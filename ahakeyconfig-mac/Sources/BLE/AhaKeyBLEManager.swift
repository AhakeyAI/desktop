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
    typealias CommandResponse = (status: UInt8, payload: Data, frame: Data)

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
    @Published private(set) var configurationSnapshot = DeviceConfigurationSnapshot()
    @Published private(set) var ws3DisplaySnapshot: WS3DisplaySnapshot?
    @Published private(set) var ws3SingleLightSnapshot: WS3SingleLightSnapshot?
    @Published private(set) var ws3LightCatalogSnapshot: WS3LightCatalogSnapshot?
    enum WS3DisplayOperationKind { case reading, updating }
    struct WS3DisplayOperationTicket: Equatable {
        fileprivate let id: UUID
        fileprivate let generation: UInt64
        fileprivate let kind: WS3DisplayOperationKind
    }
    private var activeWS3DisplayOperation: WS3DisplayOperationTicket?

    func beginWS3DisplayOperation(_ kind: WS3DisplayOperationKind) -> WS3DisplayOperationTicket {
        let ticket = WS3DisplayOperationTicket(id: UUID(), generation: commandSessionGeneration, kind: kind)
        activeWS3DisplayOperation = ticket
        switch kind {
        case .reading: isReadingWS3Display = true
        case .updating: isUpdatingWS3Display = true
        }
        return ticket
    }

    func finishWS3DisplayOperation(_ ticket: WS3DisplayOperationTicket) {
        guard ticket.generation == commandSessionGeneration, activeWS3DisplayOperation == ticket else { return }
        activeWS3DisplayOperation = nil
        switch ticket.kind {
        case .reading: isReadingWS3Display = false
        case .updating: isUpdatingWS3Display = false
        }
    }

    @Published private(set) var isReadingWS3Display = false
    @Published private(set) var isUpdatingWS3Display = false
    var canEditWS3Display: Bool {
        isConnected && !commandChannelUnsynchronized && firmwareCapabilityProfile?.mayQueryWS3Display == true &&
            ws3DisplaySnapshot?.verifiesDisplaySettings(in: commandSessionGeneration) == true
    }
    @Published private(set) var isReadingConfigurationSnapshot = false
    @Published private(set) var isChangingWorkMode = false
    @Published private(set) var isReadingStandby = false
    @Published private(set) var isSettingStandby = false
    @Published private(set) var isReadingSideSwitch = false
    @Published private(set) var isSettingSideSwitch = false
    @Published private(set) var isEditingOrdinaryKey = false
    @Published private(set) var isManagingVoiceHandoff = false
    @Published private(set) var isManagingK1Route = false
    private var k1RouteProofGeneration: UInt64?
    private var hasCurrentK1RouteProof: Bool {
        k1RouteProofGeneration == commandSessionGeneration && hasValidStatusReadback &&
            firmwareCapabilityProfile?.mayQueryOrdinaryKeys == true
    }
    @Published private(set) var isChangingPresentation = false
    private var presentationBlocksLegacySingle = false
    private(set) var presentationRuntimeActive = false
    lazy var studioPresentation = StudioPresentationController(ble: self)
    var isConfigurationOperationInProgress: Bool {
        isChangingPresentation || isUploadingOLED || isReadingWS3Display || isUpdatingWS3Display || isReadingConfigurationSnapshot || isChangingWorkMode || isReadingStandby || isSettingStandby || isReadingSideSwitch || isSettingSideSwitch || isEditingOrdinaryKey || isManagingVoiceHandoff || isManagingK1Route
    }
    @Published private(set) var firmwareCapabilityProfile: FirmwareCapabilityProfile?
    @Published private(set) var bluetoothPermissionGranted = true
    @Published private(set) var bluetoothPoweredOn = false
    /// 细分的「卡在哪条链路」诊断，把笼统的「等待设备」拆成可操作提示（Issue #34）。
    @Published private(set) var linkDiagnostic: LinkDiagnostic = .idle
    @Published private(set) var oledUploadProgress: OLEDUploadProgress?
    @Published private(set) var isUploadingOLED = false
    /// 由 ahakeyconfig-agent 写入的当前 IDE hook 状态值（IDEState.rawValue），用于画布 LED 颜色实时还原
    @Published private(set) var liveIDEStateValue: Int? = nil
    /// Agent 端 BLE 通知缓存（agent 占用蓝牙时主 App 自己 BLE 未连，靠这些读到键盘实时状态）。
    @Published private(set) var agentBatteryLevel: Int? = nil
    @Published private(set) var agentLightMode: Int? = nil
    @Published private(set) var agentSwitchState: Int? = nil
    @Published private(set) var agentWorkMode: Int? = nil
    var batteryLevelForDisplay: Int? {
        isConnected ? (hasValidStatusReadback ? batteryLevel : nil) : (agentBLEConnectedProvider() ? agentBatteryLevel : nil)
    }
    var switchStateForDisplay: Int? {
        isConnected ? (hasValidStatusReadback ? switchState : nil) : (agentBLEConnectedProvider() ? agentSwitchState : nil)
    }
    var workModeForDisplay: Int? {
        isConnected ? (hasValidStatusReadback ? workMode : nil) : (agentBLEConnectedProvider() ? agentWorkMode : nil)
    }
    var lightModeForDisplay: Int? {
        isConnected ? (hasValidStatusReadback ? lightMode : nil) : (agentBLEConnectedProvider() ? agentLightMode : nil)
    }
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
    private var statusQueryTask: Task<Void, Never>?
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
    private var connectionAttempt = BLEConnectionAttemptGuard()
    private var connectionDeadlineTask: Task<Void, Never>?
    /// 为 true 时，本 App 不扫描、不连接、不响应掉线/轮询重连（物理键盘由 `ahakeyconfig-agent` 占用时由 AgentManager 置位）
    private var suppressAutomaticConnection = false
    /// Do not start a new CoreBluetooth connection before cancellation completes.
    private var awaitingPeripheralDisconnect = false
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
    private struct PendingCommandResponse {
        let id: UInt64
        let generation: UInt64
        let request: Data
        let command: UInt8
        let continuation: CheckedContinuation<CommandResponse, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingCommandResponse: PendingCommandResponse?
    private let commandTurns = CommandTurnQueue()
    private var commandTurnOccupied: Bool { commandTurns.isOccupied }
    private var commandSessionGeneration: UInt64 = 0
    private var nextCommandRequestID: UInt64 = 0
    private var commandChannelUnsynchronized: Bool { commandTurns.isInvalidated }
    private var hasValidStatusReadback = false
    private struct PendingDataWrite {
        let id: UInt64
        let generation: UInt64
        let continuation: CheckedContinuation<Void, Error>
        let timeoutTask: Task<Void, Never>
    }
    private var pendingDataWrite: PendingDataWrite?
    private var nextDataWriteID: UInt64 = 0
    private var dataNotificationFramer = DeviceNotificationFramer()
    private var notifyNotificationFramer = DeviceNotificationFramer()
    nonisolated static let dataWriteResultTimeoutSeconds: Double = 10.0
    nonisolated static let oledChunkMaxAttempts = 3
    var dataWriteRequiresReconnect: Bool { commandChannelUnsynchronized }

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
        guard !awaitingPeripheralDisconnect, connectionAttempt.resumeByUser() else { return }
        ensureCentralManager()
        setSuppressedForAgentOwningKeyboard(false)
        connectAutomatically()
    }

    /// 与 `AgentManager` 的蓝牙占用方一致：交给 Agent 时为 true，交回本 App 时为 false。
    func setSuppressedForAgentOwningKeyboard(_ suppress: Bool) {
        suppressAutomaticConnection = suppress
        if suppress {
            connectionDeadlineTask?.cancel()
            connectionDeadlineTask = nil
            connectionAttempt.reset()
            // Stop scanning before yielding ownership. Retain the lock until CoreBluetooth
            // confirms cancellation of an active/pending connection.
            central?.stopScan()
            isScanning = false
            pendingConnect = false
            autoReconnectTimer?.invalidate()
            autoReconnectTimer = nil
            stopRSSIPolling()
            stopStatusPolling()
            invalidateConnectionState()
            bleConnectionStatus = NSLocalizedString("已断开", comment: "")
            linkDiagnostic = .ownedByAgent
            if let peripheral, peripheral.state != .disconnected {
                awaitingPeripheralDisconnect = true
                central?.cancelPeripheralConnection(peripheral)
            } else {
                self.peripheral = nil
                awaitingPeripheralDisconnect = false
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
        guard !awaitingPeripheralDisconnect else { return }
        guard connectionAttempt.mayBegin else { return }
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
                beginPeripheralConnection(p)
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
            beginPeripheralConnection(existing)
            bleConnectionStatus = "连接中…"
            return
        }

        // 3. 扫描
        startScan()
    }

    /// Called directly by the native powered-off callback; no radio is created here.
    func handleBluetoothPoweredOff() {
        connectionDeadlineTask?.cancel()
        connectionDeadlineTask = nil
        connectionAttempt.reset()
        awaitingPeripheralDisconnect = false
        isScanning = false
        peripheral = nil
        stopRSSIPolling()
        stopStatusPolling()
        invalidateConnectionState()
        // The old peripheral callback is now ignored. Complete a pending handoff
        // here rather than leaving the suppressed App holding the Agent's lock.
        if suppressAutomaticConnection { connectionLock.release() }
    }

    private func beginPeripheralConnection(_ target: CBPeripheral) {
        guard acceptsConnectionCallbacks, !awaitingPeripheralDisconnect,
              let ticket = connectionAttempt.begin(target: target.identifier,
                  retryAutomatically: lastPeripheralUUID == target.identifier) else { return }
        peripheral = target
        target.delegate = self
        central?.connect(target, options: nil)
        connectionDeadlineTask?.cancel()
        connectionDeadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(BLEConnectionAttemptGuard.deadlineSeconds * 1_000_000_000)) }
            catch { return }
            guard let self, self.peripheral === target, self.connectionAttempt.timeOut(ticket) else { return }
            self.central?.stopScan()
            self.isScanning = false
            self.autoReconnectTimer?.invalidate()
            self.autoReconnectTimer = nil
            self.awaitingPeripheralDisconnect = true
            self.bleConnectionStatus = NSLocalizedString("连接等待超时", comment: "")
            if self.connectionAttempt.requiresManualRetry {
                self.linkDiagnostic = .pairingRequired
                self.appendLog(NSLocalizedString("新设备连接等待超时，已取消待连接请求并暂停自动重试；请先在 macOS 蓝牙中完成配对，再点击连接设备。", comment: ""), isError: true)
            }
            self.central?.cancelPeripheralConnection(target)
        }
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
        guard connectionAttempt.mayBegin, !awaitingPeripheralDisconnect else { return }
        guard central?.state == .poweredOn else {
            pendingConnect = true
            return
        }
        isScanning = true
        bleConnectionStatus = "扫描中…"
        linkDiagnostic = .scanning
        appendLog("开始扫描 AhaKey 设备…")
        central?.scanForPeripherals(
            // CP4D/WS3 advertises HID + Battery, not necessarily 0x7340.
            // Service filters are ORed; the discovery callback still checks the name.
            withServices: [Self.serviceUUID, Self.hidServiceUUID, Self.batteryServiceUUID],
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
        writeCommand(data, confirmedWrite: .none)
    }

    private func writeCommand(_ data: Data, confirmedWrite: ConfigurationCommandPolicy.ConfirmedWrite) {
        if isManagingK1Route, ![UInt8(0x00), 0x9F, 0x9E].contains(data.count > 2 ? data[2] : 0xFF) { return }
        if data.count > 2 {
            if data[2] == 0x90, presentationBlocksLegacySingle, confirmedWrite != .ws3Presentation { return }
            if isChangingPresentation, confirmedWrite != .ws3Presentation,
               ![UInt8(0x00), 0x88, 0x9F].contains(data[2]) { return }
        }
        // A display transaction owns the channel; unrelated raw status/display
        // writes must not race into firmware's single ready command slot.
        if (isUploadingOLED || isUpdatingWS3Display), firmwareCapabilityProfile?.mayQueryWS3Display == true {
            let ownsWrite = isUploadingOLED ? confirmedWrite == .ws3Resource :
                (confirmedWrite == .ws3Display || confirmedWrite == .ws3ResourceRestore)
            if !ownsWrite, ![UInt8(0x00), 0x88].contains(data.count > 2 ? data[2] : 0xFF) {
                appendLog("显示操作占用通道，未发送其他配置命令", category: .verbose)
                return
            }
        }
        guard ConfigurationCommandPolicy.permits(data, profile: firmwareCapabilityProfile, confirmedWrite: confirmedWrite,
                                               ws3DisplayReadbackVerified: canEditWS3Display,
                                               k1RouteReadbackVerified: hasCurrentK1RouteProof) else {
            appendLog("当前固件配置写入尚未验证，已阻止写入", isError: true)
            return
        }
        guard acceptsConnectionCallbacks, !awaitingPeripheralDisconnect,
              let commandChar, let peripheral else {
            appendLog("命令通道未就绪", isError: true)
            return
        }
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: writeType)
        if logStore.isVerboseLoggingEnabled {
            appendLog("→ CMD \(data.count)B: \(data.hexString)", category: .verbose)
        }
    }

    func uploadOLEDFrames(_ frames: [Data], fps: Int, mode: UInt8 = 0, startIndex: UInt16 = 0) async throws {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        guard firmwareCapabilityProfile?.identity == .legacy else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        guard acceptsConnectionCallbacks, let peripheral, let dataChar, let commandChar else {
            throw OLEDUploadError.channelNotReady
        }
        let uploadGeneration = commandSessionGeneration
        guard !frames.isEmpty else {
            throw OLEDUploadError.noFrames
        }
        guard frames.count <= AhaKeyCommand.oledMaxFrames else {
            throw OLEDUploadError.tooManyFrames(max: AhaKeyCommand.oledMaxFrames)
        }
        // 0x80/0x81 的等待位都是单槽：两次上传交错（如连接后默认动图自动同步与手动写入）会互相顶掉等待者。
        guard !isUploadingOLED else {
            throw OLEDUploadError.uploadInProgress
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
            if commandSessionGeneration == uploadGeneration {
                isUploadingOLED = false
                oledUploadProgress = nil
            }
        }

        let writeType: CBCharacteristicWriteType =
            dataChar.properties.contains(.write) ? .withResponse : .withoutResponse
        var completedChunks = 0
        var completedFrames = 0

        do {

            for (frameIndex, frame) in frames.enumerated() {
                let frameAddress = UInt32(Int(startIndex) + frameIndex) * UInt32(AhaKeyCommand.oledFrameSlotSize)
                appendLog("  帧 #\(frameIndex) 物理地址=0x\(String(format: "%08X", frameAddress))=\(frameAddress), 大小=\(frame.count)B", category: .verbose)
                let chunks = stride(from: 0, to: frame.count, by: AhaKeyCommand.oledChunkSize).map { offset in
                    let end = min(offset + AhaKeyCommand.oledChunkSize, frame.count)
                    return (offset: offset, data: Data(frame[offset ..< end]))
                }

                for (chunkIndex, chunk) in chunks.enumerated() {
                    guard self.peripheral === peripheral, self.dataChar === dataChar else {
                        throw OLEDUploadError.disconnected
                    }
                    let address = frameAddress + UInt32(chunk.offset)
                    let prepare = AhaKeyCommand.prepareWrite(chunkLength: chunk.data.count, address: address)
                    // 同一地址重发 0x80 + 数据是幂等的（固件按扇区擦写），单块丢一次 0x81 不应让整次上传失败（AHK-022）。
                    var stage = OLEDTransferStage.prepareWrite
                    var attempts = 0
                    do {
                        try await Self.retryingOLEDTimeouts(
                            maxAttempts: Self.oledChunkMaxAttempts,
                            canRetry: { self.dataCharReady && !self.commandChannelUnsynchronized && !self.awaitingPeripheralDisconnect },
                            onRetry: { attempt, error in
                                self.appendLog("  帧 #\(frameIndex) 块 \(chunkIndex + 1)/\(chunks.count) \(stage.label)失败（\(error.localizedDescription)），第 \(attempt) 次重试", isError: true)
                            }
                        ) { attempt in
                            attempts = attempt
                            stage = .prepareWrite
                            _ = try await self.sendCommandAwaitingResponse(prepare, expectedCommand: AhaKeyCommand.cmdPrepareWrite)
                            stage = .dataWrite
                            try await self.writeDataChunk(chunk.data, to: peripheral, characteristic: dataChar, type: writeType)
                        }
                    } catch {
                        throw OLEDUploadError.transferFailed(
                            stage: stage, mode: mode,
                            frame: frameIndex + 1, totalFrames: frames.count,
                            chunk: chunkIndex + 1, totalChunks: chunks.count,
                            attempts: attempts, reason: error.localizedDescription
                        )
                    }
                    completedChunks += 1
                    oledUploadProgress = OLEDUploadProgress(
                        completedChunks: completedChunks,
                        totalChunks: oledUploadProgress?.totalChunks ?? completedChunks,
                        completedFrames: frameIndex,
                        totalFrames: frames.count
                    )
                }

                completedFrames = frameIndex + 1
                oledUploadProgress = OLEDUploadProgress(
                    completedChunks: completedChunks,
                    totalChunks: oledUploadProgress?.totalChunks ?? completedChunks,
                    completedFrames: completedFrames,
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
            do {
                _ = try await sendCommandAwaitingResponse(updateCommand, expectedCommand: AhaKeyCommand.cmdUpdatePic)
            } catch {
                throw OLEDUploadError.transferFailed(
                    stage: .commitPicture, mode: mode,
                    frame: frames.count, totalFrames: frames.count,
                    chunk: nil, totalChunks: nil,
                    attempts: 1, reason: error.localizedDescription
                )
            }
        } catch {
            appendLog("LCD 上传未确认完成: mode=\(mode) 已写入 \(completedFrames)/\(frames.count) 帧。原因：\(error.localizedDescription)", isError: true)
            throw OLEDUploadError.uploadIncomplete(completedFrames: completedFrames, totalFrames: frames.count, reason: error.localizedDescription)
        }
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
        guard commands.allSatisfy({ ConfigurationCommandPolicy.permits($0.data, profile: firmwareCapabilityProfile) }) else {
            appendLog("当前固件配置写入尚未验证，未加入写入队列", isError: true)
            return
        }
        writeBatches.append(WriteCommandBatch(commandsRemaining: commands.count, completion: completion))
        writeQueue.append(contentsOf: commands.map { ($0.data, $0.label) })
        drainWriteQueue()
    }

    private func drainWriteQueue() {
        guard !isWriting, !writeQueue.isEmpty else { return }
        let generation = commandSessionGeneration
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
            guard self.commandSessionGeneration == generation else { return }
            self.isWriting = false
            self.drainWriteQueue()
        }
    }

    /// 查询设备状态
    func queryDeviceStatus() {
        guard statusQueryTask == nil, !commandChannelUnsynchronized else { return }
        statusQueryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.statusQueryTask = nil }
            do {
                self.appendLog(NSLocalizedString("查询设备状态…", comment: ""), category: .verbose)
                _ = try await self.sendCommandAwaitingResponse(
                    AhaKeyCommand.queryDeviceStatus(), expectedCommand: 0x00
                )
            } catch {
                self.appendLog("设备状态查询失败: \(error)", category: .verbose)
            }
        }
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

    /// A catalog probe is read-only. A legacy profile is assigned only after
    /// this connection has independently returned a valid status frame.
    func readFirmwareCapabilityProfile(forceStatusReadback: Bool = false) async throws -> FirmwareCapabilityProfile {
        k1RouteProofGeneration = nil
        let generation = commandSessionGeneration
        let previousProfile = firmwareCapabilityProfile
        firmwareCapabilityProfile = nil
        ws3DisplaySnapshot = nil
        ws3SingleLightSnapshot = nil
        ws3LightCatalogSnapshot = nil
        var accepted = false
        defer {
            if !accepted, generation == commandSessionGeneration {
                // A failed refresh cannot leave old capabilities/facts writable.
                firmwareCapabilityProfile = nil
                ws3DisplaySnapshot = nil
                ws3SingleLightSnapshot = nil
                ws3LightCatalogSnapshot = nil
                configurationSnapshot.reset(generation: generation)
            }
        }
        if forceStatusReadback || !hasValidStatusReadback {
            let statusResponse = try await sendCommandAwaitingResponse(
                AhaKeyCommand.queryDeviceStatus(), expectedCommand: 0x00
            )
            guard AhaKeyResponseParser.parseDeviceStatus(statusResponse.frame) != nil else {
                throw OLEDUploadError.invalidReadback
            }
        }
        try ensureConfigurationReadSession(generation)
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.queryFirmwareCatalog(),
            expectedCommand: AhaKeyCommand.cmdReadFirmwareCatalog,
            allowDeviceError: true
        )
        try ensureConfigurationReadSession(generation)
        let authority = await FirmwareRuntimeCatalog.shared.snapshot()
        try ensureConfigurationReadSession(generation)
        let profile = authority.profile(response.frame, hasValidStatus: hasValidStatusReadback)
        guard profile.identity != .unknown(nil) else { throw OLEDUploadError.invalidReadback }
        if profile != previousProfile { configurationSnapshot.reset(generation: generation) }
        firmwareCapabilityProfile = profile
        accepted = true
        return profile
    }

    func readOrdinaryKey(mode: UInt8, keyIndex: UInt8) async throws -> OrdinaryKeyReadbackResult {
        let generation = commandSessionGeneration
        guard firmwareCapabilityProfile?.mayQueryOrdinaryKeys == true else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        guard let request = AhaKeyCommand.queryOrdinaryKey(mode: mode, keyIndex: keyIndex) else {
            throw OLEDUploadError.invalidCommandFrame
        }
        let response = try await sendCommandAwaitingResponse(
            request, expectedCommand: AhaKeyCommand.cmdReadOrdinaryKey, allowDeviceError: true
        )
        let result = OrdinaryKeyReadbackResult.parse(
            response.frame, requestedMode: mode, requestedKeyIndex: keyIndex
        )
        guard result != .malformed else { throw OLEDUploadError.invalidReadback }
        try ensureConfigurationReadSession(generation)
        configurationSnapshot.recordKey(result, mode: mode, index: keyIndex, generation: generation)
        return result
    }

    func readStandbyMinutes() async throws -> UInt16 {
        let generation = commandSessionGeneration
        guard firmwareCapabilityProfile?.mayQueryStandby == true else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.queryStandby(), expectedCommand: AhaKeyCommand.cmdReadStandby
        )
        guard let value = WS2SettingsReadback.standbyMinutes(response.frame) else {
            throw OLEDUploadError.invalidReadback
        }
        try ensureConfigurationReadSession(generation)
        configurationSnapshot.recordStandby(value, generation: generation)
        return value
    }

    func readVoiceOnboardingState() async throws -> UInt8 {
        let generation = commandSessionGeneration
        guard firmwareCapabilityProfile?.mayQueryVoiceOnboarding == true else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.queryVoiceOnboarding(), expectedCommand: AhaKeyCommand.cmdReadVoiceOnboarding
        )
        guard let value = WS2SettingsReadback.voiceOnboardingState(response.frame) else {
            throw OLEDUploadError.invalidReadback
        }
        try ensureConfigurationReadSession(generation)
        configurationSnapshot.recordVoice(value, generation: generation)
        return value
    }

    func readSideSwitchBinding() async throws -> SideSwitchReadback {
        let generation = commandSessionGeneration
        guard firmwareCapabilityProfile?.mayQuerySideSwitchBindings == true else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.querySideSwitch(), expectedCommand: AhaKeyCommand.cmdReadSideSwitch
        )
        guard let value = WS2SettingsReadback.sideSwitch(response.frame) else {
            throw OLEDUploadError.invalidReadback
        }
        try ensureConfigurationReadSession(generation)
        configurationSnapshot.recordSideSwitch(value, generation: generation)
        return value
    }

    private func ensureConfigurationReadSession(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard generation == commandSessionGeneration, isConnected, !commandChannelUnsynchronized else {
            throw OLEDUploadError.channelNotReady
        }
    }

    private func readWS3DisplayValue(_ item: WS3DisplayItem, generation: UInt64) async throws -> WS3DisplayValue {
        try ensureConfigurationReadSession(generation)
        guard let request = item.request else { throw OLEDUploadError.invalidCommandFrame }
        let response = try await sendCommandAwaitingResponse(request, expectedCommand: 0x88, allowDeviceError: true)
        try ensureConfigurationReadSession(generation)
        guard let value = WS3DisplayValue.parse(response.frame, for: item) else { throw OLEDUploadError.invalidReadback }
        if value == .unsupported { throw OLEDUploadError.unsupportedWS3Readback }
        if case .rejected(let status) = value { throw OLEDUploadError.deviceRejected(command: 0x88, status: status) }
        return value
    }

    /// Safe discovery of the CP2 read-only surface. Older CP4D's generic ACK
    /// is treated as unsupported and never authorizes resource writes.
    func readWS3DisplayForEditing() async throws -> WS3DisplaySnapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        let displayOperation = beginWS3DisplayOperation(.reading)
        ws3DisplaySnapshot = nil
        ws3SingleLightSnapshot = nil
        ws3LightCatalogSnapshot = nil
        defer { finishWS3DisplayOperation(displayOperation) }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryWS3Display else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        func read(_ item: WS3DisplayItem) async throws -> WS3DisplayValue {
            try await self.readWS3DisplayValue(item, generation: generation)
        }
        guard case .brightness(let brightness) = try await read(.brightness) else { throw OLEDUploadError.invalidReadback }
        var resources: [WS3ResourceReadback] = []
        for id: UInt8 in 0..<19 {
            let basic = try await read(.resourceBasic(id))
            let integrity = try await read(.resourceIntegrity(id))
            guard let resource = WS3ResourceReadback(id: id, basic: basic, integrity: integrity) else { throw OLEDUploadError.invalidReadback }
            resources.append(resource)
        }
        try ensureConfigurationReadSession(generation)
        let snapshot = WS3DisplaySnapshot(generation: generation, brightness: brightness, resources: resources)
        ws3DisplaySnapshot = snapshot
        return snapshot
    }

    func verifyWS3Resource(_ payload: WS3ResourcePayload) async throws -> WS3ResourceMetadataComparison {
        guard !isConfigurationOperationInProgress, canEditWS3Display, let baseline = ws3DisplaySnapshot else {
            throw WS3ResourceMaintenanceError.unverifiedConnection
        }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.reading)
        defer { finishWS3DisplayOperation(displayOperation) }
        do {
            let actual = try await ConfirmedWS3ResourceMaintenance.read(entry: payload.entryID, baseline: baseline,
                generation: generation, checkSession: { try self.ensureConfigurationReadSession(generation) },
                exchange: { try await self.sendCommandAwaitingResponse($0, expectedCommand: 0x88, allowDeviceError: true).frame })
            try ensureConfigurationReadSession(generation)
            ws3DisplaySnapshot = WS3DisplaySnapshot(generation: generation, brightness: baseline.brightness,
                resources: baseline.resources.map { $0.id == actual.id ? actual : $0 })
            return WS3ResourceMetadataComparison(payload: payload, resource: actual)
        } catch {
            if generation == commandSessionGeneration { ws3DisplaySnapshot = nil }
            throw error
        }
    }

    func restoreWS3ResourceDefault(entry: UInt8, baseline: WS3DisplaySnapshot) async throws -> WS3ResourceReadback {
        guard !isConfigurationOperationInProgress, canEditWS3Display,
              firmwareCapabilityProfile?.mayQueryWS3Resources == true,
              baseline.generation == commandSessionGeneration else { throw WS3ResourceMaintenanceError.unverifiedConnection }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.updating)
        var attemptedWrite = false
        defer { finishWS3DisplayOperation(displayOperation) }
        do {
            let actual = try await ConfirmedWS3ResourceMaintenance.restoreDefault(entry: entry, baseline: baseline,
                generation: generation, checkSession: { try self.ensureConfigurationReadSession(generation) }, exchange: { request in
                    if request[2] == 0x8D { attemptedWrite = true }
                    return try await self.sendCommandAwaitingResponse(request, expectedCommand: request[2],
                        allowDeviceError: true, confirmedWrite: request[2] == 0x8D ? .ws3ResourceRestore : .none).frame
                })
            try ensureConfigurationReadSession(generation)
            ws3DisplaySnapshot = WS3DisplaySnapshot(generation: generation, brightness: baseline.brightness,
                resources: baseline.resources.map { $0.id == actual.id ? actual : $0 })
            return actual
        } catch {
            if generation == commandSessionGeneration {
                ws3DisplaySnapshot = nil
                if attemptedWrite { invalidateCommandResponseChannel() }
            }
            throw error
        }
    }

    func uploadWS3Resource(_ payload: WS3ResourcePayload, baseline: WS3DisplaySnapshot) async throws -> WS3ResourceReadback {
        guard !isConfigurationOperationInProgress, canEditWS3Display,
              firmwareCapabilityProfile?.mayQueryWS3Resources == true,
              baseline.generation == commandSessionGeneration,
              let peripheral, let commandChar else { throw WS3ResourceUploadError.unverifiedConnection }
        let generation = commandSessionGeneration
        let writeType: CBCharacteristicWriteType = commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let maximum = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = min(48, maximum - 11)
        guard maximum >= 16, chunkSize > 0 else { throw WS3ResourceUploadError.invalidMTU }
        isUploadingOLED = true
        let totalChunks = (payload.bytes.count + chunkSize - 1) / chunkSize
        oledUploadProgress = .init(completedChunks: 0, totalChunks: totalChunks, completedFrames: 0, totalFrames: Int(payload.frameCount))
        defer {
            if generation == commandSessionGeneration { isUploadingOLED = false; oledUploadProgress = nil }
        }
        var lastProgressAt = ProcessInfo.processInfo.systemUptime
        do {
            let actual = try await ConfirmedWS3ResourceUpload.run(payload: payload, baseline: baseline,
                generation: generation, maximumWriteLength: maximum, checkSession: {
                    try self.ensureConfigurationReadSession(generation)
                }, exchange: { request in
                    try await self.sendCommandAwaitingResponse(request, expectedCommand: request[2],
                        confirmedWrite: request[2] == 0x88 ? .none : .ws3Resource).frame
                }, progress: { bytes, total in
                    let now = ProcessInfo.processInfo.systemUptime
                    guard bytes == total || now - lastProgressAt >= 0.2 else { return }
                    lastProgressAt = now
                    self.oledUploadProgress = .init(completedChunks: (bytes + chunkSize - 1) / chunkSize,
                        totalChunks: totalChunks, completedFrames: bytes / Int(WS3ResourceReadback.frameBytes), totalFrames: Int(payload.frameCount))
                })
            try ensureConfigurationReadSession(generation)
            ws3DisplaySnapshot = WS3DisplaySnapshot(generation: generation, brightness: baseline.brightness,
                resources: baseline.resources.map { $0.id == actual.id ? actual : $0 })
            appendLog("素材上传完成，帧数/长度/CRC元数据读回一致")
            return actual
        } catch {
            if generation == commandSessionGeneration {
                // Revoke the configuration link, without promising that macOS
                // released the physical HID link or firmware upload owner.
                // 8D is destructive clear, never a cancellation shortcut.
                invalidateCommandResponseChannel()
            }
            throw error
        }
    }

    /// Publish only a complete, current-connection four-mode catalog.
    func readWS3LightCatalogForEditing() async throws -> WS3LightCatalogSnapshot {
        guard !isConfigurationOperationInProgress, canEditWS3Display,
              let baseline = ws3DisplaySnapshot else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.reading)
        ws3LightCatalogSnapshot = nil
        ws3SingleLightSnapshot = nil
        defer { finishWS3DisplayOperation(displayOperation) }
        let result = try await ConfirmedWS3LightCatalog.read(baseline: baseline, generation: generation,
            checkSession: { try self.ensureConfigurationReadSession(generation) },
            exchange: { request in
                try await self.sendCommandAwaitingResponse(request, expectedCommand: 0x88, allowDeviceError: true).frame
            })
        try ensureConfigurationReadSession(generation)
        ws3LightCatalogSnapshot = result
        return result
    }

    func readWS3SingleLightForEditing(mode: UInt8, state: UInt8) async throws -> WS3SingleLightSnapshot {
        guard !isConfigurationOperationInProgress, canEditWS3Display else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.reading)
        ws3SingleLightSnapshot = nil
        defer { finishWS3DisplayOperation(displayOperation) }
        do {
            guard case .singleLight(let effect) = try await readWS3DisplayValue(.singleLight(mode: mode, state: state), generation: generation) else {
                throw OLEDUploadError.invalidReadback
            }
            try ensureConfigurationReadSession(generation)
            let result = WS3SingleLightSnapshot(generation: generation, mode: mode, state: state, effect: effect)
            ws3SingleLightSnapshot = result
            ws3LightCatalogSnapshot = ws3LightCatalogSnapshot?.replacing(result)
            return result
        } catch {
            if generation == commandSessionGeneration { ws3LightCatalogSnapshot = nil }
            throw error
        }
    }

    /// A narrow fresh read used to verify a completed component write batch.
    func readWS3SettingForEditing(_ setting: WS3DisplaySetting) async throws -> UInt8 {
        if case .singleLight(let mode, let state, _) = setting {
            return try await readWS3SingleLightForEditing(mode: mode, state: state).effect
        }
        guard !isConfigurationOperationInProgress, canEditWS3Display else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        let operation = beginWS3DisplayOperation(.reading)
        defer { finishWS3DisplayOperation(operation) }
        guard case .brightness(let value) = try await readWS3DisplayValue(.brightness, generation: generation) else {
            throw OLEDUploadError.invalidReadback
        }
        try ensureConfigurationReadSession(generation)
        return value
    }

    func previewWS3Display(_ preview: WS3DisplayPreview) async throws {
        guard !isConfigurationOperationInProgress, canEditWS3Display else { throw OLEDUploadError.channelNotReady }
        guard let request = preview.request else { throw ConfirmedWS3DisplaySetting.Failure.invalidValue }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.updating)
        defer { finishWS3DisplayOperation(displayOperation) }
        try ensureConfigurationReadSession(generation)
        _ = try await sendCommandAwaitingResponse(request, expectedCommand: 0x89, confirmedWrite: .ws3Display)
        try ensureConfigurationReadSession(generation)
        // ACK proves command acceptance only. Firmware expires preview in 10s;
        // never start a client refresh loop or claim the rendered scene was observed.
    }

    func saveWS3DisplaySetting(_ target: WS3DisplaySetting, baseline: UInt8, expectedGeneration: UInt64) async throws {
        guard !isConfigurationOperationInProgress, canEditWS3Display,
              expectedGeneration == commandSessionGeneration else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        let displayOperation = beginWS3DisplayOperation(.updating)
        defer { finishWS3DisplayOperation(displayOperation) }
        do {
            let actual = try await ConfirmedWS3DisplaySetting.run(target: target, baseline: baseline, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, read: { item in
                let value = try await self.readWS3DisplayValue(item, generation: generation)
                switch value {
                case .brightness(let value), .singleLight(let value): return value
                default: throw OLEDUploadError.invalidReadback
                }
            }, write: { request in
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: 0x8E, confirmedWrite: .ws3Display)
            })
            try ensureConfigurationReadSession(generation)
            switch target {
            case .brightness:
                if let snapshot = ws3DisplaySnapshot {
                    ws3DisplaySnapshot = WS3DisplaySnapshot(generation: generation, brightness: actual, resources: snapshot.resources)
                }
            case .singleLight(let mode, let state, _):
                let updated = WS3SingleLightSnapshot(generation: generation, mode: mode, state: state, effect: actual)
                ws3SingleLightSnapshot = updated
                ws3LightCatalogSnapshot = ws3LightCatalogSnapshot?.replacing(updated)
            }
        } catch {
            if generation == commandSessionGeneration {
                ws3DisplaySnapshot = nil
                ws3SingleLightSnapshot = nil
                ws3LightCatalogSnapshot = nil
            }
            throw error
        }
    }

    /// Explicit read only: never applies local drafts or persists device settings.
    func readDeviceConfigurationSnapshot() async throws {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isReadingConfigurationSnapshot = true
        defer { isReadingConfigurationSnapshot = false }
        configurationSnapshot.reset(generation: generation)
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.isVerifiedProtocol else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        var fields: [DeviceConfigurationSnapshot.Field] = [.standby, .voice, .sideSwitch]
        for mode: UInt8 in 0..<4 {
            for index: UInt8 in 0..<4 { fields.append(.key(mode: mode, index: index)) }
        }
        for field in fields {
            try ensureConfigurationReadSession(generation)
            do {
                switch field {
                case .standby: _ = try await readStandbyMinutes()
                case .voice: _ = try await readVoiceOnboardingState()
                case .sideSwitch: _ = try await readSideSwitchBinding()
                case .key(let mode, let index): _ = try await readOrdinaryKey(mode: mode, keyIndex: index)
                }
            } catch {
                try ensureConfigurationReadSession(generation)
                configurationSnapshot.recordFailure(field, message: error.localizedDescription, generation: generation)
            }
        }
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

    func readStandbyForEditing() async throws -> UInt16 {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isReadingStandby = true
        defer { isReadingStandby = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryStandby else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        try ensureConfigurationReadSession(generation)
        return try await readStandbyMinutes()
    }

    func setStandbyConfirmed(_ target: UInt16) async throws -> UInt16 {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        guard ConfirmedStandbySetting.supportedMinutes.contains(target) else { throw ConfirmedStandbySetting.Failure.invalidValue }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isSettingStandby = true
        defer { isSettingStandby = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryStandby else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        do {
            return try await ConfirmedStandbySetting.run(target: target, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, read: { try await self.readStandbyMinutes() }, write: { value in
                guard let request = ConfirmedStandbySetting.request(minutes: value) else { throw ConfirmedStandbySetting.Failure.invalidValue }
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: 0x95, confirmedWrite: .standby)
            })
        } catch {
            self.configurationSnapshot.recordFailure(.standby, message: error.localizedDescription, generation: generation)
            throw error
        }
    }

    func readVoiceHandoffForEditing() async throws -> VoiceHandoffSnapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isManagingVoiceHandoff = true
        defer { isManagingVoiceHandoff = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryVoiceOnboarding && profile.mayQueryOrdinaryKeys else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        try ensureConfigurationReadSession(generation)
        return try await readVoiceHandoffSnapshot()
    }

    private func readVoiceHandoffSnapshot() async throws -> VoiceHandoffSnapshot {
        let state = try await readVoiceOnboardingState()
        var keys: [OrdinaryKeyReadback] = []
        for mode: UInt8 in 0..<4 { keys.append(try await requireOrdinaryKey(mode: mode, index: 0)) }
        let snapshot = VoiceHandoffSnapshot(onboardingState: state, keys: keys)
        guard snapshot.isValid else { throw ConfirmedVoiceHandoff.Failure.invalidSnapshot }
        return snapshot
    }

    func takeOverVoiceConfirmed(baseline: VoiceHandoffSnapshot, expectedGeneration: UInt64,
                               checkHostReady: () throws -> Void, prepareHost: () throws -> Void) async throws -> VoiceHandoffSnapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        guard generation == expectedGeneration else { throw OLEDUploadError.channelNotReady }
        isManagingVoiceHandoff = true
        defer { isManagingVoiceHandoff = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryVoiceOnboarding && profile.mayQueryOrdinaryKeys else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        do {
            return try await ConfirmedVoiceHandoff.run(baseline: baseline, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, checkHostReady: checkHostReady, read: { try await self.readVoiceHandoffSnapshot() }, prepareHost: prepareHost, write: { request in
                guard let peripheral = self.peripheral, let characteristic = self.commandChar else { throw OLEDUploadError.channelNotReady }
                let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                let maximum = peripheral.maximumWriteValueLength(for: type)
                guard request.count <= maximum else { throw ConfirmedSideSwitchSetting.Failure.transportLimit(maximum: maximum) }
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: request[2], confirmedWrite: .voiceHandoff)
            })
        } catch {
            self.configurationSnapshot.recordFailure(.voice, message: error.localizedDescription, generation: generation)
            for mode: UInt8 in 0..<4 {
                self.configurationSnapshot.recordFailure(.key(mode: mode, index: 0), message: error.localizedDescription, generation: generation)
            }
            throw error
        }
    }

    func changeVoiceModeConfirmed(baseline: VoiceHandoffSnapshot, target: OrdinaryKeyReadback, expectedGeneration: UInt64,
                               checkHostReady: () throws -> Void, prepareHost: () throws -> Void, writeStarted: () -> Void = {}) async throws -> VoiceHandoffSnapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        guard generation == expectedGeneration else { throw OLEDUploadError.channelNotReady }
        isManagingVoiceHandoff = true
        defer { isManagingVoiceHandoff = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryVoiceOnboarding && profile.mayQueryOrdinaryKeys else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        do {
            return try await ConfirmedVoiceModeChange.run(baseline: baseline, target: target, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, checkHostReady: checkHostReady, read: { try await self.readVoiceHandoffSnapshot() }, validateCurrentKey: { actual in
                guard let mode = AhaKeyModeSlot(rawValue: Int(actual.mode)),
                      StudioKeyWriteProposal.draft(from: actual, preserving: AhaKeyModeDraft.default(for: mode).key(for: .voice)) != nil else {
                    throw ConfirmedOrdinaryKeySetting.Failure.invalidValue
                }
            }, prepareHost: prepareHost, write: { request in
                guard let peripheral = self.peripheral, let characteristic = self.commandChar else { throw OLEDUploadError.channelNotReady }
                let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                let maximum = peripheral.maximumWriteValueLength(for: type)
                guard request.count <= maximum else { throw ConfirmedSideSwitchSetting.Failure.transportLimit(maximum: maximum) }
                writeStarted()
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: request[2], confirmedWrite: request[2] == 0x96 ? .voiceHandoff : .ordinaryKey)
            })
        } catch {
            self.configurationSnapshot.recordFailure(.voice, message: error.localizedDescription, generation: generation)
            for mode: UInt8 in 0..<4 {
                self.configurationSnapshot.recordFailure(.key(mode: mode, index: 0), message: error.localizedDescription, generation: generation)
            }
            throw error
        }
    }

    func readOrdinaryKeyForEditing(mode: UInt8, index: UInt8) async throws -> OrdinaryKeyReadback {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isEditingOrdinaryKey = true
        defer { isEditingOrdinaryKey = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryOrdinaryKeys else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        try ensureConfigurationReadSession(generation)
        return try await requireOrdinaryKey(mode: mode, index: index)
    }

    /// New routing is proved on every acquired connection, never inferred from
    /// the unchanged WS2 catalog key or the old global onboarding byte.
    func readK1RoutesForEditing() async throws -> K1OutputRouteTransaction.Snapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isManagingK1Route = true; k1RouteProofGeneration = nil
        defer { isManagingK1Route = false; k1RouteProofGeneration = nil }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryOrdinaryKeys else { throw K1OutputRouteTransaction.Failure.unsupported }
        return try await K1OutputRouteTransaction.read(checkSession: {
            try self.ensureConfigurationReadSession(generation)
        }, exchange: { try await self.exchangeK1Route($0, generation: generation) })
    }

    func setK1RouteConfirmed(mode: UInt8, baseline: K1OutputRoute, target: K1OutputRoute,
                             expectedGeneration: UInt64, prepareHost: () throws -> Void,
                             writeStarted: () -> Void) async throws -> K1OutputRouteTransaction.Snapshot {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        guard generation == expectedGeneration else { throw OLEDUploadError.channelNotReady }
        isManagingK1Route = true; k1RouteProofGeneration = nil
        defer { isManagingK1Route = false; k1RouteProofGeneration = nil }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryOrdinaryKeys, let peripheral, let characteristic = commandChar else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        return try await K1OutputRouteTransaction.save(mode: mode, baseline: baseline, target: target,
            maximumRequestBytes: min(62, peripheral.maximumWriteValueLength(for: type)), checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, prepareHost: prepareHost, writeStarted: writeStarted,
            exchange: { try await self.exchangeK1Route($0, generation: generation) })
    }

    private func exchangeK1Route(_ command: K1OutputRouteCommand, generation: UInt64) async throws -> Data {
        try ensureConfigurationReadSession(generation)
        guard let request = command.request, let peripheral, let characteristic = commandChar else {
            throw OLEDUploadError.invalidCommandFrame
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        guard request.count <= peripheral.maximumWriteValueLength(for: type) else { throw K1OutputRouteTransaction.Failure.transportLimit }
        let isWrite = [UInt8(0x20), 0x21, 0x22].contains(command.subcommand)
        let reply = try await sendCommandAwaitingResponse(request, expectedCommand: 0x9E, allowDeviceError: true,
            confirmedWrite: isWrite ? .k1Route : .none)
        try ensureConfigurationReadSession(generation)
        if command.subcommand == 0, K1OutputRouteReply.parse(reply.frame, for: command) == .capability {
            k1RouteProofGeneration = generation
        }
        return reply.frame
    }

    private func requireOrdinaryKey(mode: UInt8, index: UInt8) async throws -> OrdinaryKeyReadback {
        let result = try await readOrdinaryKey(mode: mode, keyIndex: index)
        guard case .value(let value) = result else { throw OLEDUploadError.invalidReadback }
        return value
    }

    func setOrdinaryKeyConfirmed(baseline: OrdinaryKeyReadback, target: OrdinaryKeyReadback, expectedGeneration: UInt64) async throws -> OrdinaryKeyReadback {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        guard generation == expectedGeneration else { throw OLEDUploadError.channelNotReady }
        isEditingOrdinaryKey = true
        defer { isEditingOrdinaryKey = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryOrdinaryKeys else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        do {
            guard let peripheral, let characteristic = commandChar else { throw OLEDUploadError.channelNotReady }
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            let maximum = peripheral.maximumWriteValueLength(for: type)
            var planned: [Data] = []
            if baseline.actionType != target.actionType || baseline.action != target.action,
               let request = OrdinaryKeyConfiguration.actionRequest(target) { planned.append(request) }
            if baseline.description != target.description,
               let request = OrdinaryKeyConfiguration.descriptionRequest(target) { planned.append(request) }
            guard planned.allSatisfy({ $0.count <= maximum }) else { throw ConfirmedSideSwitchSetting.Failure.transportLimit(maximum: maximum) }
            return try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, read: { try await self.requireOrdinaryKey(mode: target.mode, index: target.keyIndex) }, voiceState: {
                try await self.readVoiceOnboardingState()
            }, write: { request in
                guard let peripheral = self.peripheral, let characteristic = self.commandChar else { throw OLEDUploadError.channelNotReady }
                let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                let maximum = peripheral.maximumWriteValueLength(for: type)
                guard request.count <= maximum else { throw ConfirmedSideSwitchSetting.Failure.transportLimit(maximum: maximum) }
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: request[2], confirmedWrite: .ordinaryKey)
            })
        } catch {
            self.configurationSnapshot.recordFailure(.key(mode: target.mode, index: target.keyIndex), message: error.localizedDescription, generation: generation)
            throw error
        }
    }

    func readSideSwitchForEditing() async throws -> SideSwitchReadback {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isReadingSideSwitch = true
        defer { isReadingSideSwitch = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQuerySideSwitchBindings else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        try ensureConfigurationReadSession(generation)
        return try await readSideSwitchBinding()
    }

    func setSideSwitchConfirmed(baseline: [SideSwitchReadback.Position], target: [SideSwitchReadback.Position], expectedGeneration: UInt64) async throws -> SideSwitchReadback {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        guard generation == expectedGeneration else { throw OLEDUploadError.channelNotReady }
        isSettingSideSwitch = true
        defer { isSettingSideSwitch = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQuerySideSwitchBindings else { throw OLEDUploadError.unsupportedReadOnlyProfile }
        do {
            return try await ConfirmedSideSwitchSetting.run(baseline: baseline, target: target, checkSession: {
                try self.ensureConfigurationReadSession(generation)
            }, read: { try await self.readSideSwitchBinding() }, write: { request in
                guard let peripheral = self.peripheral, let characteristic = self.commandChar else {
                    throw OLEDUploadError.channelNotReady
                }
                let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                let maximum = peripheral.maximumWriteValueLength(for: type)
                guard request.count <= maximum else { throw ConfirmedSideSwitchSetting.Failure.transportLimit(maximum: maximum) }
                _ = try await self.sendCommandAwaitingResponse(request, expectedCommand: 0x97, confirmedWrite: .sideSwitch)
            })
        } catch {
            self.configurationSnapshot.recordFailure(.sideSwitch, message: error.localizedDescription, generation: generation)
            throw error
        }
    }

    func switchWorkModeConfirmed(_ target: UInt8) async throws -> UInt8 {
        guard !isConfigurationOperationInProgress else { throw OLEDUploadError.channelNotReady }
        let generation = commandSessionGeneration
        try ensureConfigurationReadSession(generation)
        isChangingWorkMode = true
        defer { isChangingWorkMode = false }
        let profile = try await readFirmwareCapabilityProfile()
        guard profile.mayQueryOrdinaryKeys || profile.identity == .legacy else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        return try await ConfirmedModeChange.run(target: target, checkSession: {
            try self.ensureConfigurationReadSession(generation)
        }, readMode: {
            let response = try await self.sendCommandAwaitingResponse(AhaKeyCommand.queryDeviceStatus(), expectedCommand: 0x00)
            guard let status = AhaKeyResponseParser.parseDeviceStatus(response.frame), (0..<4).contains(status.workMode) else {
                throw OLEDUploadError.invalidDeviceStatusPayload
            }
            return UInt8(status.workMode)
        }, writeMode: { mode in
            _ = try await self.sendCommandAwaitingResponse(
                AhaKeyCommand.setWorkMode(mode), expectedCommand: AhaKeyCommand.cmdSetWorkMode,
                confirmedWrite: .mode
            )
        })
    }

    func beginPresentationOperation() throws -> UInt64 {
        guard !isConfigurationOperationInProgress, canEditWS3Display else { throw WS3PresentationError.busy }
        isChangingPresentation = true
        return commandSessionGeneration
    }
    func finishPresentationOperation(generation: UInt64) {
        if generation == commandSessionGeneration { isChangingPresentation = false }
    }
    func setPresentationRuntimeActive(_ active: Bool) { presentationRuntimeActive = active }
    func blockLegacySinglePresentation(_ blocked: Bool) { presentationBlocksLegacySingle = blocked }
    func exchangePresentation(_ request: Data, generation: UInt64) async throws -> Data {
        try ensureConfigurationReadSession(generation)
        guard AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio,
              canEditWS3Display, request.count >= 5, [UInt8(0x9F), 0x88, 0x98, 0x99].contains(request[2]) else {
            throw WS3PresentationError.unavailable
        }
        let reply = try await sendCommandAwaitingResponse(request, expectedCommand: request[2], confirmedWrite: .ws3Presentation)
        try ensureConfigurationReadSession(generation)
        guard AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio else { throw WS3PresentationError.connectionChanged }
        return reply.frame
    }
    func sendPresentationDefault(generation: UInt64) -> Bool {
        sendPresentationState(4, generation: generation)
    }
    @discardableResult
    func sendPresentationState(_ state: UInt8, generation: UInt64) -> Bool {
        guard generation == commandSessionGeneration, canEditWS3Display,
              state <= 8, AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio else { return false }
        writeCommand(WS3PresentationCommand.single(state: state).request!, confirmedWrite: .ws3Presentation)
        return true
    }
    func poisonPresentationConnection(generation: UInt64) {
        guard generation == commandSessionGeneration else { return }
        invalidateCommandResponseChannel()
    }

    /// 修改设备蓝牙名称；名称不合法时不发送任何命令，设备保留原名。
    @discardableResult
    func changeDeviceName(_ rawName: String) -> Result<String, AhaKeyCommand.DeviceNameValidationError> {
        let validation = AhaKeyCommand.validateDeviceName(rawName)
        guard case .success(let name) = validation else {
            appendLog("设备名不合法，未发送: \(rawName)", isError: true)
            return validation
        }
        let cmd = AhaKeyCommand.changeName(name)
        appendLog("修改设备名: \(name)")
        writeCommand(cmd)
        // 修改后保存并刷新
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(100) * 1_000_000)
            self.saveConfig()
        }
        return validation
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
        guard !suppressAutomaticConnection, !connectionAttempt.requiresManualRetry else { return }
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
        guard !suppressAutomaticConnection, !connectionAttempt.requiresManualRetry else { return }
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
                guard !self.commandTurnOccupied, !self.commandChannelUnsynchronized else { return }
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
            if agentBatteryLevel != nil { agentBatteryLevel = nil }
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
            let battery = obj["battery"] as? Int
            let lm = obj["lightMode"] as? Int
            let sw = obj["switchState"] as? Int
            let wm = obj["workMode"] as? Int
            let validBattery = battery.flatMap { (0...100).contains($0) ? $0 : nil }
            if agentBatteryLevel != validBattery { agentBatteryLevel = validBattery }
            if agentLightMode != lm { agentLightMode = lm }
            if agentSwitchState != sw { agentSwitchState = sw }
            updateAgentWorkMode(wm)
        } else {
            if agentBatteryLevel != nil { agentBatteryLevel = nil }
            if agentLightMode != nil { agentLightMode = nil }
            if agentSwitchState != nil { agentSwitchState = nil }
            if agentWorkMode != nil { agentWorkMode = nil }
        }
        scheduleIDEStateExpiry(at: expiryDeadlines.min())
    }

    private func updateAgentWorkMode(_ value: Int?) {
        let valid = value.flatMap { (0..<4).contains($0) ? $0 : nil }
        guard agentWorkMode != valid else { return }
        agentWorkMode = valid
        guard !isConnected, agentBLEConnectedProvider(), let valid else { return }
        NotificationCenter.default.post(name: .ahaKeyKeyboardWorkModeChanged, object: self, userInfo: ["workMode": valid])
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

    private func acquireCommandTurn() async throws -> CommandTurnQueue.Ticket {
        do { return try await commandTurns.acquire() }
        catch CommandTurnQueue.Failure.invalidated { throw OLEDUploadError.responseChannelUnsynchronized }
        catch CommandTurnQueue.Failure.reset { throw OLEDUploadError.channelNotReady }
    }

    private func resetCommandSession() {
        k1RouteProofGeneration = nil
        commandSessionGeneration &+= 1
        isChangingPresentation = false
        presentationRuntimeActive = false
        presentationBlocksLegacySingle = false
        activeWS3DisplayOperation = nil
        isReadingWS3Display = false
        isUpdatingWS3Display = false
        commandTurns.reset(generation: commandSessionGeneration)
        hasValidStatusReadback = false
        firmwareCapabilityProfile = nil
        ws3DisplaySnapshot = nil
        ws3SingleLightSnapshot = nil
        ws3LightCatalogSnapshot = nil
        configurationSnapshot.reset(generation: commandSessionGeneration)
        if let pending = pendingCommandResponse {
            pendingCommandResponse = nil
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: OLEDUploadError.channelNotReady)
        }
        if let pending = pendingDataWrite {
            pendingDataWrite = nil
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: OLEDUploadError.channelNotReady)
        }
    }

    /// Invalidate device facts as soon as ownership is yielded, before the
    /// asynchronous CoreBluetooth disconnect callback arrives.
    private func invalidateConnectionState() {
        resetCommandSession()
        apply(.disconnected)
        dataChar = nil
        commandChar = nil
        notifyChar = nil
        batteryLevelChar = nil
        dataCharReady = false
        commandCharReady = false
        notifyCharReady = false
        dataNotificationFramer.reset()
        notifyNotificationFramer.reset()
        supportsConfigurableLighting = nil
        keyboardPictureStates.removeAll()
        writeQueue.removeAll()
        writeBatches.removeAll()
        isWriting = false
        didQueryAfterConnect = false
        isUploadingOLED = false
        oledUploadProgress = nil
    }

    private func timeoutCommandResponse(id: UInt64, generation: UInt64) {
        guard let pending = pendingCommandResponse,
              pending.id == id, pending.generation == generation else { return }
        pendingCommandResponse = nil
        // ACKs have no transaction ID. A late reply could otherwise complete
        // a later request for the same command, so writes wait for reconnect.
        invalidateCommandResponseChannel()
        pending.continuation.resume(throwing: OLEDUploadError.timeout(command: pending.command))
    }

    /// Cancelling an already-sent command is not a rollback. Its untagged ACK
    /// must not be consumed by another operation on this connection.
    func cancelConfigurationOperation() {
        guard isConfigurationOperationInProgress else { return }
        if let pending = pendingCommandResponse {
            cancelCommandResponse(id: pending.id, generation: pending.generation)
        } else if let pending = pendingDataWrite {
            cancelDataWrite(id: pending.id, generation: pending.generation)
        } else { invalidateCommandResponseChannel() }
    }

    private func invalidateCommandResponseChannel() {
        k1RouteProofGeneration = nil
        commandTurns.invalidate()
        // A poisoned channel also terminates any companion data/control request.
        // The initiating caller already removed its own pending entry and keeps
        // its original cancellation/timeout error.
        if let pending = pendingCommandResponse {
            pendingCommandResponse = nil
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: OLEDUploadError.responseChannelUnsynchronized)
        }
        if let pending = pendingDataWrite {
            pendingDataWrite = nil
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: OLEDUploadError.responseChannelUnsynchronized)
        }
        hasValidStatusReadback = false
        firmwareCapabilityProfile = nil
        ws3DisplaySnapshot = nil
        ws3SingleLightSnapshot = nil
        ws3LightCatalogSnapshot = nil
        configurationSnapshot.reset(generation: commandSessionGeneration)
        appendLog("Configuration interrupted; reconnect and read back before continuing.", isError: true)
        if let peripheral {
            awaitingPeripheralDisconnect = true
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    private func cancelCommandResponse(id: UInt64, generation: UInt64) {
        guard let pending = pendingCommandResponse,
              pending.id == id, pending.generation == generation else { return }
        pendingCommandResponse = nil
        pending.timeoutTask.cancel()
        invalidateCommandResponseChannel()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func completeCommandResponse(_ frame: Data) {
        guard let pending = pendingCommandResponse,
              pending.generation == commandSessionGeneration,
              DeviceResponseMatcher.matches(
                  request: pending.request, expectedCommand: pending.command, response: frame
              ) else { return }
        let result: CommandResponse
        if pending.command == 0x00 {
            result = (status: 0, payload: frame, frame: frame)
        } else if let response = AhaKeyResponseParser.parseCommandResponse(frame) {
            result = (status: response.status, payload: response.payload, frame: frame)
        } else {
            return
        }
        pendingCommandResponse = nil
        pending.timeoutTask.cancel()
        pending.continuation.resume(returning: result)
    }

    private func sendCommandAwaitingResponse(
        _ data: Data, expectedCommand: UInt8, timeoutSeconds: Double = 5.0,
        allowDeviceError: Bool = false, confirmedWrite: ConfigurationCommandPolicy.ConfirmedWrite = .none
    ) async throws -> CommandResponse {
        guard peripheral != nil, commandChar != nil else { throw OLEDUploadError.disconnected }
        let ticket = try await acquireCommandTurn()
        let generation = ticket.generation
        defer { commandTurns.release(ticket) }
        guard ConfigurationCommandPolicy.permits(data, profile: firmwareCapabilityProfile, confirmedWrite: confirmedWrite,
                                               ws3DisplayReadbackVerified: canEditWS3Display,
                                               k1RouteReadbackVerified: hasCurrentK1RouteProof) else {
            throw OLEDUploadError.unsupportedReadOnlyProfile
        }
        try Task.checkCancellation()
        guard commandTurns.isCurrent(ticket), generation == commandSessionGeneration,
              !awaitingPeripheralDisconnect, commandChar != nil, peripheral != nil else {
            throw OLEDUploadError.channelNotReady
        }
        nextCommandRequestID &+= 1
        let id = nextCommandRequestID
        let result: CommandResponse = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    } catch { return }
                    self?.timeoutCommandResponse(id: id, generation: generation)
                }
                pendingCommandResponse = PendingCommandResponse(
                    id: id, generation: generation, request: data, command: expectedCommand,
                    continuation: continuation, timeoutTask: timeoutTask
                )
                dataNotificationFramer.expectResponse(to: data)
                notifyNotificationFramer.expectResponse(to: data)
                writeCommand(data, confirmedWrite: confirmedWrite)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelCommandResponse(id: id, generation: generation) }
        })
        try Task.checkCancellation()
        guard commandTurns.isCurrent(ticket), generation == commandSessionGeneration,
              !awaitingPeripheralDisconnect else { throw OLEDUploadError.channelNotReady }
        guard allowDeviceError || result.status == 0 else {
            throw OLEDUploadError.deviceRejected(command: expectedCommand, status: result.status)
        }
        return result
    }

    /// Shares the production pending command slot: an old timeout/cancel cannot clear a new request.
    func awaitProtocolResponse(expectedCommand: UInt8, timeoutSeconds: Double,
                               send: () -> Void) async throws -> CommandResponse {
        guard !commandChannelUnsynchronized else { throw OLEDUploadError.reconnectRequired }
        if let old = pendingCommandResponse {
            pendingCommandResponse = nil
            old.timeoutTask.cancel()
            old.continuation.resume(throwing: OLEDUploadError.superseded(command: old.command))
        }
        nextCommandRequestID &+= 1
        let id = nextCommandRequestID, generation = commandSessionGeneration
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)) }
                    catch { return }
                    self?.timeoutCommandResponse(id: id, generation: generation)
                }
                pendingCommandResponse = PendingCommandResponse(id: id, generation: generation,
                    request: Data([0xAA, 0xBB, expectedCommand, 0xCC, 0xDD]), command: expectedCommand,
                    continuation: continuation, timeoutTask: timer)
                send()
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelCommandResponse(id: id, generation: generation) }
        })
    }

    func failPendingDeviceOperations() {
        failPendingResponses(with: OLEDUploadError.disconnected)
    }

    private func writeDataChunk(
        _ data: Data, to peripheral: CBPeripheral,
        characteristic: CBCharacteristic, type: CBCharacteristicWriteType,
        timeoutSeconds: Double = AhaKeyBLEManager.dataWriteResultTimeoutSeconds
    ) async throws {
        guard acceptsConnectionCallbacks, !awaitingPeripheralDisconnect,
              self.peripheral === peripheral, self.dataChar === characteristic else {
            throw OLEDUploadError.channelNotReady
        }
        let generation = commandSessionGeneration
        let negotiated = max(1, peripheral.maximumWriteValueLength(for: type))
        let packetSize = min(negotiated, AhaKeyCommand.oledPacketSize)
        appendLog("→ DATA \(data.count)B, 分片 \(packetSize)B (协商上限 \(negotiated)B)", category: .verbose)
        try await awaitDataWriteResult(timeoutSeconds: timeoutSeconds) {
            for offset in stride(from: 0, to: data.count, by: packetSize) {
                try Task.checkCancellation()
                guard generation == self.commandSessionGeneration, !self.commandChannelUnsynchronized,
                      !self.awaitingPeripheralDisconnect, self.peripheral === peripheral,
                      self.dataChar === characteristic else { throw OLEDUploadError.channelNotReady }
                if type == .withoutResponse {
                    var waited = 0
                    while !peripheral.canSendWriteWithoutResponse {
                        try Task.checkCancellation()
                        guard waited < 5_000, generation == self.commandSessionGeneration,
                              self.peripheral === peripheral, !self.awaitingPeripheralDisconnect,
                              !self.commandChannelUnsynchronized else { throw OLEDUploadError.dataWriteFailed("flow control stalled") }
                        try await Task.sleep(nanoseconds: 10_000_000)
                        waited += 10
                    }
                }
                let end = min(offset + packetSize, data.count)
                peripheral.writeValue(Data(data[offset ..< end]), for: characteristic, type: type)
                try await Task.sleep(nanoseconds: 12_000_000)
            }
        }
        try Task.checkCancellation()
        guard generation == commandSessionGeneration, !commandChannelUnsynchronized,
              !awaitingPeripheralDisconnect else { throw OLEDUploadError.channelNotReady }
    }

    /// One request ID and generation own packet delivery, ACK, timeout and cancellation.
    /// The ACK budget starts after the last packet; packet delivery remains cancellable.
    func awaitDataWriteResult(timeoutSeconds: Double,
                             sendPackets: @escaping @MainActor () async throws -> Void) async throws {
        guard !commandChannelUnsynchronized else { throw OLEDUploadError.reconnectRequired }
        guard pendingDataWrite == nil else { throw OLEDUploadError.uploadInProgress }
        nextDataWriteID &+= 1
        let id = nextDataWriteID, generation = commandSessionGeneration
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let work = Task { @MainActor [weak self] in
                    do {
                        try await sendPackets()
                        try Task.checkCancellation()
                        guard self?.pendingDataWrite?.id == id,
                              self?.pendingDataWrite?.generation == generation else { return }
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        self?.timeoutDataWrite(id: id, generation: generation)
                    } catch {
                        guard let self, let pending = self.pendingDataWrite,
                              pending.id == id, pending.generation == generation else { return }
                        self.pendingDataWrite = nil
                        self.invalidateCommandResponseChannel()
                        pending.continuation.resume(throwing: error)
                    }
                }
                pendingDataWrite = PendingDataWrite(id: id, generation: generation,
                    continuation: continuation, timeoutTask: work)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelDataWrite(id: id, generation: generation) }
        })
        try Task.checkCancellation()
    }

    private func cancelDataWrite(id: UInt64, generation: UInt64) {
        guard let pending = pendingDataWrite, pending.id == id, pending.generation == generation else { return }
        pendingDataWrite = nil
        pending.timeoutTask.cancel()
        invalidateCommandResponseChannel()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func timeoutDataWrite(id: UInt64, generation: UInt64) {
        guard let pending = pendingDataWrite, pending.id == id, pending.generation == generation else { return }
        pendingDataWrite = nil
        invalidateCommandResponseChannel()
        pending.continuation.resume(throwing: OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult))
    }

    private func invalidateDataWriteConnection() {
        // Caller settles its original error before poisoning the shared channel.
        dataCharReady = false
        if pendingDataWrite == nil { invalidateCommandResponseChannel() }
    }

    func finishDataWrite(_ result: Result<Void, Error>) {
        guard let pending = pendingDataWrite, pending.generation == commandSessionGeneration else { return }
        pendingDataWrite = nil
        pending.timeoutTask.cancel()
        if case .failure = result { invalidateCommandResponseChannel() }
        pending.continuation.resume(with: result)
    }

    private func completeDataWrite(status: UInt8) {
        finishDataWrite(status == 0 ? .success(()) : .failure(OLEDUploadError.deviceRejected(
            command: AhaKeyCommand.cmdWriteResult, status: status)))
    }

    func failPendingResponses(with error: Error) {
        let command = pendingCommandResponse, data = pendingDataWrite
        pendingCommandResponse = nil; pendingDataWrite = nil
        command?.timeoutTask.cancel(); data?.timeoutTask.cancel()
        command?.continuation.resume(throwing: error); data?.continuation.resume(throwing: error)
        if command != nil || data != nil { invalidateCommandResponseChannel() }
    }

    static func retryingOLEDTimeouts(maxAttempts: Int, canRetry: () -> Bool,
        onRetry: (_ nextAttempt: Int, _ error: Error) -> Void,
        _ operation: (_ attempt: Int) async throws -> Void) async throws {
        var attempt = 1
        while true {
            do { try await operation(attempt); return }
            catch OLEDUploadError.timeout(let command) where attempt < maxAttempts && canRetry() {
                attempt += 1
                onRetry(attempt, OLEDUploadError.timeout(command: command))
            }
        }
    }

}


/// Stage-specific legacy OLED error reporting, independent from WS3 transactions.
enum OLEDTransferStage: Equatable {
    case prepareWrite, dataWrite, commitPicture
    var label: String {
        switch self {
        case .prepareWrite: return "准备写入（0x80）"
        case .dataWrite: return "数据写入确认（0x81）"
        case .commitPicture: return "提交动图（0x82）"
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
            if AgentManager.shared.codexHooksInstalled {
                CodexApprovalSetupController.shared.requestOffer()
            }
            postNotification(
                title: "拨杆 → 自动批准",
                body: "Claude／Cursor 原生审批请求可由 Hook 自动批准。已授权的 Codex 本机桌面会话从下一轮随拨杆切换权限；未接管时继续原流程。Kimi 原生终端审批由自身管理。",
                identifier: "lab.jawa.ahakey.switch.auto",
                isCritical: true
            )
        } else if switchedToManual {
            postNotification(
                title: "拨杆 → 手动批准",
                body: "AhaKey 停止 Hook 自动批准；已接管的 Codex 本机桌面会话从下一轮切为请求批准，其他会话继续原流程，不拒绝正常操作。",
                identifier: "lab.jawa.ahakey.switch.manual",
                isCritical: false
            )
        }
    }

    private func postNotification(title: String, body: String, identifier: String, isCritical: Bool) {
        let center = UNUserNotificationCenter.current()
        let deliver = { [weak self] in
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString(title, comment: "")
            content.body = NSLocalizedString(body, comment: "")
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
        // A denied notification permission must not interrupt the user's work.
        // The optional Codex offer is already delivered by the bottom capsule.

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
    case pairingRequired

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
        case .pairingRequired: return NSLocalizedString("等待系统配对", comment: "")
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
        case .pairingRequired: return NSLocalizedString("新设备连接未完成，已暂停自动重试。请先在 macOS 蓝牙设置完成配对，再点击连接设备。", comment: "")
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
    case responseChannelUnsynchronized
    case deviceRejected(command: UInt8, status: UInt8)
    case uploadIncomplete(completedFrames: Int, totalFrames: Int, reason: String)
    case disconnected
    case superseded(command: UInt8)
    case reconnectRequired
    case uploadInProgress
    case uploadInterrupted
    case dataWriteFailed(String)
    case deviceDisconnected
    case transferFailed(
        stage: OLEDTransferStage, mode: UInt8,
        frame: Int, totalFrames: Int,
        chunk: Int?, totalChunks: Int?,
        attempts: Int, reason: String
    )
    case invalidPictureStatePayload
    case invalidDeviceStatusPayload
    case invalidReadback
    case unsupportedReadOnlyProfile
    case unsupportedWS3Readback
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
        case .timeout(let command) where command == AhaKeyCommand.cmdWriteResult:
            return "等待设备响应超时: 0x81。键盘未确认图片数据写入，本次写入已停止；请等待键盘重新连接后重新写入。"
        case .timeout(let command):
            return String(format: "等待设备响应超时: 0x%02X", command)
        case .responseChannelUnsynchronized:
            return "设备响应超时后无法区分迟到回包，请重新连接键盘再继续。"
        case .deviceRejected(let command, let status):
            return String(format: "设备拒绝了命令 0x%02X，状态码 0x%02X", command, status)
        case .uploadIncomplete(let completedFrames, let totalFrames, let reason):
            return "动图上传未完成（已写入 \(completedFrames)/\(totalFrames) 帧）：\(reason)"
        case .disconnected:
            return "设备连接已断开，本次写入未完成。"
        case .superseded(let command):
            return String(format: "另一项写入占用了设备通道，命令 0x%02X 已中止。", command)
        case .reconnectRequired:
            return "上次图片数据写入未获确认，请等待键盘重新连接后重新写入。"
        case .uploadInProgress:
            return "LCD 图片正在上传中，请等当前上传完成后再写入。"
        case .uploadInterrupted:
            return "图片数据写入被新的写入打断，请重新写入。"
        case .dataWriteFailed(let reason):
            return "图片数据发送失败：\(reason)。请保持键盘连接后重新写入。"
        case .deviceDisconnected:
            return "键盘连接已断开，本次写入已停止；请重新连接后再写入。"
        case .transferFailed(let stage, let mode, let frame, let totalFrames, let chunk, let totalChunks, let attempts, let reason):
            let modeTitle = AhaKeyModeSlot(rawValue: Int(mode))?.title ?? "mode \(mode)"
            var position = "\(modeTitle) 第 \(frame)/\(totalFrames) 帧"
            if let chunk, let totalChunks { position += "、第 \(chunk)/\(totalChunks) 块" }
            let attemptNote = attempts > 1 ? "，已自动重试 \(attempts - 1) 次" : ""
            return "LCD 动图上传在「\(stage.label)」阶段失败（\(position)\(attemptNote)）：\(reason)。该动图未确认生效，请保持键盘连接并靠近电脑后重新写入。"
        case .invalidPictureStatePayload:
            return "设备返回的动画槽位信息无法解析。"
        case .invalidDeviceStatusPayload:
            return "设备返回的状态信息无法解析。"
        case .invalidReadback:
            return "设备返回的配置内容无法解析。"
        case .unsupportedWS3Readback:
            return NSLocalizedString("当前固件未提供 WS3 显示读回，未修改键盘显示配置。", comment: "")
        case .unsupportedReadOnlyProfile:
            return "尚未确认当前固件支持这项只读查询。"
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
                self.handleBluetoothPoweredOff()
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
            guard self.acceptsConnectionCallbacks, self.connectionAttempt.mayBegin,
                  !self.awaitingPeripheralDisconnect else { return }
            self.appendLog("发现设备: \(name) RSSI=\(RSSI)")
            // 扫到目标设备广播：退避重置回 4s 并立即连接
            self.reconnectBackoff.reset()
            self.central?.stopScan()
            self.isScanning = false
            self.beginPeripheralConnection(peripheral)
            self.bleConnectionStatus = "连接中…"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks, !self.awaitingPeripheralDisconnect,
                  self.peripheral === peripheral,
                  self.connectionAttempt.connected(target: peripheral.identifier) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            self.connectionDeadlineTask?.cancel()
            self.connectionDeadlineTask = nil
            self.resetCommandSession()
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
            guard self.peripheral === peripheral else { return }
            self.connectionDeadlineTask?.cancel()
            self.connectionDeadlineTask = nil
            self.connectionAttempt.ended(target: peripheral.identifier)
            self.invalidateConnectionState()
            self.awaitingPeripheralDisconnect = false
            if self.peripheral === peripheral { self.peripheral = nil }
            if self.suppressAutomaticConnection {
                self.peripheral = nil
                self.connectionLock.release()
                return
            }
            if self.connectionAttempt.requiresManualRetry {
                self.bleConnectionStatus = NSLocalizedString("等待系统配对", comment: "")
                self.linkDiagnostic = .pairingRequired
                return
            }
            self.bleConnectionStatus = "连接失败"
            self.appendLog("连接失败: \(error?.localizedDescription ?? "未知")", isError: true)
            self.startAutoReconnectPolling()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            guard self.peripheral === peripheral else { return }
            self.connectionDeadlineTask?.cancel()
            self.connectionDeadlineTask = nil
            self.connectionAttempt.ended(target: peripheral.identifier)
            self.awaitingPeripheralDisconnect = false
            let dropped = self.writeQueue.count
            let openBatches = self.writeBatches.count
            if dropped > 0 || openBatches > 0 {
                self.appendLog(
                    "BLE 已断开，丢弃未发出命令 \(dropped) 条（未闭合批 \(openBatches) 个）。\(error.map { "原因：\($0.localizedDescription)" } ?? "")",
                    isError: true
                )
            }
            self.invalidateConnectionState()
            self.bleConnectionStatus = self.connectionAttempt.requiresManualRetry ? NSLocalizedString("等待系统配对", comment: "") : NSLocalizedString("已断开", comment: "")
            if self.connectionAttempt.requiresManualRetry { self.linkDiagnostic = .pairingRequired }
            // 不清 peripheral 和 lastPeripheralUUID——用于直连重试
            self.peripheral = nil
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
            guard self.acceptsConnectionCallbacks, self.peripheral === peripheral else { return }
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
            guard self.acceptsConnectionCallbacks, self.peripheral === peripheral else { return }
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
            guard self.peripheral === peripheral, self.acceptsNotification(characteristic) else { return }
            self.handleNotification(from: characteristic.uuid, data: data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks, self.peripheral === peripheral else { return }
            self.apply(.rssi(RSSI.intValue))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard self.acceptsConnectionCallbacks, self.peripheral === peripheral else { return }
            if let error {
                self.appendLog("写入特征 \(characteristic.uuid) 失败: \(error.localizedDescription)", isError: true)
                if self.peripheral === peripheral, characteristic === self.dataChar {
                    self.invalidateDataWriteConnection()
                    self.finishDataWrite(.failure(OLEDUploadError.dataWriteFailed(error.localizedDescription)))
                }
            } else {
                self.appendLog("写入特征 \(characteristic.uuid) 完成", category: .verbose)
            }
        }
    }

    /// 仅协议 ACK 需要当前写入通道身份；标准电量/设备信息读回不受 OLED 写入状态影响。
    func acceptsNotification(_ characteristic: CBCharacteristic) -> Bool {
        if characteristic.uuid == Self.dataCharUUID || characteristic.uuid == Self.notifyCharUUID {
            return !dataWriteRequiresReconnect && (characteristic === notifyChar || characteristic === dataChar)
        }
        return true
    }

    private func handleNotification(from uuid: CBUUID, data: Data) {
        let hex = data.hexString
        switch uuid {
        case Self.dataCharUUID:
            appendLog("← DATA(0x7341): \(hex)", category: .verbose)
            for frame in dataNotificationFramer.append(data) { parseProtocolResponse(frame) }
        case Self.notifyCharUUID:
            appendLog("← NOTIFY(0x7344): \(hex)", category: .verbose)
            for frame in notifyNotificationFramer.append(data) { parseProtocolResponse(frame) }
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
            hasValidStatusReadback = true
            apply(.fullStatus(
                battery: status.battery, firmwareMain: status.firmwareMain,
                firmwareSub: status.firmwareSub, workMode: status.workMode,
                lightMode: status.lightMode, switchState: status.switchState,
                brightness: status.brightness, activePictureSet: 0
            ))
            let supported = Self.statusAdvertisesConfigurableLighting(brightness: status.brightness)
            if supportsConfigurableLighting != supported { supportsConfigurableLighting = supported }
            completeCommandResponse(data)
        } else if AhaKeyResponseParser.isProtocolFrame(data) {
            if let response = AhaKeyResponseParser.parseCommandResponse(data) {
                completeCommandResponse(data)

                if response.cmd == AhaKeyCommand.cmdWriteResult {
                    completeDataWrite(status: response.status)
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
