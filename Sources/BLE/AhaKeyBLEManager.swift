import AppKit
import Combine
import CoreBluetooth
import Foundation
import os.log
import UserNotifications

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "BLE")

/// 通信日志条目
struct BLELogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

/// AhaKey-X1 BLE 通信管理器
@MainActor
final class AhaKeyBLEManager: NSObject, ObservableObject {
    typealias CommandResponse = (status: UInt8, payload: Data)

    struct OLEDUploadProgress: Equatable {
        let completedChunks: Int
        let totalChunks: Int
        let completedFrames: Int
        let totalFrames: Int

        var fractionCompleted: Double {
            guard totalChunks > 0 else { return 0 }
            return Double(completedChunks) / Double(totalChunks)
        }
    }

    // MARK: - Published State

    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName: String?
    @Published private(set) var batteryLevel: Int = 0
    @Published private(set) var signalStrength: Int = 0
    @Published private(set) var firmwareMainVersion: Int = 0
    @Published private(set) var firmwareSubVersion: Int = 0
    @Published private(set) var firmwareRevision: String = "—"
    @Published private(set) var modelNumber: String = "—"
    @Published private(set) var workMode: Int = 0
    @Published private(set) var lightMode: Int = 0
    @Published private(set) var switchState: Int = 0
    @Published private(set) var bleConnectionStatus: String = "未连接"
    @Published private(set) var bleDeviceUUID: String = "—"
    @Published private(set) var oledUploadProgress: OLEDUploadProgress?
    @Published private(set) var isUploadingOLED = false

    /// 通信日志（最近 200 条）
    @Published private(set) var commLog: [BLELogEntry] = []
    private let maxLogEntries = 200

    // 特征就绪状态
    @Published private(set) var dataCharReady = false
    @Published private(set) var commandCharReady = false
    @Published private(set) var notifyCharReady = false

    // MARK: - BLE Constants

    // AhaKey 主服务
    static let serviceUUID = CBUUID(string: "7340")
    static let dataCharUUID = CBUUID(string: "7341")
    static let infoCharUUID = CBUUID(string: "7342")
    static let commandCharUUID = CBUUID(string: "7343")
    static let notifyCharUUID = CBUUID(string: "7344")

    // 标准 Battery Service
    static let batteryServiceUUID = CBUUID(string: "180F")
    static let batteryLevelCharUUID = CBUUID(string: "2A19")

    // 标准 Device Information Service
    static let deviceInfoServiceUUID = CBUUID(string: "180A")
    static let firmwareRevisionCharUUID = CBUUID(string: "2A26")
    static let modelNumberCharUUID = CBUUID(string: "2A24")

    nonisolated static let deviceNamePrefix = "vibe code"

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?
    private var pendingConnect = false
    private var rssiTimer: Timer?
    private var autoReconnectTimer: Timer?
    private var statusPollTimer: Timer?
    /// 记住上次连接的 UUID，用于快速重连
    private var lastPeripheralUUID: UUID?
    /// 为 true 时，本 App 不扫描、不连接、不响应掉线/轮询重连（物理键盘由 `ahakeyconfig-agent` 占用时由 AgentManager 置位）
    private var suppressAutomaticConnection = false
    /// 防止 onAllCharacteristicsReady 重复触发
    private var didQueryAfterConnect = false
    /// 写入队列：避免连发导致设备过载
    private var writeQueue: [(Data, String)] = []
    private var isWriting = false
    /// 与 `writeQueue` 前缀顺序对应的各批 `writeCommandsSequentially` 剩余条数与完成回调。
    private struct WriteCommandBatch {
        var commandsRemaining: Int
        var completion: (() -> Void)?
    }

    private var writeBatches: [WriteCommandBatch] = []
    private var protocolResponseWaiters: [UInt8: CheckedContinuation<CommandResponse, Error>] = [:]
    private var dataWriteResultContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Init

    override init() {
        super.init()
        // 与 AgentManager 启动顺序无关：若上次退出前选择「Agent 占蓝牙」，
        // 在蓝牙栈 poweredOn 回调里会立刻重连，必须在 init 就挡住。
        let storedOwner = UserDefaults.standard.string(forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner")
        if storedOwner == nil || storedOwner == BluetoothConnectionOwner.agentDaemon.rawValue {
            suppressAutomaticConnection = true
        }
        central = CBCentralManager(delegate: nil, queue: nil)
        central.delegate = self
        startAutoReconnectPolling()
    }

    // MARK: - Public API

    /// 由「设备信息 / 顶栏」等**用户显式**发起连接时调用：取消「交给 Agent」时的抑制并尝试连接。
    func userInitiatedConnect() {
        suppressAutomaticConnection = false
        connectAutomatically()
    }

    /// 与 `AgentManager` 的蓝牙占用方一致：交给 Agent 时为 true，交回本 App 时为 false。
    func setSuppressedForAgentOwningKeyboard(_ suppress: Bool) {
        suppressAutomaticConnection = suppress
    }

    func connectAutomatically() {
        guard !suppressAutomaticConnection else { return }
        guard central.state == .poweredOn else {
            pendingConnect = true
            return
        }

        // 1. 用已知 UUID 直连（最快）
        if let uuid = lastPeripheralUUID {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                appendLog("用已知 UUID 直连: \(p.name ?? uuid.uuidString)")
                self.peripheral = p
                p.delegate = self
                central.connect(p, options: nil)
                bleConnectionStatus = "连接中…"
                return
            }
        }

        // 2. 查找系统已连接设备
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
        if let existing = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(Self.deviceNamePrefix) }) {
            appendLog("发现系统已连接设备: \(existing.name ?? "?")")
            self.peripheral = existing
            existing.delegate = self
            central.connect(existing, options: nil)
            bleConnectionStatus = "连接中…"
            return
        }

        // 3. 扫描
        startScan()
    }

    func startScan() {
        guard central.state == .poweredOn else {
            pendingConnect = true
            return
        }
        isScanning = true
        bleConnectionStatus = "扫描中…"
        appendLog("开始扫描 AhaKey 设备…")
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            if self.isScanning {
                self.central.stopScan()
                self.isScanning = false
                self.bleConnectionStatus = "等待设备"
                self.appendLog("扫描超时，继续后台轮询设备")
            }
        }
    }

    func disconnect() {
        guard let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
        appendLog("用户主动断开")
    }

    /// 发送原始命令到 0x7343（带队列，防止连发过载）
    func writeCommand(_ data: Data) {
        guard let commandChar, let peripheral else {
            appendLog("命令通道未就绪", isError: true)
            return
        }
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: writeType)
        appendLog("→ CMD \(data.count)B: \(data.hexString)")
    }

    func uploadOLEDFrames(_ frames: [Data], fps: Int, mode: UInt8 = 0, startIndex: UInt16 = 0) async throws {
        guard let peripheral, let dataChar, let commandChar else {
            throw OLEDUploadError.channelNotReady
        }
        guard !frames.isEmpty else {
            throw OLEDUploadError.noFrames
        }
        guard frames.count <= AhaKeyCommand.oledMaxFrames else {
            throw OLEDUploadError.tooManyFrames(max: AhaKeyCommand.oledMaxFrames)
        }

        isUploadingOLED = true
        oledUploadProgress = OLEDUploadProgress(
            completedChunks: 0,
            totalChunks: frames.reduce(0) { partialResult, frame in
                partialResult + max(1, Int(ceil(Double(frame.count) / Double(AhaKeyCommand.oledChunkSize))))
            },
            completedFrames: 0,
            totalFrames: frames.count
        )
        appendLog("开始上传 OLED 数据: \(frames.count) 帧, FPS=\(fps), mode=\(mode), startIndex=\(startIndex), frameSlotSize=\(AhaKeyCommand.oledFrameSlotSize)")

        defer {
            isUploadingOLED = false
            oledUploadProgress = nil
        }

        let writeType: CBCharacteristicWriteType =
            dataChar.properties.contains(.write) ? .withResponse : .withoutResponse
        var completedChunks = 0

        for (frameIndex, frame) in frames.enumerated() {
            let frameAddress = UInt32(Int(startIndex) + frameIndex) * UInt32(AhaKeyCommand.oledFrameSlotSize)
            appendLog("  帧 #\(frameIndex) 物理地址=0x\(String(format: "%08X", frameAddress))=\(frameAddress), 大小=\(frame.count)B")
            let chunks = stride(from: 0, to: frame.count, by: AhaKeyCommand.oledChunkSize).map { offset in
                let end = min(offset + AhaKeyCommand.oledChunkSize, frame.count)
                return (offset: offset, data: Data(frame[offset ..< end]))
            }

            for chunk in chunks {
                let address = frameAddress + UInt32(chunk.offset)
                let prepare = AhaKeyCommand.prepareWrite(chunkLength: chunk.data.count, address: address)
                _ = try await sendCommandAwaitingResponse(prepare, expectedCommand: AhaKeyCommand.cmdPrepareWrite)

                try await writeDataChunk(chunk.data, to: peripheral, characteristic: dataChar, type: writeType)
                completedChunks += 1
                oledUploadProgress = OLEDUploadProgress(
                    completedChunks: completedChunks,
                    totalChunks: oledUploadProgress?.totalChunks ?? completedChunks,
                    completedFrames: frameIndex,
                    totalFrames: frames.count
                )
            }

            oledUploadProgress = OLEDUploadProgress(
                completedChunks: completedChunks,
                totalChunks: oledUploadProgress?.totalChunks ?? completedChunks,
                completedFrames: frameIndex + 1,
                totalFrames: frames.count
            )
        }

        let delay = UInt16(max(1, 1000 / max(1, fps)))
        let updateCommand = AhaKeyCommand.updatePicture(
            mode: mode,
            startIndex: startIndex,
            frameCount: UInt16(frames.count),
            timeDelayMs: delay
        )
        appendLog("→ updatePicture mode=\(mode) startIndex=\(startIndex) frameCount=\(frames.count) delayMs=\(delay) hex=\(updateCommand.hexString)")
        _ = try await sendCommandAwaitingResponse(updateCommand, expectedCommand: AhaKeyCommand.cmdUpdatePic)
        appendLog("OLED 上传完成: \(frames.count) 帧, start=\(startIndex)")
        _ = commandChar
    }

    /// 批量写入命令（每条间隔 50ms，避免设备过载）。**该批**全部写入后会在主线程执行 `completion`（若入队 0 条则立即执行）。
    func writeCommandsSequentially(
        _ commands: [(data: Data, label: String)],
        completion: (() -> Void)? = nil
    ) {
        if commands.isEmpty {
            completion?()
            return
        }
        writeBatches.append(WriteCommandBatch(commandsRemaining: commands.count, completion: completion))
        writeQueue.append(contentsOf: commands.map { ($0.data, $0.label) })
        drainWriteQueue()
    }

    private func drainWriteQueue() {
        guard !isWriting, !writeQueue.isEmpty else { return }
        isWriting = true
        let (data, label) = writeQueue.removeFirst()
        if !writeBatches.isEmpty {
            writeBatches[0].commandsRemaining -= 1
            if writeBatches[0].commandsRemaining == 0 {
                let c = writeBatches.removeFirst().completion
                c?()
            }
        }
        appendLog(label)
        writeCommand(data)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.isWriting = false
            self.drainWriteQueue()
        }
    }

    /// 查询设备状态
    func queryDeviceStatus() {
        let cmd = AhaKeyCommand.queryDeviceStatus()
        appendLog("查询设备状态…")
        writeCommand(cmd)
    }

    /// 设置键位映射
    func setKeyMapping(mode: UInt8 = 0, keyIndex: UInt8, hidCodes: [UInt8]) {
        let cmd = AhaKeyCommand.setKeyMapping(mode: mode, keyIndex: keyIndex, hidCodes: hidCodes)
        let keyName = "Key\(keyIndex + 1)"
        let codeNames = hidCodes.map { HIDUsage.name(for: $0) }.joined(separator: "+")
        appendLog("写入 Mode\(mode) \(keyName) 键码: \(codeNames)")
        writeCommand(cmd)
    }

    /// 设置按键宏（固件 subMacro 子类型 0x74）。
    /// - parameter macroData: 已展平的 (action, param) 字节流。固件上限 98 字节。
    func setKeyMacro(mode: UInt8 = 0, keyIndex: UInt8, macroData: [UInt8]) {
        let cmd = AhaKeyCommand.setKeyMacro(mode: mode, keyIndex: keyIndex, macroData: macroData)
        appendLog("写入 Mode\(mode) Key\(keyIndex + 1) 宏: \(macroData.count) 字节 / \(macroData.count / 2) 步")
        writeCommand(cmd)
    }

    /// 设置按键描述（显示在 OLED 上）
    func setKeyDescription(mode: UInt8 = 0, keyIndex: UInt8, text: String) {
        let cmd = AhaKeyCommand.setKeyDescription(mode: mode, keyIndex: keyIndex, text: text)
        appendLog("写入 Mode\(mode) Key\(keyIndex + 1) 描述: \(text)")
        writeCommand(cmd)
    }

    /// 保存配置到设备 Flash
    func saveConfig() {
        let cmd = AhaKeyCommand.saveConfig()
        appendLog("保存配置到设备…")
        writeCommand(cmd)
    }

    func readPictureState(mode: UInt8) async throws -> AhaKeyPictureState {
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.readPicState(mode: mode),
            expectedCommand: AhaKeyCommand.cmdReadPicState
        )
        guard let state = AhaKeyResponseParser.parsePictureStateResponse(response.payload) else {
            throw OLEDUploadError.invalidPictureStatePayload
        }
        appendLog("  图片状态 mode=\(state.mode) start=\(state.startIndex) length=\(state.picLength) interval=\(state.frameInterval) max=\(state.allModeMaxPic)")
        return state
    }

    /// 同步 IDE 状态到键盘 LED
    func updateIDEState(_ state: IDEState) {
        guard commandChar != nil else { return }
        let cmd = AhaKeyCommand.updateState(state)
        writeCommand(cmd)
    }

    /// 修改设备蓝牙名称
    func changeDeviceName(_ name: String) {
        let cmd = AhaKeyCommand.changeName(name)
        appendLog("修改设备名: \(name)")
        writeCommand(cmd)
        // 修改后保存并刷新
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.saveConfig()
        }
    }

    func clearLog() {
        commLog.removeAll()
    }

    /// 与内部 `appendLog` 相同（含 `~/Library/.../AhaKeyConfig/diagnostics/ble-comm.log` 与系统日志），供 Studio 等写入调试说明。
    func appendCommLogLine(_ message: String, isError: Bool = false) {
        appendLog(message, isError: isError)
    }

    // MARK: - Logging

    static let logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ble-comm.log")
    }()

    private func appendLog(_ message: String, isError: Bool = false) {
        let entry = BLELogEntry(timestamp: Date(), message: message, isError: isError)
        commLog.append(entry)
        if commLog.count > maxLogEntries {
            commLog.removeFirst(commLog.count - maxLogEntries)
        }
        if isError {
            log.error("\(message)")
        } else {
            log.info("\(message)")
        }
        let line = "[\(entry.formattedTime)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: Self.logFileURL.path) {
                if let fh = try? FileHandle(forWritingTo: Self.logFileURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: Self.logFileURL)
            }
        }
    }

    private func startRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.peripheral?.readRSSI()
            }
        }
    }

    private func startAutoReconnectPolling() {
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.central.state == .poweredOn else { return }
                guard !self.isConnected, !self.isScanning else { return }
                guard self.bleConnectionStatus != "连接中…" else { return }
                self.appendLog("后台轮询中，尝试寻找设备…")
                self.connectAutomatically()
            }
        }
    }

    private func stopRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    /// 周期性查询设备状态，用于感知键盘物理档位变化（workMode / switchState / lightMode）。
    /// 固件不会在档位切换时主动 push，必须靠轮询。
    private func startStatusPolling() {
        statusPollTimer?.invalidate()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isConnected else { return }
                // 正在上传 OLED 时避免占用命令通道
                guard !self.isUploadingOLED else { return }
                // 有 protocol 响应在等（如 readPictureState / saveConfig）时也跳过
                guard self.protocolResponseWaiters.isEmpty else { return }
                self.queryDeviceStatus()
            }
        }
    }

    private func stopStatusPolling() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    /// 所有 AhaKey 主服务特征就绪后触发（仅一次）
    private func onAllCharacteristicsReady() {
        guard !didQueryAfterConnect else { return }
        didQueryAfterConnect = true
        appendLog("所有特征就绪，查询设备状态")
        queryDeviceStatus()
    }

    private func sendCommandAwaitingResponse(_ data: Data, expectedCommand: UInt8, timeoutSeconds: Double = 5.0) async throws -> CommandResponse {
        defer { protocolResponseWaiters[expectedCommand] = nil }
        return try await withThrowingTaskGroup(of: CommandResponse.self) { group in
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResponse, Error>) in
                    Task { @MainActor in
                        self?.protocolResponseWaiters[expectedCommand] = continuation
                        self?.writeCommand(data)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw OLEDUploadError.timeout(command: expectedCommand)
            }

            let result = try await group.next() ?? (status: 0, payload: Data())
            group.cancelAll()
            guard result.status == 0 else {
                throw OLEDUploadError.deviceRejected(command: expectedCommand, status: result.status)
            }
            return result
        }
    }

    private func writeDataChunk(
        _ data: Data,
        to peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType,
        timeoutSeconds: Double = 5.0
    ) async throws {
        defer { dataWriteResultContinuation = nil }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        self?.dataWriteResultContinuation = continuation
                        let negotiatedLength = max(1, peripheral.maximumWriteValueLength(for: type))
                        // 固件侧按 oledPacketSize (≈180B) 组帧，必须以它为子包上限，
                        // 否则会触发 CoreBluetooth "value's length is invalid" 或固件直接丢帧。
                        let maxPacketLength = min(negotiatedLength, AhaKeyCommand.oledPacketSize)
                        self?.appendLog("→ DATA \(data.count)B, 分片 \(maxPacketLength)B (协商上限 \(negotiatedLength)B)")
                        Task {
                            for offset in stride(from: 0, to: data.count, by: maxPacketLength) {
                                let end = min(offset + maxPacketLength, data.count)
                                let packet = Data(data[offset ..< end])
                                peripheral.writeValue(packet, for: characteristic, type: type)
                                try? await Task.sleep(for: .milliseconds(12))
                            }
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult)
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }
}

// MARK: - 拨杆档位切换 → 系统通知（与 `switchState` 同源，放在本文件避免独立 .swift 未被索引器收录）

/// 监听 `AhaKeyBLEManager.switchState` 的稳定变化，在拨杆切换档位时弹一条 macOS 通知。
@MainActor
final class SwitchStateNotifier: ObservableObject {
    static let shared = SwitchStateNotifier()

    private weak var bleManager: AhaKeyBLEManager?
    private var cancellable: AnyCancellable?
    private var lastObservedState: Int?
    private var lastNotificationAt: Date?
    private var hasInitialState = false
    private var hasRequestedAuthorization = false

    private init() {}

    func bind(to manager: AhaKeyBLEManager) {
        if bleManager === manager, cancellable != nil { return }

        bleManager = manager
        lastObservedState = nil
        hasInitialState = false
        cancellable = manager.$switchState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
    }

    private func handleStateChange(_ newState: Int) {
        defer { lastObservedState = newState }

        guard hasInitialState else {
            hasInitialState = true
            return
        }

        guard let previous = lastObservedState, previous != newState else { return }

        if let last = lastNotificationAt, Date().timeIntervalSince(last) < 1.5 {
            return
        }
        lastNotificationAt = Date()

        let switchedToAuto = (previous != 0 && newState == 0)
        let switchedToManual = (previous == 0 && newState != 0)

        if switchedToAuto {
            postNotification(
                title: "拨杆 → 自动批准",
                body: "Claude / Cursor 的工具调用将无条件放行（含 shell、删文件等高危操作）。需要确认时请把拨杆切回手动档。",
                identifier: "lab.jawa.ahakey.switch.auto",
                isCritical: true
            )
        } else if switchedToManual {
            postNotification(
                title: "拨杆 → 手动批准",
                body: "Claude / Cursor 将按默认弹窗逐条确认权限。",
                identifier: "lab.jawa.ahakey.switch.manual",
                isCritical: false
            )
        }
    }

    private func postNotification(title: String, body: String, identifier: String, isCritical: Bool) {
        let center = UNUserNotificationCenter.current()
        let deliver = { [weak self] in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = isCritical ? .defaultCritical : .default
            let request = UNNotificationRequest(identifier: "\(identifier).\(UUID().uuidString)",
                                                content: content,
                                                trigger: nil)
            center.add(request) { error in
                if error != nil, isCritical {
                    Task { @MainActor in
                        self?.fallbackAlert(title: title, body: body)
                    }
                }
            }
        }

        if hasRequestedAuthorization {
            deliver()
            return
        }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                deliver()
            } else if isCritical {
                Task { @MainActor in
                    self.fallbackAlert(title: title, body: body)
                }
            }
        }
    }

    private func fallbackAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

enum OLEDUploadError: LocalizedError {
    case channelNotReady
    case noFrames
    case tooManyFrames(max: Int)
    case noAvailablePictureSlot(needed: Int, max: Int)
    case timeout(command: UInt8)
    case deviceRejected(command: UInt8, status: UInt8)
    case invalidPictureStatePayload

    var errorDescription: String? {
        switch self {
        case .channelNotReady:
            return "BLE 数据通道还没准备好。"
        case .noFrames:
            return "没有可上传的图片帧。"
        case .tooManyFrames(let max):
            return "帧数超过设备上限，最多支持 \(max) 帧。"
        case .noAvailablePictureSlot(let needed, let max):
            return "动画需要 \(needed) 帧，但设备当前没有足够连续空间。总容量上限约为 \(max) 帧。"
        case .timeout(let command):
            return String(format: "等待设备响应超时: 0x%02X", command)
        case .deviceRejected(let command, let status):
            return String(format: "设备拒绝了命令 0x%02X，状态码 0x%02X", command, status)
        case .invalidPictureStatePayload:
            return "设备返回的动画槽位信息无法解析。"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension AhaKeyBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.appendLog("蓝牙已开启")
                self.connectAutomatically()
            case .poweredOff:
                self.appendLog("蓝牙已关闭", isError: true)
                self.bleConnectionStatus = "蓝牙关闭"
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.lowercased().hasPrefix(Self.deviceNamePrefix) else { return }

        Task { @MainActor in
            self.appendLog("发现设备: \(name) RSSI=\(RSSI)")
            self.central.stopScan()
            self.isScanning = false
            self.peripheral = peripheral
            peripheral.delegate = self
            self.central.connect(peripheral, options: nil)
            self.bleConnectionStatus = "连接中…"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            self.deviceName = peripheral.name
            self.bleDeviceUUID = peripheral.identifier.uuidString
            self.lastPeripheralUUID = peripheral.identifier
            self.bleConnectionStatus = "已连接"
            self.appendLog("已连接: \(peripheral.name ?? "?") UUID=\(peripheral.identifier.uuidString)")
            self.autoReconnectTimer?.invalidate()
            self.autoReconnectTimer = nil
            peripheral.discoverServices([
                Self.serviceUUID,
                Self.batteryServiceUUID,
                Self.deviceInfoServiceUUID,
            ])
            peripheral.readRSSI()
            self.startRSSIPolling()
            self.startStatusPolling()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.bleConnectionStatus = "连接失败"
            self.appendLog("连接失败: \(error?.localizedDescription ?? "未知")", isError: true)
            self.startAutoReconnectPolling()
            // 3 秒后重试
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !self.isConnected {
                    self.connectAutomatically()
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let dropped = self.writeQueue.count
            let openBatches = self.writeBatches.count
            if dropped > 0 || openBatches > 0 {
                self.appendLog(
                    "BLE 已断开，丢弃未发出命令 \(dropped) 条（未闭合批 \(openBatches) 个）。\(error.map { "原因：\($0.localizedDescription)" } ?? "")",
                    isError: true
                )
            }
            self.isConnected = false
            self.bleConnectionStatus = "已断开"
            self.dataChar = nil
            self.commandChar = nil
            self.notifyChar = nil
            self.batteryLevelChar = nil
            self.dataCharReady = false
            self.commandCharReady = false
            self.notifyCharReady = false
            // 不清 peripheral 和 lastPeripheralUUID——用于直连重试
            self.peripheral = nil
            self.writeQueue.removeAll()
            self.isWriting = false
            self.writeBatches.removeAll()
            self.didQueryAfterConnect = false
            self.stopRSSIPolling()
            self.stopStatusPolling()
            self.startAutoReconnectPolling()
            self.appendLog("已断开: \(error?.localizedDescription ?? "正常")")

            // 2 秒后自动重连
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if !self.isConnected {
                    self.appendLog("尝试自动重连…")
                    self.connectAutomatically()
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension AhaKeyBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for service in services {
                self.appendLog("发现服务: \(service.uuid)")
                switch service.uuid {
                case Self.serviceUUID:
                    peripheral.discoverCharacteristics(
                        [Self.dataCharUUID, Self.infoCharUUID, Self.commandCharUUID, Self.notifyCharUUID],
                        for: service
                    )
                case Self.batteryServiceUUID:
                    peripheral.discoverCharacteristics([Self.batteryLevelCharUUID], for: service)
                case Self.deviceInfoServiceUUID:
                    peripheral.discoverCharacteristics(
                        [Self.firmwareRevisionCharUUID, Self.modelNumberCharUUID],
                        for: service
                    )
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                switch char.uuid {
                // AhaKey 主服务特征
                case Self.dataCharUUID:
                    self.dataChar = char
                    self.dataCharReady = true
                    peripheral.setNotifyValue(true, for: char)
                    self.appendLog("数据特征(0x7341) 已订阅通知")
                case Self.commandCharUUID:
                    self.commandChar = char
                    self.commandCharReady = true
                    self.appendLog("命令特征(0x7343) 就绪")
                case Self.notifyCharUUID:
                    self.notifyChar = char
                    self.notifyCharReady = true
                    peripheral.setNotifyValue(true, for: char)
                    self.appendLog("通知特征(0x7344) 已订阅")
                case Self.infoCharUUID:
                    self.appendLog("设备信息(0x7342) 就绪")

                // 标准 Battery Level
                case Self.batteryLevelCharUUID:
                    self.batteryLevelChar = char
                    peripheral.readValue(for: char)
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                    self.appendLog("电池特征(0x2A19) 读取中")

                // 标准 Device Information
                case Self.firmwareRevisionCharUUID:
                    peripheral.readValue(for: char)
                case Self.modelNumberCharUUID:
                    peripheral.readValue(for: char)

                default:
                    break
                }
            }

            // 检查 AhaKey 三个核心特征是否全部就绪，再发查询
            if self.dataCharReady && self.commandCharReady && self.notifyCharReady {
                self.onAllCharacteristicsReady()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            self.handleNotification(from: characteristic.uuid, data: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            self.signalStrength = RSSI.intValue
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.appendLog("写入特征 \(characteristic.uuid) 失败: \(error.localizedDescription)", isError: true)
            } else {
                self.appendLog("写入特征 \(characteristic.uuid) 完成")
            }
        }
    }

    private func handleNotification(from uuid: CBUUID, data: Data) {
        let hex = data.hexString
        switch uuid {
        case Self.dataCharUUID:
            appendLog("← DATA(0x7341): \(hex)")
            parseProtocolResponse(data)
        case Self.notifyCharUUID:
            appendLog("← NOTIFY(0x7344): \(hex)")
            parseProtocolResponse(data)
        case Self.batteryLevelCharUUID:
            if let level = data.first {
                batteryLevel = Int(level)
                appendLog("← 电池: \(batteryLevel)%")
            }
        case Self.firmwareRevisionCharUUID:
            if let str = String(data: data, encoding: .utf8) {
                firmwareRevision = str
            }
        case Self.modelNumberCharUUID:
            if let str = String(data: data, encoding: .utf8) {
                modelNumber = str
            }
        default:
            appendLog("← 未知(\(uuid)): \(hex)")
        }
    }

    private func parseProtocolResponse(_ data: Data) {
        if let status = AhaKeyResponseParser.parseDeviceStatus(data) {
            batteryLevel = status.battery
            firmwareMainVersion = status.firmwareMain
            firmwareSubVersion = status.firmwareSub
            workMode = status.workMode
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": status.workMode]
            )
            lightMode = status.lightMode
            switchState = status.switchState
            appendLog("  状态: 电量=\(status.battery) 固件=\(status.firmwareMain).\(status.firmwareSub) 模式=\(status.workMode) 灯=\(status.lightMode) 开关=\(status.switchState)")
        } else if AhaKeyResponseParser.isProtocolFrame(data) {
            if let response = AhaKeyResponseParser.parseCommandResponse(data) {
                protocolResponseWaiters.removeValue(forKey: response.cmd)?.resume(returning: (response.status, response.payload))

                if response.cmd == AhaKeyCommand.cmdWriteResult {
                    if response.status == 0 {
                        dataWriteResultContinuation?.resume()
                    } else {
                        dataWriteResultContinuation?.resume(throwing: OLEDUploadError.deviceRejected(command: response.cmd, status: response.status))
                    }
                    dataWriteResultContinuation = nil
                }

                if response.status == 0 {
                    appendLog("  ✓ 命令 0x\(String(format: "%02X", response.cmd)) 成功")
                } else {
                    let payloadHex = response.payload.isEmpty ? "—" : response.payload.hexString
                    appendLog("  命令 0x\(String(format: "%02X", response.cmd)) 失败: status=0x\(String(format: "%02X", response.status)) payload=\(payloadHex)", isError: true)
                }
            }
        } else {
            let bytes = data.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
            appendLog("  原始 [\(data.count)B]: \(bytes)")
        }
    }

    /// 发送探测命令
    func sendProbeCommands() {
        guard commandChar != nil else {
            appendLog("命令通道未就绪", isError: true)
            return
        }
        appendLog("═══ 开始探测 ═══")

        let probes: [(String, Data)] = [
            ("设备状态查询", AhaKeyCommand.queryDeviceStatus()),
            ("读配置 0x01", Data([0xAA, 0xBB, 0x01, 0xCC, 0xDD])),
            ("读配置 0x03", Data([0xAA, 0xBB, 0x03, 0xCC, 0xDD])),
            ("读配置 0x05", Data([0xAA, 0xBB, 0x05, 0xCC, 0xDD])),
        ]
        for (label, data) in probes {
            appendLog("→ \(label): \(data.hexString)")
            writeCommand(data)
        }

        if let batteryLevelChar {
            peripheral?.readValue(for: batteryLevelChar)
            appendLog("→ 重读电池电量")
        }

        appendLog("═══ 探测完毕，等待回调 ═══")
    }
}

extension Notification.Name {
    /// `userInfo["workMode"]` 为 `Int`，与键盘物理档位一致。
    static let ahaKeyKeyboardWorkModeChanged = Notification.Name("lab.jawa.ahakeyconfig.keyboardWorkModeChanged")
}

// MARK: - Data Extension

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
