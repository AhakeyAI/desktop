import AppKit
import Combine
import CoreBluetooth
import Foundation
import os.log
import UserNotifications

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "BLE")

/// 0x83 查询回来的某个 mode 的图片元信息（用 Equatable struct 方便 SwiftUI .onChange 监听）
struct KeyboardPictureState: Equatable {
    let frameCount: Int
    let frameIntervalMs: Int
}

struct KeyboardTaskPictureSlot: Hashable {
    let mode: Int
    let set: Int
    let state: Int
}

enum AhaKeyProtocolMode: Equatable {
    case negotiating
    case legacy
    case current
    case restrictedUnknown
}

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
    @Published private(set) var isWiredConnected = false
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
    @Published private(set) var brightness: Int = 35
    @Published private(set) var bleConnectionStatus: String = "未连接"
    @Published private(set) var bleDeviceUUID: String = "—"
    @Published private(set) var bluetoothPermissionGranted = true
    @Published private(set) var bluetoothPoweredOn = false
    @Published private(set) var oledUploadProgress: OLEDUploadProgress?
    @Published private(set) var isUploadingOLED = false
    /// 由 ahakeyconfig-agent 写入的当前 IDE hook 状态值（IDEState.rawValue），用于画布 LED 颜色实时还原
    @Published private(set) var liveIDEStateValue: Int? = nil
    /// Agent 端 BLE 通知缓存的 lightMode/switchState/workMode（agent 占用蓝牙时主 App 自己 BLE 未连，靠这些读到键盘实时状态）
    @Published private(set) var agentLightMode: Int? = nil
    @Published private(set) var agentSwitchState: Int? = nil
    @Published private(set) var agentWorkMode: Int? = nil
    /// 各 mode flash 里的真实图片元信息。
    /// 主 App 自占 BLE 后通过 0x83 查询填充；frameCount == 0 表示用户没自定义上传，
    /// 键盘显示固件出厂动图（与 bundle/DefaultOLED 同源）。
    @Published private(set) var keyboardPictureStates: [Int: KeyboardPictureState] = [:]
    @Published private(set) var keyboardTaskPictureStates: [KeyboardTaskPictureSlot: AhaKeyTaskPictureState] = [:]
    @Published private(set) var activeTaskPictureSets: [Int: Int] = [:]
    @Published private(set) var firmwareCapabilities: AhaKeyFirmwareCapabilities?
    @Published private(set) var protocolMode: AhaKeyProtocolMode = .negotiating

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

    nonisolated static let deviceNamePrefix = "AhaKey"

    // MARK: - Private

    private var central: CBCentralManager?
    private let usbTransport = AhaKeyUSBHIDTransport()
    private var isBLEConnected = false
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?
    private var pendingConnect = false
    private var rssiTimer: Timer?
    private var autoReconnectTimer: Timer?
    private var statusPollTimer: Timer?
    private var ideStatePollTimer: Timer?
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
    private struct ProtocolResponseWaiter {
        let id: UUID
        let continuation: CheckedContinuation<CommandResponse, Error>
        let timeout: DispatchWorkItem
    }
    private struct DataWriteWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
        let timeout: DispatchWorkItem
    }
    private var protocolResponseWaiters: [UInt8: ProtocolResponseWaiter] = [:]
    private var dataWriteWaiter: DataWriteWaiter?
    private var dataPacketWriteTask: Task<Void, Never>?
    private var forceBLEPictureTransfer = false
    private var writeWithoutResponseReadyContinuation: CheckedContinuation<Void, Never>?
    private var currentUploadSessionID: UInt16?

    // MARK: - Init

    override init() {
        super.init()
        usbTransport.onConnected = { [weak self] in
            Task { @MainActor in self?.usbDidConnect() }
        }
        usbTransport.onDisconnected = { [weak self] in
            Task { @MainActor in self?.usbDidDisconnect() }
        }
        usbTransport.onFrame = { [weak self] data in
            Task { @MainActor in self?.handleUSBFrame(data) }
        }
        usbTransport.onError = { [weak self] error in
            Task { @MainActor in self?.appendLog("USB HID: \(error.localizedDescription)", isError: true) }
        }
        usbTransport.start()
        let storedOwner = UserDefaults.standard.string(forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner")
        if storedOwner == nil || storedOwner == BluetoothConnectionOwner.agentDaemon.rawValue {
            suppressAutomaticConnection = true
        }
        // 只有蓝牙权限已授予时才创建 CBCentralManager（创建即触发系统弹窗）。
        // 权限未决时延迟到用户点「申请」后调用 ensureCentralManager()。
        if CBCentralManager.authorization == .allowedAlways {
            central = CBCentralManager(delegate: self, queue: nil)
        }
        refreshBluetoothAuthorization()
        startAutoReconnectPolling()
        startIDEStatePolling()
    }

    /// 确保 CBCentralManager 已创建。用户显式申请蓝牙权限时调用。
    func ensureCentralManager() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    private var hasConfigurationTransport: Bool {
        isWiredConnected || (peripheral != nil && commandChar != nil && dataChar != nil)
    }

    private func usbDidConnect() {
        guard !isWiredConnected else { return }
        isWiredConnected = true
        isConnected = true
        deviceName = "AhaKey USB"
        bleDeviceUUID = "USB 413C:2107"
        bleConnectionStatus = "有线已连接"
        didQueryAfterConnect = false
        protocolMode = .negotiating
        firmwareCapabilities = nil
        appendLog("USB HID 有线配置通道已连接")
        startStatusPolling()
        onAllCharacteristicsReady()
    }

    private func usbDidDisconnect() {
        guard isWiredConnected else { return }
        isWiredConnected = false
        cancelPendingTransferWaiters(reason: .connectionLost)
        isConnected = isBLEConnected
        if isBLEConnected {
            deviceName = peripheral?.name
            bleDeviceUUID = peripheral?.identifier.uuidString ?? "—"
            bleConnectionStatus = "已连接"
        } else {
            deviceName = nil
            bleDeviceUUID = "—"
            bleConnectionStatus = "已断开"
            stopStatusPolling()
            startAutoReconnectPolling()
        }
        appendLog("USB HID 有线配置通道已断开")
    }

    var supportedTaskDisplayStates: [AhaKeyTaskDisplayState] {
        firmwareCapabilities?.supportedTaskDisplayStates
            ?? AhaKeyTaskDisplayState.allCases.filter { $0 != .idle }
    }

    var allowsTaskPictureConfiguration: Bool {
        protocolMode == .legacy || protocolMode == .current
    }

    private func handleUSBFrame(_ data: Data) {
        appendLog("← USB: \(data.hexString)")
        parseProtocolResponse(data)
    }

    // MARK: - Public API

    func refreshBluetoothAuthorization() {
        bluetoothPermissionGranted = Self.currentBluetoothAuthorizationGranted()
        bluetoothPoweredOn = central?.state == .poweredOn
        if !bluetoothPermissionGranted {
            bleConnectionStatus = "蓝牙权限未开启"
        } else if central?.state == .poweredOff {
            bleConnectionStatus = "蓝牙关闭"
        }
    }

    var bluetoothAuthorizationCanPrompt: Bool {
        CBCentralManager.authorization == .notDetermined
    }

    var bluetoothAuthorizationDeniedOrRestricted: Bool {
        switch CBCentralManager.authorization {
        case .restricted, .denied:
            return true
        case .allowedAlways, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private static func currentBluetoothAuthorizationGranted() -> Bool {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            return true
        case .notDetermined:
            return true
        case .restricted, .denied:
            return false
        @unknown default:
            return true
        }
    }

    /// 由「设备信息 / 顶栏」等**用户显式**发起连接时调用：取消「交给 Agent」时的抑制并尝试连接。
    func userInitiatedConnect() {
        ensureCentralManager()
        suppressAutomaticConnection = false
        connectAutomatically()
    }

    /// 与 `AgentManager` 的蓝牙占用方一致：交给 Agent 时为 true，交回本 App 时为 false。
    func setSuppressedForAgentOwningKeyboard(_ suppress: Bool) {
        suppressAutomaticConnection = suppress
    }

    func connectAutomatically() {
        if usbTransport.isConnected {
            usbDidConnect()
            return
        }
        guard !suppressAutomaticConnection else { return }
        guard central?.state == .poweredOn else {
            pendingConnect = true
            return
        }

        // 1. 用已知 UUID 直连（最快）
        if let uuid = lastPeripheralUUID {
            let known = central?.retrievePeripherals(withIdentifiers: [uuid]) ?? []
            if let p = known.first {
                appendLog("用已知 UUID 直连: \(p.name ?? uuid.uuidString)")
                self.peripheral = p
                p.delegate = self
                central?.connect(p, options: nil)
                bleConnectionStatus = "连接中…"
                return
            }
        }

        // 2. 查找系统已连接设备
        let connected = central?.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]) ?? []
        if let existing = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(Self.deviceNamePrefix.lowercased()) }) {
            appendLog("发现系统已连接设备: \(existing.name ?? "?")")
            self.peripheral = existing
            existing.delegate = self
            central?.connect(existing, options: nil)
            bleConnectionStatus = "连接中…"
            return
        }

        // 3. 扫描
        startScan()
    }

    func startScan() {
        guard central?.state == .poweredOn else {
            pendingConnect = true
            return
        }
        isScanning = true
        bleConnectionStatus = "扫描中…"
        appendLog("开始扫描 AhaKey 设备…")
        central?.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Double(10) * 1_000_000_000))
            if self.isScanning {
                self.central?.stopScan()
                self.isScanning = false
                self.bleConnectionStatus = "等待设备"
                self.appendLog("扫描超时，继续后台轮询设备")
            }
        }
    }

    func disconnect() {
        if isWiredConnected {
            appendLog("USB 有线连接由拔线断开")
            return
        }
        guard let peripheral else { return }
        central?.cancelPeripheralConnection(peripheral)
        appendLog("用户主动断开")
    }

    /// 发送原始命令到 0x7343（带队列，防止连发过载）
    func writeCommand(_ data: Data, forceBLE: Bool = false) {
        if isWiredConnected && !forceBLE {
            do {
                try usbTransport.sendCommand(data)
                appendLog("→ USB CMD \(data.count)B: \(data.hexString)")
                return
            } catch {
                appendLog(
                    "USB 命令发送失败，尝试回退 BLE: \(error.localizedDescription)",
                    isError: true
                )
            }
        }
        guard let commandChar, let peripheral else {
            appendLog("命令通道未就绪", isError: true)
            return
        }
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: writeType)
        appendLog("→ CMD \(data.count)B: \(data.hexString)")
    }

    func uploadOLEDFrames(
        _ frames: [Data],
        fps: Int,
        mode: UInt8 = 0,
        startIndex: UInt16 = 0,
        preserveDefaultPictureBinding: Bool = false,
        resetTransportPreference: Bool = true
    ) async throws {
        if resetTransportPreference {
            forceBLEPictureTransfer = false
        }
        guard isWiredConnected || (peripheral != nil && dataChar != nil && commandChar != nil) else {
            throw OLEDUploadError.channelNotReady
        }
        guard !frames.isEmpty else {
            throw OLEDUploadError.noFrames
        }
        guard frames.count <= AhaKeyCommand.oledMaxFrames else {
            throw OLEDUploadError.tooManyFrames(max: AhaKeyCommand.oledMaxFrames)
        }
        guard frames.allSatisfy({ $0.count == AhaKeyCommand.oledEncodedFrameBytes }) else {
            throw OLEDUploadError.invalidEncodedFrameSize
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
        appendLog("开始上传 LCD 数据: \(frames.count) 帧, FPS=\(fps), mode=\(mode), startIndex=\(startIndex), frameSlotSize=\(AhaKeyCommand.oledFrameSlotSize)")

        let usesSessionUpload = firmwareCapabilities?.supportsSessionUpload == true
        var uploadFinished = false
        defer {
            if !uploadFinished, let sessionID = currentUploadSessionID {
                writeCommand(
                    AhaKeyCommand.abortPictureWrite(sessionID: sessionID),
                    forceBLE: forceBLEPictureTransfer
                )
            }
            currentUploadSessionID = nil
            isUploadingOLED = false
            oledUploadProgress = nil
        }

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
                var chunkAttempt = 0
                while true {
                    chunkAttempt += 1
                    let prepare: Data
                    let expectedCommand: UInt8
                    if usesSessionUpload {
                        let sessionID = UInt16.random(in: 1 ... UInt16.max)
                        currentUploadSessionID = sessionID
                        prepare = AhaKeyCommand.prepareSessionWrite(
                            sessionID: sessionID,
                            chunkLength: chunk.data.count,
                            address: address
                        )
                        expectedCommand = AhaKeyCommand.cmdPrepareSessionWrite
                    } else {
                        prepare = AhaKeyCommand.prepareWrite(
                            chunkLength: chunk.data.count,
                            address: address
                        )
                        expectedCommand = AhaKeyCommand.cmdPrepareWrite
                    }
                    let prepareResponse = try await sendCommandAwaitingResponse(
                        prepare,
                        expectedCommand: expectedCommand,
                        forceBLE: forceBLEPictureTransfer
                    )
                    guard prepareResponse.status == 0 else {
                        throw OLEDUploadError.deviceRejected(
                            command: expectedCommand,
                            status: prepareResponse.status
                        )
                    }

                    do {
                        try await writeDataChunk(chunk.data)
                        currentUploadSessionID = nil
                        break
                    } catch OLEDUploadError.timeout(let command)
                        where command == AhaKeyCommand.cmdWriteResult &&
                            chunkAttempt == 1 &&
                            isWiredConnected &&
                            peripheral != nil &&
                            dataChar != nil {
                        forceBLEPictureTransfer = true
                        if let sessionID = currentUploadSessionID {
                            let abortResponse = try await sendCommandAwaitingResponse(
                                AhaKeyCommand.abortPictureWrite(sessionID: sessionID),
                                expectedCommand: AhaKeyCommand.cmdAbortPictureWrite,
                                timeoutSeconds: 2.0,
                                forceBLE: true
                            )
                            guard abortResponse.status == 0 else {
                                throw OLEDUploadError.deviceRejected(
                                    command: AhaKeyCommand.cmdAbortPictureWrite,
                                    status: abortResponse.status
                                )
                            }
                        }
                        currentUploadSessionID = nil
                        appendLog("当前数据块 USB 确认丢失，立即改用 BLE 重写", isError: true)
                    }
                }
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

        if preserveDefaultPictureBinding {
            let finishCommand = AhaKeyCommand.finishTaskPictureWrite()
            appendLog("→ finishTaskPictureWrite mode=\(mode) startIndex=\(startIndex) hex=\(finishCommand.hexString)")
            let finishResponse = try await sendCommandAwaitingResponse(
                finishCommand,
                expectedCommand: AhaKeyCommand.cmdFinishTaskPicWrite
            )
            guard finishResponse.status == 0 else {
                throw OLEDUploadError.deviceRejected(
                    command: AhaKeyCommand.cmdFinishTaskPicWrite,
                    status: finishResponse.status
                )
            }
        } else {
            let delay = UInt16(max(1, 1000 / max(1, fps)))
            let updateCommand = AhaKeyCommand.updatePicture(
                mode: mode,
                startIndex: startIndex,
                frameCount: UInt16(frames.count),
                timeDelayMs: delay
            )
            appendLog("→ updatePicture mode=\(mode) startIndex=\(startIndex) frameCount=\(frames.count) delayMs=\(delay) hex=\(updateCommand.hexString)")
            let updateResponse = try await sendCommandAwaitingResponse(
                updateCommand,
                expectedCommand: AhaKeyCommand.cmdUpdatePic
            )
            guard updateResponse.status == 0 else {
                throw OLEDUploadError.deviceRejected(
                    command: AhaKeyCommand.cmdUpdatePic,
                    status: updateResponse.status
                )
            }
        }
        uploadFinished = true
        appendLog("LCD 上传完成: \(frames.count) 帧, start=\(startIndex)")
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
            try? await Task.sleep(nanoseconds: UInt64(50) * 1_000_000)
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

    /// 设置按键描述（显示在 LCD 上）
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

    /// Reuse the proven 0x80/data frame writer, then bind the uploaded range to a task GIF slot.
    /// Task resources must not use 0x82: that command replaces the normal per-mode animation binding.
    func uploadTaskOLEDFrames(_ frames: [Data], fps: Int, mode: UInt8, set: UInt8, state: UInt8, startIndex: UInt16) async throws {
        forceBLEPictureTransfer = false
        let delay = UInt16(max(1, 1000 / max(1, fps)))
        // One image's transient BLE hiccup (timeout / superseded / a stale
        // metadata read) should not fail the whole multi-image sync. Retry the
        // write+confirm for this single slot a few times before giving up, so
        // the caller only sees a hard failure after the device really refuses.
        let maxAttempts = 3
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                try await uploadOLEDFrames(
                    frames,
                    fps: fps,
                    mode: mode,
                    startIndex: startIndex,
                    preserveDefaultPictureBinding: true,
                    resetTransportPreference: false
                )
                _ = try await sendCommandAwaitingResponse(
                    AhaKeyCommand.updateTaskPictureSet(mode: mode, set: set, state: state, startIndex: startIndex, frameCount: UInt16(frames.count), timeDelayMs: delay),
                    expectedCommand: AhaKeyCommand.cmdUpdateTaskPicSet
                )
                let confirmed = try await readTaskPictureState(mode: mode, set: set, state: state)
                guard confirmed.startIndex == Int(startIndex), confirmed.picLength == frames.count,
                      confirmed.frameInterval == Int(delay) else {
                    throw OLEDUploadError.taskPictureMetadataMismatch
                }
                let slot = KeyboardTaskPictureSlot(mode: Int(mode), set: Int(set), state: Int(state))
                keyboardTaskPictureStates[slot] = AhaKeyTaskPictureState(
                    mode: Int(mode), set: Int(set), state: Int(state), startIndex: Int(startIndex), picLength: frames.count,
                    frameInterval: Int(delay), allModeMaxPic: AhaKeyCommand.oledMaxFrames, activeSet: activeTaskPictureSets[Int(mode)] ?? 0
                )
                return
            } catch let error as OLEDUploadError {
                // Cancellation and permanent failures must surface immediately;
                // only transient transport-level errors are worth retrying.
                switch error {
                case .cancelled, .connectionLost, .noFrames, .tooManyFrames, .channelNotReady, .noAvailablePictureSlot:
                    throw error
                default:
                    lastError = error
                }
            } catch is CancellationError {
                throw OLEDUploadError.cancelled
            }
            if attempt < maxAttempts {
                appendCommLogLine("任务图写入第 \(attempt) 次失败，重试中…（mode\(mode) 套图\(set) 状态\(state)）", isError: true)
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                if Task.isCancelled { throw OLEDUploadError.cancelled }
            }
        }
        throw lastError ?? OLEDUploadError.taskPictureMetadataMismatch
    }

    func clearTaskPicture(mode: UInt8, set: UInt8, state: UInt8) async throws {
        _ = try await sendCommandAwaitingResponse(
            AhaKeyCommand.updateTaskPictureSet(mode: mode, set: set, state: state, startIndex: 0, frameCount: 0, timeDelayMs: 0),
            expectedCommand: AhaKeyCommand.cmdUpdateTaskPicSet
        )
        let confirmed = try await readTaskPictureState(mode: mode, set: set, state: state)
        guard confirmed.startIndex == 0, confirmed.picLength == 0, confirmed.frameInterval == 0 else {
            throw OLEDUploadError.taskPictureMetadataMismatch
        }
        let slot = KeyboardTaskPictureSlot(mode: Int(mode), set: Int(set), state: Int(state))
        keyboardTaskPictureStates[slot] = AhaKeyTaskPictureState(
            mode: Int(mode), set: Int(set), state: Int(state), startIndex: 0, picLength: 0, frameInterval: 0,
            allModeMaxPic: AhaKeyCommand.oledMaxFrames, activeSet: activeTaskPictureSets[Int(mode)] ?? 0
        )
    }

    func readTaskPictureState(mode: UInt8, set: UInt8, state: UInt8) async throws -> AhaKeyTaskPictureState {
        let response = try await sendCommandAwaitingResponse(AhaKeyCommand.readTaskPictureSet(mode: mode, set: set, state: state), expectedCommand: AhaKeyCommand.cmdReadTaskPicSet)
        guard let picture = AhaKeyResponseParser.parseTaskPictureSetResponse(response.payload) else { throw OLEDUploadError.invalidTaskPictureStatePayload }
        keyboardTaskPictureStates[KeyboardTaskPictureSlot(mode: picture.mode, set: picture.set, state: picture.state)] = picture
        activeTaskPictureSets[picture.mode] = picture.activeSet
        return picture
    }

    func readAllTaskPictureStates() async throws -> [AhaKeyTaskPictureState] {
        var result: [AhaKeyTaskPictureState] = []
        var failedReads = 0
        for mode in 0 ..< AhaKeyCommand.oledModeCount {
            for set in 0 ..< 2 {
                for state in supportedTaskDisplayStates {
                    do {
                        result.append(try await readTaskPictureState(mode: UInt8(mode), set: UInt8(set), state: UInt8(state.rawValue)))
                    } catch OLEDUploadError.cancelled {
                        throw OLEDUploadError.cancelled
                    } catch OLEDUploadError.connectionLost {
                        throw OLEDUploadError.connectionLost
                    } catch {
                        // Per-slot tolerance: a single read hiccup must not blank
                        // out the whole device-state snapshot. A missing slot only
                        // means *that* slot is treated as empty (and may re-upload);
                        // the slots that did read keep their lengths so unchanged
                        // images are not needlessly re-sent.
                        failedReads += 1
                        appendCommLogLine("槽位状态读取失败（mode\(mode) 套图\(set) 状态\(state)），按空槽处理：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
        // Only treat the whole snapshot as unavailable when nothing came back at
        // all (e.g. firmware without the task-picture command). A partial read is
        // still useful for the incremental diff.
        if failedReads > 0 {
            throw OLEDUploadError.invalidTaskPictureStatePayload
        }
        return result
    }

    func setActiveTaskPictureSet(mode: UInt8, set: UInt8) async throws {
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.setActiveTaskPictureSet(mode: mode, set: set),
            expectedCommand: AhaKeyCommand.cmdSetActiveTaskPicSet
        )
        guard response.payload.count >= 2 else { throw OLEDUploadError.invalidTaskPictureStatePayload }
        activeTaskPictureSets[Int(response.payload[0])] = Int(response.payload[1])
    }

    func saveConfigAwaitingResponse() async throws {
        _ = try await sendCommandAwaitingResponse(AhaKeyCommand.saveConfig(), expectedCommand: AhaKeyCommand.cmdSaveConfig)
    }

    /// 同步 IDE 状态到键盘 LED
    func updateIDEState(_ state: IDEState) {
        guard hasConfigurationTransport else { return }
        let cmd = AhaKeyCommand.updateState(state)
        writeCommand(cmd)
    }

    /// 最新固件中 0x91 已改为灯效预览；虚拟拨杆只保留软件覆盖，不再向键盘发送旧 0x91。
    /// value: 0=auto/up, 1=manual/down, 2=mid
    func setSwitchStateViaBLE(_ value: UInt8) {
        appendLog("虚拟拨杆 sw_state=\(value) 仅作为软件覆盖；最新固件 0x91 用于灯效预览。")
    }

    func setLightMapping(mode: UInt8, stateEffects: [UInt8]) {
        guard hasConfigurationTransport else { return }
        writeCommand(AhaKeyCommand.setLightMapping(mode: mode, stateEffects: stateEffects))
        appendLog("→ 灯效映射 mode=\(mode) effects=\(stateEffects)")
    }

    func setBrightness(_ value: UInt8) {
        guard hasConfigurationTransport else { return }
        writeCommand(AhaKeyCommand.setBrightness(value))
        appendLog("→ 亮度 \(value)")
    }

    func previewLightEffect(_ effect: UInt8) {
        guard hasConfigurationTransport else { return }
        writeCommand(AhaKeyCommand.previewLightEffect(effect))
        appendLog("→ 预览灯效 \(effect)")
    }

    func setWorkMode(_ mode: UInt8) {
        guard hasConfigurationTransport else { return }
        writeCommand(AhaKeyCommand.setWorkMode(mode))
        appendLog("→ 工作模式 \(mode)")
    }

    /// 修改设备蓝牙名称
    func changeDeviceName(_ name: String) {
        let cmd = AhaKeyCommand.changeName(name)
        appendLog("修改设备名: \(name)")
        writeCommand(cmd)
        // 修改后保存并刷新
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(100) * 1_000_000)
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
                guard self.central?.state == .poweredOn else { return }
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
                // 正在上传 LCD 时避免占用命令通道
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

    private func startIDEStatePolling() {
        ideStatePollTimer?.invalidate()
        ideStatePollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pollIDEStateFile()
            }
        }
    }

    /// 主动触发一次共享文件读取（用户点击虚拟拨杆后立即调用，避免等下一次定时 poll）
    func refreshAgentStateFromFileNow() {
        pollIDEStateFile()
    }

    /// 点击虚拟拨杆瞬间的乐观更新值。在文件 poll 把 agentSwitchState 刷新到目标值前先顶住，
    /// 之后 polling 把真实值刷过来时再清掉，保证按一下立刻看到拨杆切档。
    @Published private(set) var optimisticSwitchOverride: Int? = nil

    func applyOptimisticSwitchOverride(_ value: UInt8) {
        optimisticSwitchOverride = Int(value)
    }

    private func clearOptimisticSwitchOverrideIfMatched() {
        guard let opt = optimisticSwitchOverride else { return }
        if agentSwitchState == opt || (isConnected && switchState == opt) {
            optimisticSwitchOverride = nil
        }
    }

    private func pollIDEStateFile() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/current-ide-state.json")
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
            if agentLightMode != nil { agentLightMode = nil }
            if agentSwitchState != nil { agentSwitchState = nil }
            if agentWorkMode != nil { agentWorkMode = nil }
            return
        }
        let now = Date().timeIntervalSince1970
        // stateValue 是瞬时态（hook 触发），30s 过期；超时则置空，固件 LED 也会回到无 state 默认
        if let v = obj["stateValue"] as? Int,
           let stateTs = (obj["stateTs"] as? Double) ?? (obj["ts"] as? Double),
           now - stateTs <= 30 {
            if liveIDEStateValue != v { liveIDEStateValue = v }
        } else {
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
        }
        // lightMode/switchState/workMode 来自 BLE 通知，2 分钟没新数据视为 agent 已断连
        if let topTs = obj["ts"] as? Double, now - topTs <= 120 {
            let lm = obj["lightMode"] as? Int
            let sw = obj["switchState"] as? Int
            let wm = obj["workMode"] as? Int
            if agentLightMode != lm { agentLightMode = lm }
            if agentSwitchState != sw { agentSwitchState = sw }
            if agentWorkMode != wm { agentWorkMode = wm }
        } else {
            if agentLightMode != nil { agentLightMode = nil }
            if agentSwitchState != nil { agentSwitchState = nil }
            if agentWorkMode != nil { agentWorkMode = nil }
        }
        clearOptimisticSwitchOverrideIfMatched()
    }

    /// 所有 AhaKey 主服务特征就绪后触发（仅一次）
    private func onAllCharacteristicsReady() {
        guard hasConfigurationTransport else { return }
        guard !didQueryAfterConnect else { return }
        didQueryAfterConnect = true
        appendLog("所有特征就绪，开始顺序握手")
        Task { [weak self] in
            guard let self else { return }
            self.queryDeviceStatus()
            try? await Task.sleep(nanoseconds: UInt64(200) * 1_000_000)
            await self.queryFirmwareCapabilities()
            await self.queryAllPictureStates()
        }
    }

    private func queryFirmwareCapabilities() async {
        var lastFailure = "设备未返回能力帧"
        for attempt in 1 ... 3 {
            do {
                let response = try await sendCommandAwaitingResponse(
                    AhaKeyCommand.queryCapabilities(),
                    expectedCommand: AhaKeyCommand.cmdCapabilities,
                    timeoutSeconds: 2.0
                )
                guard response.status == 0 else {
                    lastFailure = String(
                        format: "能力查询被设备拒绝，状态码 0x%02X",
                        response.status
                    )
                    continue
                }
                guard let capabilities = AhaKeyResponseParser.parseCapabilities(response.payload) else {
                    lastFailure = "能力帧长度或字段无效"
                    continue
                }
                firmwareCapabilities = capabilities
                protocolMode = capabilities.protocolVersion == 3 ? .current : .restrictedUnknown
                appendLog(
                    "协议 v\(capabilities.protocolVersion)，\(capabilities.modeCount) modes，"
                        + "\(capabilities.stateCount) states，BLE packet \(capabilities.maxPacketSize)B"
                )
                return
            } catch {
                lastFailure = error.localizedDescription
            }
            if attempt < 3 {
                appendLog("能力查询第 \(attempt) 次失败，正在重试：\(lastFailure)", isError: true)
                try? await Task.sleep(nanoseconds: 250 * 1_000_000)
            }
        }

        if firmwareMainVersion == 1 {
            protocolMode = .legacy
            appendLog("连续三次能力查询失败，按已知旧版固件兼容：\(lastFailure)", isError: true)
        } else {
            protocolMode = .restrictedUnknown
            appendLog("连续三次无法识别固件协议，进入受限兼容模式：\(lastFailure)", isError: true)
        }
    }

    /// 顺序查询每个 mode 的 0x83 图片元信息，结果累积到 keyboardPictureStates
    private func queryAllPictureStates() async {
        for slot in 0..<4 {
            do {
                let state = try await readPictureState(mode: UInt8(slot))
                keyboardPictureStates[slot] = KeyboardPictureState(
                    frameCount: state.picLength,
                    frameIntervalMs: state.frameInterval
                )
                appendLog("  mode\(slot) flash: 帧数=\(state.picLength) 间隔=\(state.frameInterval)ms")
            } catch {
                appendLog("  mode\(slot) 图片状态查询失败: \(error)", isError: true)
            }
        }
    }

    private func sendCommandAwaitingResponse(
        _ data: Data,
        expectedCommand: UInt8,
        timeoutSeconds: Double = 5.0,
        forceBLE: Bool = false
    ) async throws -> CommandResponse {
        do {
            return try await sendCommandAwaitingResponseOnce(
                data,
                expectedCommand: expectedCommand,
                timeoutSeconds: timeoutSeconds,
                forceBLE: forceBLE
            )
        } catch OLEDUploadError.timeout
            where !forceBLE && isWiredConnected && peripheral != nil && commandChar != nil {
            if expectedCommand == AhaKeyCommand.cmdPrepareWrite ||
                expectedCommand == AhaKeyCommand.cmdPrepareSessionWrite {
                forceBLEPictureTransfer = true
            }
            appendLog(
                "USB 命令 0x\(String(format: "%02X", expectedCommand)) 响应超时，回退 BLE 重试",
                isError: true
            )
            return try await sendCommandAwaitingResponseOnce(
                data,
                expectedCommand: expectedCommand,
                timeoutSeconds: timeoutSeconds,
                forceBLE: true
            )
        }
    }

    private func sendCommandAwaitingResponseOnce(
        _ data: Data,
        expectedCommand: UInt8,
        timeoutSeconds: Double,
        forceBLE: Bool
    ) async throws -> CommandResponse {
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResponse, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: OLEDUploadError.cancelled)
                    return
                }
                let timeout = DispatchWorkItem { [weak self] in
                    self?.finishProtocolWaiter(expectedCommand, id: id, result: .failure(OLEDUploadError.timeout(command: expectedCommand)))
                }
                if protocolResponseWaiters[expectedCommand] != nil {
                    finishProtocolWaiter(expectedCommand, result: .failure(OLEDUploadError.requestSuperseded))
                }
                protocolResponseWaiters[expectedCommand] = ProtocolResponseWaiter(id: id, continuation: continuation, timeout: timeout)
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
                writeCommand(data, forceBLE: forceBLE)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.finishProtocolWaiter(expectedCommand, id: id, result: .failure(OLEDUploadError.cancelled))
            }
        })
    }

    private func finishProtocolWaiter(_ command: UInt8, id: UUID? = nil, result: Result<CommandResponse, Error>) {
        guard let waiter = protocolResponseWaiters[command], id == nil || waiter.id == id else { return }
        protocolResponseWaiters.removeValue(forKey: command)
        waiter.timeout.cancel()
        waiter.continuation.resume(with: result)
    }

    private func writeDataChunk(_ data: Data, timeoutSeconds: Double = 5.0) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: OLEDUploadError.cancelled)
                    return
                }
                let timeout = DispatchWorkItem { [weak self] in
                    if let self, self.isWiredConnected,
                       self.peripheral != nil, self.dataChar != nil {
                        self.forceBLEPictureTransfer = true
                        self.appendLog("USB 图片数据确认超时，后续重试改走 BLE", isError: true)
                    }
                    self?.finishDataWrite(id: id, result: .failure(OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult)))
                }
                if dataWriteWaiter != nil {
                    finishDataWrite(result: .failure(OLEDUploadError.requestSuperseded))
                }
                dataWriteWaiter = DataWriteWaiter(id: id, continuation: continuation, timeout: timeout)
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
                if self.isWiredConnected && !self.forceBLEPictureTransfer {
                    Task { @MainActor in
                        do {
                            try await self.usbTransport.sendData(data)
                            self.appendLog("→ USB DATA \(data.count)B")
                        } catch {
                            guard let peripheral = self.peripheral,
                                  let characteristic = self.dataChar else {
                                self.finishDataWrite(id: id, result: .failure(error))
                                return
                            }
                            self.appendLog("USB DATA 失败，自动回退 BLE：\(error.localizedDescription)", isError: true)
                            self.startBLEDataWrite(
                                data,
                                peripheral: peripheral,
                                characteristic: characteristic
                            )
                        }
                    }
                    return
                }
                guard let peripheral = self.peripheral, let characteristic = self.dataChar else {
                    self.finishDataWrite(id: id, result: .failure(OLEDUploadError.channelNotReady))
                    return
                }
                self.startBLEDataWrite(data, peripheral: peripheral, characteristic: characteristic)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.finishDataWrite(id: id, result: .failure(OLEDUploadError.cancelled))
            }
        })
    }

    private func startBLEDataWrite(
        _ data: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) {
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let negotiatedLength = max(1, peripheral.maximumWriteValueLength(for: type))
        let firmwareLimit = firmwareCapabilities?.maxPacketSize ?? AhaKeyCommand.oledPacketSize
        let maxPacketLength = min(negotiatedLength, firmwareLimit)
        let sessionID = currentUploadSessionID
        let tagLength = sessionID == nil ? 0 : 2
        let payloadLength = max(1, maxPacketLength - tagLength)
        appendLog("→ DATA \(data.count)B, 分片 \(payloadLength)B (协商上限 \(negotiatedLength)B)")
        dataPacketWriteTask?.cancel()
        dataPacketWriteTask = Task { @MainActor in
            let startedAt = Date()
            var bytesInFlightWindow = 0
            for offset in stride(from: 0, to: data.count, by: payloadLength) {
                guard !Task.isCancelled else { return }
                let end = min(offset + payloadLength, data.count)
                if type == .withoutResponse {
                    await self.waitUntilPeripheralCanSendWriteWithoutResponse(peripheral)
                    guard !Task.isCancelled else { return }
                }
                var packet = Data()
                if let sessionID {
                    packet.append(UInt8(sessionID & 0xFF))
                    packet.append(UInt8((sessionID >> 8) & 0xFF))
                }
                packet.append(data[offset ..< end])
                peripheral.writeValue(packet, for: characteristic, type: type)
                bytesInFlightWindow += end - offset
                if type == .withResponse {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(12) * 1_000_000)
                    } catch {
                        return
                    }
                } else if bytesInFlightWindow >= 976, end < data.count {
                    // CoreBluetooth backpressure covers the host queue, while
                    // this short window also gives the CH582 task time to drain
                    // its 2 KB application FIFO into W25QXX flash.
                    bytesInFlightWindow = 0
                    do {
                        try await Task.sleep(nanoseconds: UInt64(6) * 1_000_000)
                    } catch {
                        return
                    }
                }
            }
            let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
            self.appendLog(
                String(format: "DATA 已发送 %.0f KB/s", Double(data.count) / elapsed / 1024.0)
            )
        }
    }

    private func waitUntilPeripheralCanSendWriteWithoutResponse(_ peripheral: CBPeripheral) async {
        if peripheral.canSendWriteWithoutResponse { return }
        await withCheckedContinuation { continuation in
            if peripheral.canSendWriteWithoutResponse {
                continuation.resume()
            } else {
                writeWithoutResponseReadyContinuation = continuation
            }
        }
    }

    private func finishDataWrite(id: UUID? = nil, result: Result<Void, Error>) {
        guard let waiter = dataWriteWaiter, id == nil || waiter.id == id else { return }
        dataWriteWaiter = nil
        waiter.timeout.cancel()
        writeWithoutResponseReadyContinuation?.resume()
        writeWithoutResponseReadyContinuation = nil
        dataPacketWriteTask?.cancel()
        dataPacketWriteTask = nil
        waiter.continuation.resume(with: result)
    }

    func cancelOLEDUpload() {
        if let sessionID = currentUploadSessionID {
            writeCommand(AhaKeyCommand.abortPictureWrite(sessionID: sessionID))
            currentUploadSessionID = nil
        }
        writeWithoutResponseReadyContinuation?.resume()
        writeWithoutResponseReadyContinuation = nil
        finishDataWrite(result: .failure(OLEDUploadError.cancelled))
        for command in Array(protocolResponseWaiters.keys) {
            finishProtocolWaiter(command, result: .failure(OLEDUploadError.cancelled))
        }
    }
}

// MARK: - 拨杆档位切换 → 系统通知（与 `switchState` 同源，放在本文件避免独立 .swift 未被索引器收录）

/// 监听 `AhaKeyBLEManager.switchState` 的稳定变化，在拨杆切换档位时弹一条 macOS 通知。
@MainActor
final class SwitchStateNotifier: ObservableObject {
    static let shared = SwitchStateNotifier()

    private weak var bleManager: AhaKeyBLEManager?
    private var switchStateCancellable: AnyCancellable?
    private var agentSwitchStateCancellable: AnyCancellable?
    private var lastObservedState: Int?
    private var lastNotificationAt: Date?
    private var hasInitialState = false
    private var hasRequestedAuthorization = false

    private init() {}

    func bind(to manager: AhaKeyBLEManager) {
        if bleManager === manager, switchStateCancellable != nil, agentSwitchStateCancellable != nil { return }

        bleManager = manager
        lastObservedState = nil
        hasInitialState = false
        switchStateCancellable = manager.$switchState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
        agentSwitchStateCancellable = manager.$agentSwitchState
            .compactMap { $0 }
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
                body: "Kimi：若已安装 AhaKey Kimi Hooks，自动档会直接接管当前会话批准；若刚装完或刚升级 kimi-cli，请先重开一次 kimi。Claude/Cursor/Codex 仍走各自钩子。",
                identifier: "lab.jawa.ahakey.switch.auto",
                isCritical: true
            )
        } else if switchedToManual {
            postNotification(
                title: "拨杆 → 手动批准",
                body: "Claude / Cursor / Codex：按各自确认链。Kimi：若已安装 AhaKey Kimi Hooks，手动档会直接把当前会话拉回手动批准。",
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
                if error != nil {
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
            } else {
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
    case invalidTaskPictureStatePayload
    case taskPictureMetadataMismatch
    case cancelled
    case connectionLost
    case requestSuperseded
    case unsupportedFirmwareProtocol
    case invalidEncodedFrameSize

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
        case .invalidTaskPictureStatePayload:
            return "设备返回的任务动画槽位信息无法解析；请确认键盘已烧录任务 GIF 固件。"
        case .taskPictureMetadataMismatch:
            return "设备没有保存对应套图/状态的动画槽位信息；请更新到双套图固件后重试。"
        case .cancelled:
            return "图片写入已取消。已完成的图片会保留，未完成的图片可稍后继续写入。"
        case .connectionLost:
            return "键盘连接已中断，当前图片写入已停止。请重连后继续。"
        case .requestSuperseded:
            return "设备命令被新的请求替换，请重新尝试。"
        case .unsupportedFirmwareProtocol:
            return "无法识别当前固件协议，图片配置已进入受限兼容模式。"
        case .invalidEncodedFrameSize:
            return "图片尚未转换为 160×80 LCD 帧，已停止发送原图数据。"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension AhaKeyBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.refreshBluetoothAuthorization()
                self.appendLog("蓝牙已开启")
                self.connectAutomatically()
            case .poweredOff:
                self.refreshBluetoothAuthorization()
                self.appendLog("蓝牙已关闭", isError: true)
                self.bleConnectionStatus = "蓝牙关闭"
            case .unauthorized:
                self.refreshBluetoothAuthorization()
                self.appendLog("蓝牙权限未开启", isError: true)
                self.bleConnectionStatus = "蓝牙权限未开启"
            default:
                self.refreshBluetoothAuthorization()
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
        guard name.lowercased().hasPrefix(Self.deviceNamePrefix.lowercased()) else { return }

        Task { @MainActor in
            self.appendLog("发现设备: \(name) RSSI=\(RSSI)")
            self.central?.stopScan()
            self.isScanning = false
            self.peripheral = peripheral
            peripheral.delegate = self
            self.central?.connect(peripheral, options: nil)
            self.bleConnectionStatus = "连接中…"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isBLEConnected = true
            self.isConnected = true
            if !self.isWiredConnected {
                self.deviceName = peripheral.name
                self.bleDeviceUUID = peripheral.identifier.uuidString
                self.bleConnectionStatus = "已连接"
            }
            self.lastPeripheralUUID = peripheral.identifier
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
                try? await Task.sleep(nanoseconds: UInt64(Double(3) * 1_000_000_000))
                if !self.isConnected {
                    self.connectAutomatically()
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.cancelPendingTransferWaiters(reason: .connectionLost)
            let dropped = self.writeQueue.count
            let openBatches = self.writeBatches.count
            if dropped > 0 || openBatches > 0 {
                self.appendLog(
                    "BLE 已断开，丢弃未发出命令 \(dropped) 条（未闭合批 \(openBatches) 个）。\(error.map { "原因：\($0.localizedDescription)" } ?? "")",
                    isError: true
                )
            }
            self.isBLEConnected = false
            self.isConnected = self.isWiredConnected
            if !self.isWiredConnected {
                self.bleConnectionStatus = "已断开"
            }
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
            self.keyboardPictureStates.removeAll()
            self.keyboardTaskPictureStates.removeAll()
            self.activeTaskPictureSets.removeAll()
            self.stopRSSIPolling()
            if !self.isWiredConnected {
                self.stopStatusPolling()
                self.startAutoReconnectPolling()
            }
            self.appendLog("已断开: \(error?.localizedDescription ?? "正常")")

            // 2 秒后自动重连
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Double(2) * 1_000_000_000))
                if !self.isBLEConnected && !self.isWiredConnected {
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

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            self.writeWithoutResponseReadyContinuation?.resume()
            self.writeWithoutResponseReadyContinuation = nil
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
            brightness = status.brightness
            activeTaskPictureSets[status.workMode] = status.activePictureSet
            appendLog("  状态: 电量=\(status.battery) 固件=\(status.firmwareMain).\(status.firmwareSub) 模式=\(status.workMode) 灯=\(status.lightMode) 开关=\(status.switchState) 亮度=\(status.brightness)")
        } else if AhaKeyResponseParser.isProtocolFrame(data) {
            if let response = AhaKeyResponseParser.parseCommandResponse(data) {
                finishProtocolWaiter(response.cmd, result: .success((response.status, response.payload)))

                if response.cmd == AhaKeyCommand.cmdWriteResult {
                    if let expectedSession = currentUploadSessionID {
                        guard response.payload.count >= 2 else {
                            appendLog("忽略缺少 session 的图片写入确认", isError: true)
                            return
                        }
                        let responseSession =
                            UInt16(response.payload[0]) |
                            (UInt16(response.payload[1]) << 8)
                        guard responseSession == expectedSession else {
                            appendLog(
                                "忽略过期图片确认 session=\(responseSession)，当前=\(expectedSession)",
                                isError: true
                            )
                            return
                        }
                    }
                    if response.status == 0 {
                        finishDataWrite(result: .success(()))
                    } else {
                        finishDataWrite(result: .failure(OLEDUploadError.deviceRejected(command: response.cmd, status: response.status)))
                    }
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

    private func cancelPendingTransferWaiters(reason: OLEDUploadError) {
        writeWithoutResponseReadyContinuation?.resume()
        writeWithoutResponseReadyContinuation = nil
        finishDataWrite(result: .failure(reason))
        for command in Array(protocolResponseWaiters.keys) {
            finishProtocolWaiter(command, result: .failure(reason))
        }
    }

    /// 发送探测命令
    func sendProbeCommands() {
        guard hasConfigurationTransport else {
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
