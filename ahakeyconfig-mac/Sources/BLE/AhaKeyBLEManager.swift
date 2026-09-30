import AppKit
import AhaKeyConfigShared
import Combine
import CoreBluetooth
import Darwin
import Foundation
import os.log
import UserNotifications

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "BLE")

/// 0x83 查询回来的某个 mode 的图片元信息（用 Equatable struct 方便 SwiftUI .onChange 监听）
struct KeyboardPictureState: Equatable {
    let frameCount: Int
    let frameIntervalMs: Int
}

/// Diagnostics are observed by DeviceInfoView independently of the Studio manager.
@MainActor
final class BLEDeviceDiagnosticsStore: ObservableObject {
    @Published var snapshot = DeviceDiagnosticsSnapshot()
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

    /// 核心投影：连接/设备身份、电量、模式、灯效、拨杆、亮度、固件版本、任务图套图。主 Studio 只观察它。
    /// 仅在真实变化时重新赋值——相同快照零发布，一次真实变化最多发布一次。
    @Published private(set) var coreSnapshot = CoreDeviceSnapshot()
    /// 诊断投影：RSSI、固件详细信息等遥测。与核心投影隔离，不触发主 Studio 刷新。
    let diagnosticsStore = BLEDeviceDiagnosticsStore()
    var diagnosticsSnapshot: DeviceDiagnosticsSnapshot { diagnosticsStore.snapshot }

    // 旧属性名全部保留，改为读快照的只读计算属性（@Published 不能用于计算属性，UI 零改动继续编译）。
    var isConnected: Bool { coreSnapshot.isConnected }
    var deviceName: String? { coreSnapshot.deviceName }
    var batteryLevel: Int { coreSnapshot.batteryLevel }
    var signalStrength: Int { diagnosticsSnapshot.signalStrength }
    var firmwareMainVersion: Int { coreSnapshot.firmwareMainVersion }
    var firmwareSubVersion: Int { coreSnapshot.firmwareSubVersion }
    var firmwareRevision: String { diagnosticsSnapshot.firmwareRevision }
    var modelNumber: String { diagnosticsSnapshot.modelNumber }
    var workMode: Int { coreSnapshot.workMode }
    var lightMode: Int { coreSnapshot.lightMode }
    var switchState: Int { coreSnapshot.switchState }
    var brightness: Int { coreSnapshot.brightness }
    var bleDeviceUUID: String { coreSnapshot.deviceUUID }
    /// 各 mode 当前激活的任务图套图索引（由 0x97 或设备状态上报）。
    var activeTaskPictureSets: [Int: Int] { coreSnapshot.activeTaskPictureSets }

    /// 所有周期性 BLE 状态的唯一归并入口。BLE 回调禁止直接写状态属性，必须构造事件走这里。
    private func apply(_ event: DeviceStateEvent) {
        let result = DeviceStateReducer.apply(event, core: coreSnapshot, diagnostics: diagnosticsSnapshot)
        if result.core != coreSnapshot {
            // 设备状态真实变化：记一条默认永久级摘要（连接/断开由生命周期日志覆盖，不在摘要内）
            if let summary = CoreSnapshotChangeSummary.summarize(from: coreSnapshot, to: result.core) {
                appendLog("状态变化: \(summary)", category: .stateChange)
            }
            coreSnapshot = result.core
        }
        if result.diagnostics != diagnosticsSnapshot { diagnosticsStore.snapshot = result.diagnostics }
        switch result.effect {
        case .none:
            break
        case .workModeChanged(let mode):
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": mode]
            )
        }
    }

    @Published private(set) var bleConnectionStatus: String = NSLocalizedString("未连接", comment: "")
    @Published private(set) var supportsConfigurableLighting: Bool?
    @Published private(set) var bluetoothPermissionGranted = true
    @Published private(set) var bluetoothPoweredOn = false
    /// 细分的「卡在哪条链路」诊断，把笼统的「等待设备」拆成可操作提示（Issue #34）。
    @Published private(set) var linkDiagnostic: LinkDiagnostic = .idle
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

    /// 内存诊断级日志 Store（阶段 2：独立 ObservableObject，append 不再波及观察 manager 的 View）。
    /// 周期 TX/RX 不进这里；临时详细抓包见 `BLELogStore.setVerboseLoggingEnabled`。
    let logStore: BLELogStore

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

    // 标准 HID Service —— 设备被系统蓝牙 / 语音链路连上后常只暴露 HID / DeviceInfo，
    // 用它来把「已连接但已停止广播 0x7340」的设备从系统侧捞回来（见 connectAutomatically，Issue #34）。
    static let hidServiceUUID = CBUUID(string: "1812")

    /// 设备广播名前缀白名单。除官方 "AhaKey" 外，也认 vibe coding 固件的 "vibe code" 名
    /// （CH582m_vibe_coding_BLE_keyboard 固件默认广播名形如 "vibe code XXXX"）。
    nonisolated static let deviceNamePrefixes = ["AhaKey", "vibe code"]

    /// 设备名是否匹配任一已知前缀（大小写无关）。
    nonisolated static func matchesDeviceName(_ name: String?) -> Bool {
        guard let lower = name?.lowercased() else { return false }
        return deviceNamePrefixes.contains { lower.hasPrefix($0.lowercased()) }
    }

    // MARK: - Private

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?
    private var pendingConnect = false
    private var rssiTimer: Timer?
    private var autoReconnectTimer: Timer?
    var isAutoReconnectScheduled: Bool { autoReconnectTimer?.isValid == true }
    private var statusPollTimer: Timer?
    private var ideStateDirectoryMonitor: DispatchSourceFileSystemObject?
    private var ideStateExpiryTimer: Timer?
    private var ideStateFallbackTimer: Timer?
    private var ideStateRefreshTask: Task<Void, Never>?
    /// Agent BLE 活性通道（阶段 4）：由 AgentManager 注入，返回 Agent 是否持有 BLE 连接（socket status 心跳）。
    /// 为 true 时 current-ide-state.json 中的 agent* 状态不因文件老化而作废；默认 false（纯 mtime 过期）。
    var agentBLEConnectedProvider: () -> Bool = { false }
    private let ideStateMonitorQueue = DispatchQueue(
        label: "lab.jawa.ahakeyconfig.ide-state-monitor",
        qos: .utility
    )
    /// 记住上次连接的 UUID，用于快速重连
    private var lastPeripheralUUID: UUID?
    /// 为 true 时，本 App 不扫描、不连接、不响应掉线/轮询重连（物理键盘由 `ahakeyconfig-agent` 占用时由 AgentManager 置位）
    private var suppressAutomaticConnection = false
    /// 自动重连退避（阶段 3）：4s → 8s → 15s → 30s 封顶；用户显式操作或扫到目标设备广播时重置回 4s
    private var reconnectBackoff = BackoffSchedule()
    /// 跨进程 BLE 连接锁（阶段 3，flock）：发起连接前必须持有，防止与 Agent 双连
    private let connectionLock: BLEConnectionLock
    /// 锁被其他进程占用的提示是否已记录（只记一次状态转换，不随重试刷屏）
    private var didLogConnectionLockBusy = false
    /// 设备信息窗口是否可见：RSSI 轮询只在窗口打开时进行（见 `setDiagnosticsWindowVisible`）
    private var diagnosticsWindowVisible = false
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

    override convenience init() {
        self.init(startServices: true, logStore: BLELogStore(), connectionLock: BLEConnectionLock())
    }

    /// Dependencies and service startup are explicit so tests never access user files or Bluetooth.
    init(startServices: Bool, logStore: BLELogStore, connectionLock: BLEConnectionLock,
         ideStateDirectoryURL: URL? = nil) {
        self.ideStateDirectoryURL = ideStateDirectoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
        self.logStore = logStore
        self.connectionLock = connectionLock
        super.init()
        guard startServices else { return }
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
        startIDEStateMonitoring()
    }

    /// 确保 CBCentralManager 已创建。用户显式申请蓝牙权限时调用。
    func ensureCentralManager() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
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

    nonisolated static func isBluetoothAuthorizationGranted(_ authorization: CBManagerAuthorization) -> Bool {
        switch authorization {
        case .allowedAlways:
            return true
        case .notDetermined:
            return false
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func currentBluetoothAuthorizationGranted() -> Bool {
        isBluetoothAuthorizationGranted(CBCentralManager.authorization)
    }

    /// 由「设备信息 / 顶栏」等**用户显式**发起连接时调用：取消「交给 Agent」时的抑制并尝试连接。
    func userInitiatedConnect() {
        ensureCentralManager()
        setSuppressedForAgentOwningKeyboard(false)
        connectAutomatically()
    }

    /// 与 `AgentManager` 的蓝牙占用方一致：交给 Agent 时为 true，交回本 App 时为 false。
    func setSuppressedForAgentOwningKeyboard(_ suppress: Bool) {
        suppressAutomaticConnection = suppress
        if suppress {
            // Stop scanning before yielding ownership. Retain the lock until CoreBluetooth
            // confirms cancellation of an active/pending connection.
            central?.stopScan()
            isScanning = false
            pendingConnect = false
            autoReconnectTimer?.invalidate()
            autoReconnectTimer = nil
            stopRSSIPolling()
            stopStatusPolling()
            if let peripheral, peripheral.state != .disconnected {
                central?.cancelPeripheralConnection(peripheral)
            } else {
                self.peripheral = nil
                connectionLock.release()
            }
            didLogConnectionLockBusy = false
        } else {
            // Restore retries even when the first attempt cannot acquire the lock or find a device.
            reconnectBackoff.reset()
            if !isConnected { startAutoReconnectPolling() }
        }
    }

    var acceptsConnectionCallbacks: Bool {
        !suppressAutomaticConnection && connectionLock.holdsLock
    }

    /// 设备信息窗口可见性钩子（由 DeviceInfoView 生命周期调用）。
    /// RSSI 轮询只在窗口打开时进行：打开时立即读一次并恢复 5 秒轮询，关闭时停止。
    func setDiagnosticsWindowVisible(_ visible: Bool) {
        guard visible != diagnosticsWindowVisible else { return }
        diagnosticsWindowVisible = visible
        if visible {
            guard isConnected else { return }
            peripheral?.readRSSI()
            startRSSIPolling()
        } else {
            stopRSSIPolling()
        }
    }

    func connectAutomatically() {
        guard !suppressAutomaticConnection else {
            // 蓝牙交由 ahakeyconfig-agent 占用，本 App 不直连——这是预期行为，明确标记以免被当成故障。
            linkDiagnostic = .ownedByAgent
            return
        }
        guard central?.state == .poweredOn else {
            pendingConnect = true
            switch central?.state {
            case .poweredOff: linkDiagnostic = .bluetoothOff
            case .unauthorized: linkDiagnostic = .bluetoothUnauthorized
            default: break
            }
            return
        }
        // 跨进程锁：发起连接前必须持有；被 Agent 等进程占用时不连接（不双连），随退避轮询低频重试
        guard ensureConnectionLockHeld() else { return }

        // 1. 用已知 UUID 直连（最快）
        if let uuid = lastPeripheralUUID {
            let known = central?.retrievePeripherals(withIdentifiers: [uuid]) ?? []
            if let p = known.first {
                appendLog("用已知 UUID 直连: \(p.name ?? uuid.uuidString)")
                self.peripheral = p
                p.delegate = self
                central?.connect(p, options: nil)
                bleConnectionStatus = "连接中…"
                linkDiagnostic = .connecting
                return
            }
        }

        // 2. 查找系统已连接设备。
        //    根因兜底（Issue #34）：设备一旦被系统蓝牙 / 语音(HID) 链路连上，通常会停止广播，
        //    基于广播的 scanForPeripherals(withServices:[0x7340]) 永远扫不到它；且若此前无人发现过
        //    0x7340，retrieveConnectedPeripherals(withServices:[0x7340]) 也为空。所以这里用更宽的标准
        //    service 集合把设备捞回来，再主动 connect → didConnect 里 discoverServices 补发现 0x7340。
        if let existing = systemConnectedAhaKeyPeripheral() {
            if isConfigServiceVisible(existing) {
                appendLog("发现系统已连接设备: \(existing.name ?? "?")")
                linkDiagnostic = .connecting
            } else {
                appendLog("设备已被系统/语音链路连接但未广播配置服务，主动接管 0x7340: \(existing.name ?? "?")")
                linkDiagnostic = .systemConnectedNoConfigLink
            }
            self.peripheral = existing
            existing.delegate = self
            central?.connect(existing, options: nil)
            bleConnectionStatus = "连接中…"
            return
        }

        // 3. 扫描
        startScan()
    }

    /// 用更宽的标准 service 集合在「系统已连接」外设里查找 AhaKey 设备——即使它已停止广播 0x7340。
    private func systemConnectedAhaKeyPeripheral() -> CBPeripheral? {
        let lookupServices = [
            Self.serviceUUID,
            Self.deviceInfoServiceUUID,
            Self.batteryServiceUUID,
            Self.hidServiceUUID,
        ]
        let connected = central?.retrieveConnectedPeripherals(withServices: lookupServices) ?? []
        return connected.first { Self.matchesDeviceName($0.name) }
    }

    /// 该设备是否已在系统层暴露过 0x7340 配置 service：用于区分「完整可连」与「仅 HID / 语音链路」。
    private func isConfigServiceVisible(_ peripheral: CBPeripheral) -> Bool {
        (central?.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]) ?? [])
            .contains { $0.identifier == peripheral.identifier }
    }

    /// 发起连接前必须持有跨进程连接锁；被其他进程（通常是 Agent，例如 unload 失败残留）持有时
    /// 不连接。占用状态转换只记一条 error 日志，之后随退避轮询低频重试获取，不刷屏。
    private func ensureConnectionLockHeld() -> Bool {
        guard !connectionLock.holdsLock else { return true }
        if connectionLock.acquire() {
            if didLogConnectionLockBusy {
                appendLog(NSLocalizedString("另一进程已释放蓝牙，恢复连接", comment: ""))
                didLogConnectionLockBusy = false
            }
            return true
        }
        if !didLogConnectionLockBusy {
            appendLog(NSLocalizedString("蓝牙被另一进程占用（可能 Agent 仍在运行），本 App 暂不连接", comment: ""), isError: true)
            didLogConnectionLockBusy = true
        }
        return false
    }

    func startScan() {
        guard central?.state == .poweredOn else {
            pendingConnect = true
            return
        }
        isScanning = true
        bleConnectionStatus = "扫描中…"
        linkDiagnostic = .scanning
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
                // 扫描超时后再用宽 service 探一次，区分「设备已连但未广播配置链路」与「彻底没发现设备」（Issue #34）。
                if self.systemConnectedAhaKeyPeripheral() != nil {
                    self.linkDiagnostic = .systemConnectedNoConfigLink
                    self.appendLog("扫描超时：检测到设备已被系统/语音链路连接，但配置链路 0x7340 未建立")
                } else {
                    self.linkDiagnostic = .noDeviceFound
                    self.appendLog("扫描超时，继续后台轮询设备")
                }
            }
        }
    }

    func disconnect() {
        guard let peripheral else { return }
        central?.cancelPeripheralConnection(peripheral)
        appendLog(NSLocalizedString("用户主动断开", comment: ""), category: .lifecycle)
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
        appendLog("→ CMD \(data.count)B: \(data.hexString)", category: .verbose)
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
        appendLog("开始上传 LCD 数据: \(frames.count) 帧, FPS=\(fps), mode=\(mode), startIndex=\(startIndex), frameSlotSize=\(AhaKeyCommand.oledFrameSlotSize)")

        defer {
            isUploadingOLED = false
            oledUploadProgress = nil
        }

        let writeType: CBCharacteristicWriteType =
            dataChar.properties.contains(.write) ? .withResponse : .withoutResponse
        var completedChunks = 0

        for (frameIndex, frame) in frames.enumerated() {
            let frameAddress = UInt32(Int(startIndex) + frameIndex) * UInt32(AhaKeyCommand.oledFrameSlotSize)
            appendLog("  帧 #\(frameIndex) 物理地址=0x\(String(format: "%08X", frameAddress))=\(frameAddress), 大小=\(frame.count)B", category: .verbose)
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
        appendLog("LCD 上传完成: \(frames.count) 帧, start=\(startIndex)")
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
            try? await Task.sleep(nanoseconds: UInt64(50) * 1_000_000)
            self.isWriting = false
            self.drainWriteQueue()
        }
    }

    /// 查询设备状态
    func queryDeviceStatus() {
        let cmd = AhaKeyCommand.queryDeviceStatus()
        appendLog(NSLocalizedString("查询设备状态…", comment: ""), category: .verbose)
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

    /// 同步 IDE 状态到键盘 LED
    func updateIDEState(_ state: IDEState) {
        guard commandChar != nil else { return }
        let cmd = AhaKeyCommand.updateState(state)
        writeCommand(cmd)
    }

    func setLightMapping(mode: UInt8, stateEffects: [UInt8]) {
        guard commandChar != nil else { return }
        writeCommand(AhaKeyCommand.setLightMapping(mode: mode, stateEffects: stateEffects))
        appendLog("→ 灯效映射 mode=\(mode) effects=\(stateEffects)")
    }

    func setBrightness(_ value: UInt8) {
        guard commandChar != nil else { return }
        writeCommand(AhaKeyCommand.setBrightness(value))
        appendLog("→ 亮度 \(value)")
    }

    func previewLightEffect(_ effect: UInt8) {
        guard commandChar != nil else { return }
        writeCommand(AhaKeyCommand.previewLightEffect(effect))
        appendLog("→ 预览灯效 \(effect)")
    }

    /// 写入前主动验证新灯效协议。旧 v1.0 对未知命令也返回 status=0，不能只看 0x85 ACK；
    /// 必须再查询状态并确认亮度字段真的变成期望值。
    func verifyConfigurableLightingSupport(brightness value: UInt8) async throws {
        guard commandChar != nil else { throw OLEDUploadError.channelNotReady }

        let expected = max(1, min(100, value))
        appendLog("验证灯效协议：写入亮度 \(expected)% 并回读…")
        _ = try await sendCommandAwaitingResponse(
            AhaKeyCommand.setBrightness(expected),
            expectedCommand: AhaKeyCommand.cmdSetBrightness
        )

        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.queryDeviceStatus(),
            expectedCommand: 0x00
        )
        guard let status = AhaKeyResponseParser.parseDeviceStatus(response.payload) else {
            throw OLEDUploadError.invalidDeviceStatusPayload
        }

        let supported = status.brightness == Int(expected)
        supportsConfigurableLighting = supported
        guard supported else {
            throw OLEDUploadError.unsupportedLightingFirmware(
                main: status.firmwareMain,
                sub: status.firmwareSub,
                reportedBrightness: status.brightness
            )
        }
        appendLog("灯效协议验证通过：0x84/0x85/0x91 可用")
    }

    /// 严格串行发送并等待每一条设备 ACK。只有所有命令（包括最后的 0x04 保存）
    /// 都收到 status=0，调用方才能向用户报告“写入成功”。
    func writeCommandsConfirmingResponses(
        _ commands: [(data: Data, label: String)],
        interCommandDelayMilliseconds: UInt64 = 50
    ) async throws {
        guard commandChar != nil else { throw OLEDUploadError.channelNotReady }

        for (index, command) in commands.enumerated() {
            guard command.data.count >= 5,
                  command.data[0] == 0xAA,
                  command.data[1] == 0xBB else {
                throw OLEDUploadError.invalidCommandFrame
            }
            let commandID = command.data[2]
            appendLog(command.label)
            _ = try await sendCommandAwaitingResponse(
                command.data,
                expectedCommand: commandID
            )

            if index < commands.count - 1, interCommandDelayMilliseconds > 0 {
                try await Task.sleep(nanoseconds: interCommandDelayMilliseconds * 1_000_000)
            }
        }
    }

    nonisolated static func statusAdvertisesConfigurableLighting(brightness: Int) -> Bool {
        (1...100).contains(brightness)
    }

    func setWorkMode(_ mode: UInt8) {
        guard commandChar != nil else { return }
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
        logStore.clear()
    }

    /// 与内部 `appendLog` 相同（含 `~/Library/.../AhaKeyConfig/diagnostics/ble-comm.log` 与系统日志），供 Studio 等写入调试说明。
    func appendCommLogLine(_ message: String, isError: Bool = false) {
        appendLog(message, isError: isError)
    }

    // MARK: - Logging

    /// 诊断日志目录（默认永久级 ble-comm.log 与临时详细级 ble-verbose.log 同目录）。
    nonisolated static let diagnosticsDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    nonisolated static let logFileURL: URL = diagnosticsDirectory.appendingPathComponent("ble-comm.log")

    /// 临时详细级（TX/RX 抓包）滚动文件，见 `BLELogStore`。
    nonisolated static let verboseLogFileURL: URL = diagnosticsDirectory.appendingPathComponent("ble-verbose.log")

    /// 三级日志路由（阶段 2，级别分类见 Shared/BLELogPolicy.swift）：
    /// - 默认永久级（lifecycle/stateChange/error）：内存 Store + os_log + ble-comm.log；
    /// - 内存诊断级（diagnostic，默认类别）：内存 Store + os_log；
    /// - 临时详细级（verbose）：仅详细会话开启时写 ble-verbose.log（后台串行队列），
    ///   会话开启期间其余级别也同步进抓包文件，保证抓包自含上下文。
    /// isError 强制归入 error（默认永久级），覆盖调用方给的类别。
    private func appendLog(_ message: String, isError: Bool = false, category: BLELogCategory = .diagnostic) {
        let routing = (isError ? BLELogCategory.error : category).routing
        let entry = BLELogEntry(timestamp: Date(), message: message, isError: isError)
        if routing.entersMemoryStore {
            logStore.append(entry)
        }
        if routing.entersSystemLog {
            if isError {
                log.error("\(message)")
            } else {
                log.info("\(message)")
            }
        }
        let line = "[\(entry.formattedTime)] \(message)\n"
        if routing.entersPersistentLog {
            logStore.writePersistentLine(line)
        }
        if logStore.isVerboseLoggingEnabled {
            logStore.writeVerboseLine(line)
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

    /// 退避式自动重连轮询（阶段 3）：按 `reconnectBackoff` 的间隔逐级拉长（4s → 8s → 15s → 30s 封顶）。
    private func startAutoReconnectPolling() {
        guard !suppressAutomaticConnection else { return }
        scheduleAutoReconnectAttempt(after: reconnectBackoff.next())
    }

    private func scheduleAutoReconnectAttempt(after delay: TimeInterval) {
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performAutoReconnectAttempt()
            }
        }
    }

    private func performAutoReconnectAttempt() {
        guard !suppressAutomaticConnection else { return }
        // 条件不满足（扫描中/连接中/蓝牙未开）：不消耗退避步进，按当前间隔再试
        guard central?.state == .poweredOn,
              !isConnected, !isScanning,
              bleConnectionStatus != NSLocalizedString("连接中…", comment: "") else {
            scheduleAutoReconnectAttempt(after: reconnectBackoff.currentInterval)
            return
        }
        appendLog(NSLocalizedString("后台轮询中，尝试寻找设备…", comment: ""), category: .verbose)
        connectAutomatically()
        scheduleAutoReconnectAttempt(after: reconnectBackoff.next())
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

    private let ideStateDirectoryURL: URL

    private var ideStateFileURL: URL {
        ideStateDirectoryURL.appendingPathComponent("current-ide-state.json")
    }

    /// Agent 通常以临时文件 + rename 的方式更新状态，因此监听目录而不是单个文件。
    /// 仅在真实文件变化时解析 JSON；一次性 timer 在 30s/120s 的准确过期点刷新状态。
    func startIDEStateMonitoring() {
        stopIDEStateMonitoring()
        pollIDEStateFile()

        do {
            try FileManager.default.createDirectory(
                at: ideStateDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            startIDEStateFallbackPolling()
            return
        }

        let descriptor = open(ideStateDirectoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            startIDEStateFallbackPolling()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: ideStateMonitorQueue
        )
        source.setEventHandler { [weak self, weak source] in
            let flags = source?.data ?? []
            Task { @MainActor in
                guard let self, let source, self.ideStateDirectoryMonitor === source else { return }
                if !flags.intersection([.rename, .delete, .revoke]).isEmpty {
                    self.startIDEStateMonitoring()
                } else {
                    self.scheduleIDEStateRefresh()
                }
            }
        }
        source.setRegistrationHandler { [weak self, weak source] in
            Task { @MainActor in
                guard let self, let source, self.ideStateDirectoryMonitor === source else { return }
                // A directory swap or atomic file write can happen between open() and
                // dispatch registration. Validate the inode and read once after binding.
                let currentFD = open(self.ideStateDirectoryURL.path, O_EVTONLY)
                var watched = stat()
                var current = stat()
                let matches = currentFD >= 0 && fstat(descriptor, &watched) == 0
                    && fstat(currentFD, &current) == 0
                    && watched.st_dev == current.st_dev && watched.st_ino == current.st_ino
                if currentFD >= 0 { close(currentFD) }
                if matches { self.scheduleIDEStateRefresh() }
                else { self.startIDEStateMonitoring() }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        ideStateDirectoryMonitor = source
        source.resume()
    }

    func stopIDEStateMonitoring() {
        ideStateRefreshTask?.cancel()
        ideStateRefreshTask = nil
        ideStateExpiryTimer?.invalidate()
        ideStateExpiryTimer = nil
        ideStateFallbackTimer?.invalidate()
        ideStateFallbackTimer = nil
        ideStateDirectoryMonitor?.cancel()
        ideStateDirectoryMonitor = nil
    }

    private func scheduleIDEStateRefresh() {
        ideStateRefreshTask?.cancel()
        ideStateRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            self?.pollIDEStateFile()
        }
    }

    /// 极少数无法创建目录监听器的环境下保留兼容回退；正常路径不会启动这个 timer。
    private func startIDEStateFallbackPolling() {
        ideStateFallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollIDEStateFile()
            }
        }
    }

    private func scheduleIDEStateExpiry(at deadline: TimeInterval?) {
        ideStateExpiryTimer?.invalidate()
        ideStateExpiryTimer = nil
        guard let deadline else { return }

        let interval = max(0.05, deadline - Date().timeIntervalSince1970)
        ideStateExpiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pollIDEStateFile()
            }
        }
    }

    private func pollIDEStateFile() {
        guard let data = try? Data(contentsOf: ideStateFileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            scheduleIDEStateExpiry(at: nil)
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
            if agentLightMode != nil { agentLightMode = nil }
            if agentSwitchState != nil { agentSwitchState = nil }
            if agentWorkMode != nil { agentWorkMode = nil }
            return
        }
        let now = Date().timeIntervalSince1970
        var expiryDeadlines: [TimeInterval] = []
        // stateValue 是瞬时态（hook 触发的事件时间戳），30s 过期；超时则置空，固件 LED 也会回到无 state 默认。
        // 注意它故意仍按内容里的 stateTs 判断，不随 mtime：Agent 的 30s touch 会刷新 mtime，
        // 若按 mtime 判断，瞬时态会被 Agent 保活永不落空。
        if let v = obj["stateValue"] as? Int,
           let stateTs = (obj["stateTs"] as? Double) ?? (obj["ts"] as? Double),
           now < stateTs + 30 {
            if liveIDEStateValue != v { liveIDEStateValue = v }
            expiryDeadlines.append(stateTs + 30)
        } else {
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
        }
        // lightMode/switchState/workMode 来自 Agent 的 BLE 轮询。阶段 4 起 Agent 写前去重，
        // 内容静止时不再每 1.5s 落盘，过期判断统一迁到文件 mtime 语义：mtime = 「状态最后确认时间」
        // （Agent 无变化时每 30s touch 一次 mtime；JSON 里的 "ts" 字段保留仅为兼容，不再参与过期判断）。
        // Agent 活性以 socket status 心跳为准：Agent 持有 BLE 连接时不因文件老化作废，120s 后复查；
        // Agent 不在/未连接时按 mtime 超过 120s 过期清理（与原 2 分钟语义一致）。
        let fileMtime = ((try? FileManager.default.attributesOfItem(atPath: ideStateFileURL.path))?[.modificationDate] as? Date)?.timeIntervalSince1970
        let agentStateFresh: Bool
        if agentBLEConnectedProvider() {
            agentStateFresh = true
            expiryDeadlines.append(now + 120)
        } else if let mtime = fileMtime, now < mtime + 120 {
            agentStateFresh = true
            expiryDeadlines.append(mtime + 120)
        } else {
            agentStateFresh = false
        }
        if agentStateFresh {
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
        scheduleIDEStateExpiry(at: expiryDeadlines.min())
    }

    /// 所有 AhaKey 主服务特征就绪后触发（仅一次）
    private func onAllCharacteristicsReady() {
        guard !didQueryAfterConnect else { return }
        didQueryAfterConnect = true
        appendLog("所有特征就绪，查询设备状态")
        queryDeviceStatus()
        queryAllPictureStates()
    }

    /// 顺序查询每个 mode 的 0x83 图片元信息，结果累积到 keyboardPictureStates
    private func queryAllPictureStates() {
        Task { [weak self] in
            guard let self else { return }
            for slot in 0..<4 {
                do {
                    let state = try await self.readPictureState(mode: UInt8(slot))
                    self.keyboardPictureStates[slot] = KeyboardPictureState(
                        frameCount: state.picLength,
                        frameIntervalMs: state.frameInterval
                    )
                    self.appendLog("  mode\(slot) flash: 帧数=\(state.picLength) 间隔=\(state.frameInterval)ms")
                } catch {
                    self.appendLog("  mode\(slot) 图片状态查询失败: \(error)", isError: true)
                }
            }
        }
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
            group.addTask { [weak self] in
                try await Task.sleep(nanoseconds: UInt64(Double(timeoutSeconds) * 1_000_000_000))
                // 超时必须主动 resume 仍挂着的 continuation 并移除它：CheckedContinuation 不响应任务取消，
                // 否则 withThrowingTaskGroup 会一直等这个永不结束的子任务而 hang，导致本函数永不返回 →
                // defer 不清理 → protocolResponseWaiters 残留 → 状态轮询被 guard 永久挡死（设备某档/某模式
                // 不回应即复现：界面不再随键盘变化刷新，必须重连）。removeValue 原子取出，与响应处理互斥，不会重复 resume。
                await MainActor.run { [weak self] in
                    self?.protocolResponseWaiters.removeValue(forKey: expectedCommand)?
                        .resume(throwing: OLEDUploadError.timeout(command: expectedCommand))
                }
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
                        self?.appendLog("→ DATA \(data.count)B, 分片 \(maxPacketLength)B (协商上限 \(negotiatedLength)B)", category: .verbose)
                        Task {
                            for offset in stride(from: 0, to: data.count, by: maxPacketLength) {
                                let end = min(offset + maxPacketLength, data.count)
                                let packet = Data(data[offset ..< end])
                                peripheral.writeValue(packet, for: characteristic, type: type)
                                try? await Task.sleep(nanoseconds: UInt64(12) * 1_000_000)
                            }
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Double(timeoutSeconds) * 1_000_000_000))
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
        // switchState 已改为读 coreSnapshot 的计算属性，这里改为订阅核心投影再取字段（效果同原 $switchState）
        switchStateCancellable = manager.$coreSnapshot
            .map(\.switchState)
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

/// 设备「卡在哪条链路」的细分诊断（Issue #34）：把笼统的「等待设备」拆成可操作的提示，
/// 让用户能区分「蓝牙已连但配置链路未连」与「设备完全没连接」。
enum LinkDiagnostic: Equatable {
    case idle                          // 初始 / 空闲
    case scanning                      // 扫描中
    case connecting                    // 连接中
    case connected                     // 配置链路 (0x7340) 已连
    case bluetoothOff                  // 系统蓝牙未开启
    case bluetoothUnauthorized         // 未授权蓝牙权限
    case ownedByAgent                  // BLE 交由 ahakeyconfig-agent 占用（本 App 不直连，属预期）
    case systemConnectedNoConfigLink   // 设备已被系统 / 语音(HID) 链路连接，但 0x7340 配置链路未建立
    case noDeviceFound                 // 未发现设备（未开机 / 不在范围 / 未配对）

    /// 顶栏 pill 用的极简副标题。
    var shortMessage: String {
        switch self {
        case .idle, .scanning: return "扫描中…"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .bluetoothOff: return "蓝牙未开启"
        case .bluetoothUnauthorized: return "无蓝牙权限"
        case .ownedByAgent: return "Agent 占用中"
        case .systemConnectedNoConfigLink: return "配置链路未连"
        case .noDeviceFound: return "未发现设备"
        }
    }

    /// 详细可操作说明，供设备信息 / tooltip 展示。
    var detail: String {
        switch self {
        case .idle: return "正在初始化蓝牙…"
        case .scanning: return "正在扫描 AhaKey 设备…"
        case .connecting: return "正在连接设备…"
        case .connected: return "AhaKey 配置链路 (0x7340) 已连接。"
        case .bluetoothOff: return "系统蓝牙未开启。请在「控制中心 / 系统设置 > 蓝牙」打开蓝牙。"
        case .bluetoothUnauthorized: return "未授权蓝牙权限。请在「系统设置 > 隐私与安全性 > 蓝牙」中允许 AhaKey Studio。"
        case .ownedByAgent: return "蓝牙当前交由 ahakeyconfig-agent 占用，本 App 不直接连接（这是预期行为）。配置链路状态请参考 Agent；如需本 App 直连，请在设备信息里把「蓝牙连接」切回本 App。"
        case .systemConnectedNoConfigLink: return "设备已通过系统蓝牙（HID / 语音链路）连接，但 AhaKey 配置服务 0x7340 尚未建立。本 App 正在尝试主动接管该链路；若长时间无效，请在「系统设置 > 蓝牙」忽略此设备后重新配对。"
        case .noDeviceFound: return "未发现 AhaKey 设备。请确认设备已开机、处于蓝牙范围内并已与本机配对。"
        }
    }

    /// 是否为「配置链路完整可用」。
    var isHealthy: Bool { self == .connected }
}

enum OLEDUploadError: LocalizedError {
    case channelNotReady
    case noFrames
    case tooManyFrames(max: Int)
    case noAvailablePictureSlot(needed: Int, max: Int)
    case timeout(command: UInt8)
    case deviceRejected(command: UInt8, status: UInt8)
    case invalidPictureStatePayload
    case invalidDeviceStatusPayload
    case invalidCommandFrame
    case unsupportedLightingFirmware(main: Int, sub: Int, reportedBrightness: Int)

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
        case .invalidDeviceStatusPayload:
            return "设备返回的状态信息无法解析。"
        case .invalidCommandFrame:
            return "待写入的命令帧格式不正确。"
        case .unsupportedLightingFirmware(let main, let sub, let reportedBrightness):
            return "当前键盘是旧灯效协议固件（设备回报 v\(main).\(sub)，亮度字段 \(reportedBrightness)），不会执行 0x84/0x85/0x91。请先刷入 2026-06-22 后的新固件，本次未上报写入成功。"
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
                self.appendLog(NSLocalizedString("蓝牙已开启", comment: ""), category: .lifecycle)
                self.connectAutomatically()
            case .poweredOff:
                self.refreshBluetoothAuthorization()
                self.appendLog("蓝牙已关闭", isError: true)
                self.bleConnectionStatus = "蓝牙关闭"
                self.linkDiagnostic = .bluetoothOff
            case .unauthorized:
                self.refreshBluetoothAuthorization()
                self.appendLog("蓝牙权限未开启", isError: true)
                self.bleConnectionStatus = "蓝牙权限未开启"
                self.linkDiagnostic = .bluetoothUnauthorized
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
        guard Self.matchesDeviceName(name) else { return }

        Task { @MainActor in
            guard self.acceptsConnectionCallbacks else { return }
            self.appendLog("发现设备: \(name) RSSI=\(RSSI)")
            // 扫到目标设备广播：退避重置回 4s 并立即连接
            self.reconnectBackoff.reset()
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
            guard self.acceptsConnectionCallbacks else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            self.apply(.connected(name: peripheral.name, uuid: peripheral.identifier.uuidString))
            self.lastPeripheralUUID = peripheral.identifier
            self.bleConnectionStatus = NSLocalizedString("已连接", comment: "")
            self.appendLog("已连接: \(peripheral.name ?? "?") UUID=\(peripheral.identifier.uuidString)", category: .lifecycle)
            self.linkDiagnostic = .connected
            self.reconnectBackoff.reset()
            self.autoReconnectTimer?.invalidate()
            self.autoReconnectTimer = nil
            peripheral.discoverServices([
                Self.serviceUUID,
                Self.batteryServiceUUID,
                Self.deviceInfoServiceUUID,
            ])
            // RSSI 轮询只在设备信息窗口打开时进行
            if self.diagnosticsWindowVisible {
                peripheral.readRSSI()
                self.startRSSIPolling()
            }
            self.startStatusPolling()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if self.peripheral === peripheral { self.peripheral = nil }
            if self.suppressAutomaticConnection {
                self.peripheral = nil
                self.connectionLock.release()
                return
            }
            self.bleConnectionStatus = "连接失败"
            self.appendLog("连接失败: \(error?.localizedDescription ?? "未知")", isError: true)
            self.startAutoReconnectPolling()
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
            self.apply(.disconnected)
            self.bleConnectionStatus = NSLocalizedString("已断开", comment: "")
            self.dataChar = nil
            self.commandChar = nil
            self.notifyChar = nil
            self.batteryLevelChar = nil
            self.dataCharReady = false
            self.commandCharReady = false
            self.notifyCharReady = false
            self.supportsConfigurableLighting = nil
            // 不清 peripheral 和 lastPeripheralUUID——用于直连重试
            self.peripheral = nil
            self.writeQueue.removeAll()
            self.isWriting = false
            self.writeBatches.removeAll()
            self.didQueryAfterConnect = false
            self.keyboardPictureStates.removeAll()
            self.stopRSSIPolling()
            self.stopStatusPolling()
            if self.suppressAutomaticConnection { self.connectionLock.release() }
            else { self.startAutoReconnectPolling() }
            self.appendLog("已断开: \(error?.localizedDescription ?? "正常")", category: .lifecycle)

        }
    }
}

// MARK: - CBPeripheralDelegate

extension AhaKeyBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks else { return }
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
            guard self.acceptsConnectionCallbacks else { return }
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
            guard self.acceptsConnectionCallbacks else { return }
            self.handleNotification(from: characteristic.uuid, data: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks else { return }
            self.apply(.rssi(RSSI.intValue))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks else { return }
            if let error {
                self.appendLog("写入特征 \(characteristic.uuid) 失败: \(error.localizedDescription)", isError: true)
            } else {
                self.appendLog("写入特征 \(characteristic.uuid) 完成", category: .verbose)
            }
        }
    }

    private func handleNotification(from uuid: CBUUID, data: Data) {
        let hex = data.hexString
        switch uuid {
        case Self.dataCharUUID:
            appendLog("← DATA(0x7341): \(hex)", category: .verbose)
            parseProtocolResponse(data)
        case Self.notifyCharUUID:
            appendLog("← NOTIFY(0x7344): \(hex)", category: .verbose)
            parseProtocolResponse(data)
        case Self.batteryLevelCharUUID:
            if let level = data.first {
                apply(.battery(Int(level)))
                appendLog("← 电池: \(batteryLevel)%", category: .verbose)
            }
        case Self.firmwareRevisionCharUUID:
            if let str = String(data: data, encoding: .utf8) {
                apply(.deviceInfo(firmwareRevision: str, modelNumber: nil))
            }
        case Self.modelNumberCharUUID:
            if let str = String(data: data, encoding: .utf8) {
                apply(.deviceInfo(firmwareRevision: nil, modelNumber: str))
            }
        default:
            appendLog("← 未知(\(uuid)): \(hex)")
        }
    }

    func parseProtocolResponse(_ data: Data) {
        if let status = AhaKeyResponseParser.parseDeviceStatus(data) {
            apply(.fullStatus(
                battery: status.battery, firmwareMain: status.firmwareMain,
                firmwareSub: status.firmwareSub, workMode: status.workMode,
                lightMode: status.lightMode, switchState: status.switchState,
                brightness: status.brightness, activePictureSet: 0
            ))
            let supported = Self.statusAdvertisesConfigurableLighting(brightness: status.brightness)
            if supportsConfigurableLighting != supported { supportsConfigurableLighting = supported }
            // Preserve main's status-query waiter; status frames are not ordinary ACKs.
            protocolResponseWaiters.removeValue(forKey: 0x00)?.resume(returning: (status: 0, payload: data))
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
                    appendLog("  ✓ 命令 0x\(String(format: "%02X", response.cmd)) 成功", category: .verbose)
                } else {
                    let payloadHex = response.payload.isEmpty ? "—" : response.payload.hexString
                    appendLog("  命令 0x\(String(format: "%02X", response.cmd)) 失败: status=0x\(String(format: "%02X", response.status)) payload=\(payloadHex)", isError: true)
                }
            }
        } else {
            let bytes = data.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
            appendLog("  原始 [\(data.count)B]: \(bytes)", category: .verbose)
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
            appendLog("→ \(label): \(data.hexString)", category: .verbose)
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
