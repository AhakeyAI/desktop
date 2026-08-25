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
    let startIndex: Int
    let frameCount: Int
    let frameIntervalMs: Int
    let totalCapacity: Int
}

/// 0x94/0x96 查询回来的任务图槽位标识
struct KeyboardTaskPictureSlot: Hashable {
    let mode: Int
    let set: Int
    let state: Int
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
    @Published private(set) var diagnosticsSnapshot = DeviceDiagnosticsSnapshot()

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
    /// 仅在当前 BLE 连接收到首帧完整状态后提供拨杆值，避免把初始/上次连接缓存误当实时状态。
    var currentConnectionSwitchState: Int? {
        coreSnapshot.hasReceivedFullStatus ? coreSnapshot.switchState : nil
    }
    var brightness: Int { coreSnapshot.brightness }
    var bleDeviceUUID: String { coreSnapshot.deviceUUID }
    /// 各 mode 当前激活的任务图套图索引（由 0x97 或设备状态上报）。
    var activeTaskPictureSets: [Int: Int] { coreSnapshot.activeTaskPictureSets }
    /// 4 位设备编号（广播 manufacturer data 或序列号提取），未识别为 "—"。
    var deviceIdentifier: String { coreSnapshot.deviceIdentifier }
    /// 设备序列号原文（2A25），未读取为 "—"。
    var deviceSerialNumber: String { coreSnapshot.deviceSerialNumber }
    /// 0x99 协商出的协议模式（M1d）。
    var protocolMode: AhaKeyProtocolMode { coreSnapshot.protocolMode }
    /// 0x99 查询回的固件能力（诊断遥测投影，仅协商成功时非空）。
    var firmwareCapabilities: AhaKeyFirmwareCapabilities? { diagnosticsSnapshot.firmwareCapabilities }
    /// 任务图配置入口（M2 的 0x93/0x95 路径选择以此为门）。
    var allowsTaskPictureConfiguration: Bool { coreSnapshot.protocolMode.allowsTaskPictureConfiguration }
    /// USB 有线配置通道启用入口（R2a 防护：仅 current 协议放行；M3 移植 USB 时消费）。
    var allowsUSBConfigurationTransport: Bool { coreSnapshot.protocolMode.allowsUSBConfigurationTransport }
    var taskPictureProtocolPlan: AhaKeyTaskPictureProtocolPlan? {
        AhaKeyTaskPictureProtocolPlan.make(mode: protocolMode, capabilities: firmwareCapabilities)
    }
    var supportedTaskDisplayStates: [AhaKeyTaskDisplayState] {
        taskPictureProtocolPlan?.states ?? []
    }

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
        if result.diagnostics != diagnosticsSnapshot { diagnosticsSnapshot = result.diagnostics }
        // pending 被确认/超时清除后，取消尚未触发的超时任务
        if coreSnapshot.pendingSwitchOverride == nil, switchOverrideTimeoutTask != nil {
            switchOverrideTimeoutTask?.cancel()
            switchOverrideTimeoutTask = nil
        }
        switch result.effect {
        case .none:
            break
        case .workModeChanged(let mode):
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": mode]
            )
        case .switchOverrideTimedOut:
            appendLog(
                NSLocalizedString("虚拟拨杆切换未在 3s 内收到设备确认，已回退到最后确认值", comment: ""),
                isError: true,
                category: .error
            )
        }
    }

    @Published private(set) var bleConnectionStatus: String = NSLocalizedString("未连接", comment: "")
    @Published private(set) var bluetoothPermissionGranted = true
    @Published private(set) var bluetoothPoweredOn = false
    @Published private(set) var oledUploadProgress: OLEDUploadProgress?
    @Published private(set) var isUploadingOLED = false
    /// 物理枚举到的 USB 配置接口；是否可用于命令仍由 current 协议与配置会话锁共同决定。
    @Published private(set) var usbDeviceIdentity: AhaKeyUSBDeviceIdentity?
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
    /// 各 mode 各状态任务图元信息（0x96 查询填充）。
    @Published private(set) var keyboardTaskPictureStates: [KeyboardTaskPictureSlot: AhaKeyTaskPictureState] = [:]

    /// 内存诊断级日志 Store（阶段 2：独立 ObservableObject，append 不再波及观察 manager 的 View）。
    /// 周期 TX/RX 不进这里；临时详细抓包见 `BLELogStore.setVerboseLoggingEnabled`。
    let logStore = BLELogStore()

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
    static let serialNumberCharUUID = CBUUID(string: "2A25")

    nonisolated static let deviceNamePrefix = AhaKeyDevicePresentation.bleNamePrefix

    // MARK: - Private

    private var central: CBCentralManager?
    private let usbTransport = AhaKeyUSBHIDTransport()
    private var peripheral: CBPeripheral?
    private var dataChar: CBCharacteristic?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var batteryLevelChar: CBCharacteristic?
    private var pendingConnect = false
    private var rssiTimer: Timer?
    private var autoReconnectTimer: Timer?
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
    private let connectionLock = BLEConnectionLock()
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
    private var protocolResponseTimeoutTasks: [UInt8: Task<Void, Never>] = [:]
    /// 0x9B 已开启、尚未收到 0x81 完成确认的写入会话；取消/失败时用 0x9A 回滚。
    private var currentUploadSessionID: UInt16?
    private var dataWriteResultContinuation: CheckedContinuation<Void, Error>?
    private var dataWriteTimeoutTask: Task<Void, Never>?
    private var dataPacketWriteTask: Task<Void, Never>?
    /// 某命令已因 USB 超时改走 BLE 时，忽略同 opcode 的迟到 USB 应答。
    private var bleFallbackCommands: Set<UInt8> = []
    /// 当前图片写入任务一旦发生 USB 数据确认超时，余下重试固定走 BLE。
    private var forceBLEPictureTransfer = false

    // MARK: - Init

    override init() {
        super.init()
        let storedOwner = UserDefaults.standard.string(forKey: "lab.jawa.ahakeyconfig.bluetoothConnectionOwner")
        if storedOwner == nil || storedOwner == BluetoothConnectionOwner.agentDaemon.rawValue {
            suppressAutomaticConnection = true
        }
        usbTransport.onConnected = { [weak self] identity in
            Task { @MainActor in self?.usbDidConnect(identity) }
        }
        usbTransport.onDisconnected = { [weak self] in
            Task { @MainActor in self?.usbDidDisconnect() }
        }
        usbTransport.onFrame = { [weak self] data in
            Task { @MainActor in self?.handleUSBFrame(data) }
        }
        usbTransport.onError = { [weak self] error in
            Task { @MainActor in
                self?.appendLog("USB HID: \(error.localizedDescription)", isError: true)
            }
        }
        // WBS-5.5：Agent 独占时 Studio 连 USB transport 也不启动
        if !suppressAutomaticConnection {
            usbTransport.start()
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

    var isUSBAttached: Bool { usbDeviceIdentity != nil }

    var isUSBConfigurationActive: Bool {
        selectedConfigurationRoute(forceBLE: false) == .usb
    }

    var configurationTransportLabel: String {
        if isUSBConfigurationActive { return NSLocalizedString("USB 有线（BLE 备用）", comment: "") }
        if isUSBAttached, protocolMode != .current {
            return NSLocalizedString("BLE（USB 等待 current 协议）", comment: "")
        }
        if isUSBAttached, protocolMode == .current {
            return NSLocalizedString("BLE（USB 设备身份未匹配）", comment: "")
        }
        return NSLocalizedString("BLE", comment: "")
    }

    private var configurationSessionOwned: Bool {
        !suppressAutomaticConnection && connectionLock.holdsLock && isConnected
    }

    private func selectedConfigurationRoute(forceBLE: Bool) -> AhaKeyConfigurationTransportRoute {
        AhaKeyConfigurationTransportSelector.route(
            AhaKeyConfigurationTransportContext(
                protocolMode: protocolMode,
                usbAttached: usbTransport.isConnected,
                configurationSessionOwned: configurationSessionOwned,
                usbDeviceIdentifier: usbDeviceIdentity?.shortIdentifier,
                negotiatedDeviceIdentifier: deviceIdentifier,
                forceBLE: forceBLE
            )
        )
    }

    private func usbDidConnect(_ identity: AhaKeyUSBDeviceIdentity) {
        usbDeviceIdentity = identity
        let gate = protocolMode == .current
            ? NSLocalizedString("等待 App 取得配置会话", comment: "")
            : NSLocalizedString("等待 BLE 协商 current 协议", comment: "")
        appendLog("检测到 USB HID \(identity.transportDescription)，\(gate)", category: .lifecycle)
    }

    private func usbDidDisconnect() {
        guard usbDeviceIdentity != nil else { return }
        usbDeviceIdentity = nil
        appendLog(NSLocalizedString("USB HID 有线配置通道已断开，配置写入回退 BLE", comment: ""), category: .lifecycle)
    }

    private func handleUSBFrame(_ data: Data) {
        guard selectedConfigurationRoute(forceBLE: false) == .usb else {
            appendLog("忽略未获 current 配置权限的 USB 应答: \(data.hexString)", category: .verbose)
            return
        }
        if let response = AhaKeyResponseParser.parseCommandResponse(data),
           bleFallbackCommands.contains(response.cmd) {
            appendLog("忽略 USB 迟到应答 0x\(String(format: "%02X", response.cmd))", category: .verbose)
            return
        }
        appendLog("← USB: \(data.hexString)", category: .verbose)
        parseProtocolResponse(data)
    }

    // MARK: - Public API

    func refreshBluetoothAuthorization() {
        bluetoothPermissionGranted = Self.currentBluetoothAuthorizationGranted()
        bluetoothPoweredOn = central?.state == .poweredOn
        if !bluetoothPermissionGranted {
            bleConnectionStatus = NSLocalizedString("蓝牙权限未开启", comment: "")
        } else if central?.state == .poweredOff {
            bleConnectionStatus = NSLocalizedString("蓝牙关闭", comment: "")
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
        reconnectBackoff.reset()
        connectAutomatically()
    }

    /// 与 `AgentManager` 的蓝牙占用方一致：交给 Agent 时为 true，交回本 App 时为 false。
    func setSuppressedForAgentOwningKeyboard(_ suppress: Bool) {
        suppressAutomaticConnection = suppress
        if suppress {
            // 切给 Agent：释放跨进程连接锁，Agent 方可获取；USB HID 也停止占用
            connectionLock.release()
            didLogConnectionLockBusy = false
            usbTransport.stop()
        } else {
            // 切回本 App（用户显式操作）：退避重置回 4s，尽快重连；恢复 USB transport
            reconnectBackoff.reset()
            usbTransport.start()
        }
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
        guard !suppressAutomaticConnection else { return }
        guard central?.state == .poweredOn else {
            pendingConnect = true
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
                bleConnectionStatus = NSLocalizedString("连接中…", comment: "")
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
            bleConnectionStatus = NSLocalizedString("连接中…", comment: "")
            return
        }

        // 3. 扫描
        startScan()
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
        bleConnectionStatus = NSLocalizedString("扫描中…", comment: "")
        appendLog(NSLocalizedString("开始扫描 AhaKey 设备…", comment: ""))
        central?.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Double(10) * 1_000_000_000))
            if self.isScanning {
                self.central?.stopScan()
                self.isScanning = false
                self.bleConnectionStatus = NSLocalizedString("等待设备", comment: "")
                self.appendLog(NSLocalizedString("扫描超时，继续后台轮询设备", comment: ""))
            }
        }
    }

    func disconnect() {
        guard let peripheral else { return }
        central?.cancelPeripheralConnection(peripheral)
        appendLog(NSLocalizedString("用户主动断开", comment: ""), category: .lifecycle)
    }

    /// 发送原始命令到 0x7343（带队列，防止连发过载）
    @discardableResult
    func writeCommand(_ data: Data, forceBLE: Bool = false) -> AhaKeyConfigurationTransportRoute? {
        if selectedConfigurationRoute(forceBLE: forceBLE) == .usb {
            do {
                try usbTransport.sendCommand(data)
                appendLog("→ USB CMD \(data.count)B: \(data.hexString)", category: .verbose)
                return .usb
            } catch {
                appendLog("USB 命令发送失败，回退 BLE：\(error.localizedDescription)", isError: true)
            }
        }
        guard let commandChar, let peripheral else {
            appendLog(NSLocalizedString("命令通道未就绪", comment: ""), isError: true)
            return nil
        }
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: commandChar, type: writeType)
        appendLog("→ CMD \(data.count)B: \(data.hexString)", category: .verbose)
        return .ble
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
        guard let peripheral, let dataChar, commandChar != nil else {
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

        let usesSessionUpload = taskPictureProtocolPlan?.usesSessionUpload == true
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
                        prepare = AhaKeyCommand.prepareWrite(chunkLength: chunk.data.count, address: address)
                        expectedCommand = AhaKeyCommand.cmdPrepareWrite
                    }
                    _ = try await sendCommandAwaitingResponse(
                        prepare,
                        expectedCommand: expectedCommand,
                        forceBLE: forceBLEPictureTransfer
                    )

                    let usedUSB = selectedConfigurationRoute(forceBLE: forceBLEPictureTransfer) == .usb
                    do {
                        try await writeDataChunk(chunk.data, to: peripheral, characteristic: dataChar, type: writeType)
                        currentUploadSessionID = nil
                        break
                    } catch {
                        guard shouldRetryPictureChunkOverBLE(
                            after: error,
                            usedUSB: usedUSB,
                            usesSessionUpload: usesSessionUpload,
                            chunkAttempt: chunkAttempt
                        ) else {
                            throw error
                        }
                        forceBLEPictureTransfer = true
                        if let sessionID = currentUploadSessionID {
                            _ = try await sendCommandAwaitingResponse(
                                AhaKeyCommand.abortPictureWrite(sessionID: sessionID),
                                expectedCommand: AhaKeyCommand.cmdAbortPictureWrite,
                                timeoutSeconds: 2.0,
                                forceBLE: true
                            )
                        }
                        currentUploadSessionID = nil
                        appendLog("当前图片数据块 USB 传输失败，已回滚会话并改用 BLE 重写", isError: true)
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
            if taskPictureProtocolPlan?.finishesRawUpload == true {
                let finishCommand = AhaKeyCommand.finishTaskPictureWrite()
                appendLog("→ finishTaskPictureWrite mode=\(mode) startIndex=\(startIndex) hex=\(finishCommand.hexString)", category: .verbose)
                _ = try await sendCommandAwaitingResponse(
                    finishCommand,
                    expectedCommand: AhaKeyCommand.cmdFinishTaskPicWrite,
                    forceBLE: forceBLEPictureTransfer
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
            appendLog("→ updatePicture mode=\(mode) startIndex=\(startIndex) frameCount=\(frames.count) delayMs=\(delay) hex=\(updateCommand.hexString)", category: .verbose)
            _ = try await sendCommandAwaitingResponse(
                updateCommand,
                expectedCommand: AhaKeyCommand.cmdUpdatePic,
                forceBLE: forceBLEPictureTransfer
            )
        }
        uploadFinished = true
        appendLog("LCD 上传完成: \(frames.count) 帧, start=\(startIndex)")
    }

    private func shouldRetryPictureChunkOverBLE(
        after error: Error,
        usedUSB: Bool,
        usesSessionUpload: Bool,
        chunkAttempt: Int
    ) -> Bool {
        guard usedUSB, usesSessionUpload, chunkAttempt == 1 else { return false }
        if error is AhaKeyUSBTransportError { return true }
        if case OLEDUploadError.timeout(let command) = error {
            return command == AhaKeyCommand.cmdWriteResult
        }
        return false
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
        appendLog(NSLocalizedString("保存配置到设备…", comment: ""))
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

    private func taskPictureUpdate(
        plan: AhaKeyTaskPictureProtocolPlan,
        mode: UInt8,
        set: UInt8,
        state: UInt8,
        startIndex: UInt16,
        frameCount: UInt16,
        timeDelayMs: UInt16
    ) -> (data: Data, expectedCommand: UInt8) {
        switch plan.metadataFormat {
        case .legacySingleSet:
            return (
                AhaKeyCommand.updateTaskPicture(mode: mode, state: state, startIndex: startIndex, frameCount: frameCount, timeDelayMs: timeDelayMs),
                AhaKeyCommand.cmdUpdateTaskPic
            )
        case .currentSetAware:
            return (
                AhaKeyCommand.updateTaskPictureSet(mode: mode, set: set, state: state, startIndex: startIndex, frameCount: frameCount, timeDelayMs: timeDelayMs),
                AhaKeyCommand.cmdUpdateTaskPicSet
            )
        }
    }

    private func taskPictureRead(
        plan: AhaKeyTaskPictureProtocolPlan,
        mode: UInt8,
        set: UInt8,
        state: UInt8
    ) -> (data: Data, expectedCommand: UInt8) {
        switch plan.metadataFormat {
        case .legacySingleSet:
            return (AhaKeyCommand.readTaskPictureState(mode: mode, state: state), AhaKeyCommand.cmdReadTaskPicState)
        case .currentSetAware:
            return (AhaKeyCommand.readTaskPictureSet(mode: mode, set: set, state: state), AhaKeyCommand.cmdReadTaskPicSet)
        }
    }

    private func parseTaskPictureResponse(
        _ payload: Data,
        plan: AhaKeyTaskPictureProtocolPlan
    ) -> AhaKeyTaskPictureState? {
        switch plan.metadataFormat {
        case .legacySingleSet: return AhaKeyResponseParser.parseTaskPictureStateResponse(payload)
        case .currentSetAware: return AhaKeyResponseParser.parseTaskPictureSetResponse(payload)
        }
    }

    /// 复用已验证的 0x80 数据帧写入，然后把写入区间绑定到任务图槽位。
    /// 任务图资源不能使用 0x82：该命令会替换普通每模式动画绑定。
    func uploadTaskOLEDFrames(_ frames: [Data], fps: Int, mode: UInt8, set: UInt8, state: UInt8, startIndex: UInt16) async throws {
        guard let plan = taskPictureProtocolPlan,
              plan.setIndices.contains(Int(set)), plan.states.contains(where: { $0.rawValue == Int(state) }) else {
            throw OLEDUploadError.unsupportedFirmwareProtocol
        }
        let delay = UInt16(max(1, 1000 / max(1, fps)))
        let maxAttempts = 3
        var lastError: Error?
        forceBLEPictureTransfer = false
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
                let metadata = taskPictureUpdate(
                    plan: plan, mode: mode, set: set, state: state, startIndex: startIndex,
                    frameCount: UInt16(frames.count), timeDelayMs: delay
                )
                _ = try await sendCommandAwaitingResponse(
                    metadata.data,
                    expectedCommand: metadata.expectedCommand,
                    forceBLE: forceBLEPictureTransfer
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
                switch error {
                case .cancelled, .connectionLost, .noFrames, .tooManyFrames, .invalidEncodedFrameSize,
                     .channelNotReady, .noAvailablePictureSlot, .unsupportedFirmwareProtocol:
                    throw error
                default:
                    lastError = error
                }
            } catch is CancellationError {
                throw OLEDUploadError.cancelled
            }
            if attempt < maxAttempts {
                appendLog("任务图写入第 \(attempt) 次失败，重试中…（mode\(mode) 套图\(set) 状态\(state)）", isError: true)
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
                if Task.isCancelled { throw OLEDUploadError.cancelled }
            }
        }
        throw lastError ?? OLEDUploadError.taskPictureMetadataMismatch
    }

    func clearTaskPicture(mode: UInt8, set: UInt8, state: UInt8) async throws {
        guard let plan = taskPictureProtocolPlan,
              plan.setIndices.contains(Int(set)), plan.states.contains(where: { $0.rawValue == Int(state) }) else {
            throw OLEDUploadError.unsupportedFirmwareProtocol
        }
        let metadata = taskPictureUpdate(
            plan: plan, mode: mode, set: set, state: state,
            startIndex: 0, frameCount: 0, timeDelayMs: 0
        )
        _ = try await sendCommandAwaitingResponse(metadata.data, expectedCommand: metadata.expectedCommand)
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
        guard let plan = taskPictureProtocolPlan,
              plan.setIndices.contains(Int(set)), plan.states.contains(where: { $0.rawValue == Int(state) }) else {
            throw OLEDUploadError.unsupportedFirmwareProtocol
        }
        let read = taskPictureRead(plan: plan, mode: mode, set: set, state: state)
        let response = try await sendCommandAwaitingResponse(read.data, expectedCommand: read.expectedCommand)
        let parsed = parseTaskPictureResponse(response.payload, plan: plan)
        guard let picture = parsed else {
            throw OLEDUploadError.invalidTaskPictureStatePayload
        }
        keyboardTaskPictureStates[KeyboardTaskPictureSlot(mode: picture.mode, set: picture.set, state: picture.state)] = picture
        apply(.activePictureSet(mode: picture.mode, set: picture.activeSet))
        return picture
    }

    func readAllTaskPictureStates() async throws -> [AhaKeyTaskPictureState] {
        guard let plan = taskPictureProtocolPlan else {
            throw OLEDUploadError.unsupportedFirmwareProtocol
        }
        var result: [AhaKeyTaskPictureState] = []
        var failedReads = 0
        for mode in 0 ..< AhaKeyCommand.oledModeCount {
            for set in plan.setIndices {
                for state in plan.states {
                    do {
                        result.append(try await readTaskPictureState(mode: UInt8(mode), set: UInt8(set), state: UInt8(state.rawValue)))
                    } catch OLEDUploadError.cancelled {
                        throw OLEDUploadError.cancelled
                    } catch OLEDUploadError.connectionLost {
                        throw OLEDUploadError.connectionLost
                    } catch {
                        failedReads += 1
                        appendLog("槽位状态读取失败（mode\(mode) 套图\(set) 状态\(state)），按空槽处理：\(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
        if result.isEmpty, failedReads > 0 {
            throw OLEDUploadError.invalidTaskPictureStatePayload
        }
        return result
    }

    func setActiveTaskPictureSet(mode: UInt8, set: UInt8) async throws {
        guard let plan = taskPictureProtocolPlan,
              plan.supportsActiveSet, plan.setIndices.contains(Int(set)) else {
            throw OLEDUploadError.unsupportedFirmwareProtocol
        }
        let response = try await sendCommandAwaitingResponse(
            AhaKeyCommand.setActiveTaskPictureSet(mode: mode, set: set),
            expectedCommand: AhaKeyCommand.cmdSetActiveTaskPicSet
        )
        guard response.payload.count >= 2 else { throw OLEDUploadError.invalidTaskPictureStatePayload }
        apply(.activePictureSet(mode: Int(response.payload[0]), set: Int(response.payload[1])))
    }

    /// 把已写入 flash 的帧区间绑定为某 mode 的默认动画（0x82）。
    /// 固件会把它同步到该 mode 各套图的 IDLE 任务槽：模式切换后的待机画面即此动画。
    /// 只改绑定、不写 flash 数据区，因此对同一区间重复调用是安全的。
    func bindDefaultPicture(mode: UInt8, startIndex: UInt16, frameCount: UInt16, timeDelayMs: UInt16) async throws {
        _ = try await sendCommandAwaitingResponse(
            AhaKeyCommand.updatePicture(mode: mode, startIndex: startIndex, frameCount: frameCount, timeDelayMs: timeDelayMs),
            expectedCommand: AhaKeyCommand.cmdUpdatePic
        )
        keyboardPictureStates[Int(mode)] = KeyboardPictureState(
            startIndex: Int(startIndex),
            frameCount: Int(frameCount),
            frameIntervalMs: Int(timeDelayMs),
            totalCapacity: keyboardPictureStates[Int(mode)]?.totalCapacity ?? 0
        )
    }

    func saveConfigAwaitingResponse() async throws {
        _ = try await sendCommandAwaitingResponse(AhaKeyCommand.saveConfig(), expectedCommand: AhaKeyCommand.cmdSaveConfig)
    }

    /// 同步 IDE 状态到键盘 LED
    func updateIDEState(_ state: IDEState) {
        guard commandChar != nil else { return }
        let cmd = AhaKeyCommand.updateState(state)
        writeCommand(cmd)
    }

    /// 最新固件中 0x91 已改为灯效预览；虚拟拨杆只保留软件覆盖，不再向键盘发送旧 0x91。
    /// value: 0=auto/up, 1=manual/down, 2=mid
    func setSwitchStateViaBLE(_ value: UInt8) {
        appendLog("虚拟拨杆 sw_state=\(value) 仅作为软件覆盖；最新固件 0x91 用于灯效预览。")
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

    func cancelOLEDUpload() {
        if let sessionID = currentUploadSessionID {
            writeCommand(AhaKeyCommand.abortPictureWrite(sessionID: sessionID))
            currentUploadSessionID = nil
        }
        finishDataWrite(.failure(OLEDUploadError.cancelled))
        for command in Array(protocolResponseWaiters.keys) {
            finishProtocolWaiter(command, result: .failure(OLEDUploadError.cancelled))
        }
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
        if routing.entersPersistentLog, let data = line.data(using: .utf8) {
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

    private var ideStateDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
    }

    private var ideStateFileURL: URL {
        ideStateDirectoryURL.appendingPathComponent("current-ide-state.json")
    }

    /// Agent 通常以临时文件 + rename 的方式更新状态，因此监听目录而不是单个文件。
    /// 仅在真实文件变化时解析 JSON；一次性 timer 在 30s/120s 的准确过期点刷新状态。
    private func startIDEStateMonitoring() {
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
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: ideStateMonitorQueue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleIDEStateRefresh()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        ideStateDirectoryMonitor = source
        source.resume()
    }

    private func stopIDEStateMonitoring() {
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

    /// 主动触发一次共享文件读取（用户点击虚拟拨杆后立即调用，避免等下一次定时 poll）
    func refreshAgentStateFromFileNow() {
        pollIDEStateFile()
    }

    /// 点击虚拟拨杆瞬间的乐观更新值。已迁入 `CoreDeviceSnapshot.pendingSwitchOverride`（阶段 5），
    /// 旧属性名保留为只读计算属性，UI 消费点零改动。
    var optimisticSwitchOverride: Int? { coreSnapshot.pendingSwitchOverride }

    /// pending 确认超时任务（3s ≈ 两个轮询周期）。确认到达即取消；超时派发 reducer 事件回退。
    private var switchOverrideTimeoutTask: Task<Void, Never>?

    func applyOptimisticSwitchOverride(_ value: UInt8) {
        apply(.userSetSwitch(Int(value)))
        switchOverrideTimeoutTask?.cancel()
        switchOverrideTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.apply(.switchOverrideTimeout)
        }
    }

    private func clearOptimisticSwitchOverrideIfMatched() {
        guard let opt = coreSnapshot.pendingSwitchOverride else { return }
        // Agent 共享文件轮询确认：值对齐才清除；BLE 轮询回包的一致性确认在 reducer fullStatus 分支内完成。
        if agentSwitchState == opt {
            apply(.switchOverrideConfirmed(opt))
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
        clearOptimisticSwitchOverrideIfMatched()
    }

    /// 所有 AhaKey 主服务特征就绪后触发（仅一次）
    private func onAllCharacteristicsReady() {
        guard !didQueryAfterConnect else { return }
        didQueryAfterConnect = true
        appendLog(NSLocalizedString("所有特征就绪，查询设备状态", comment: ""))
        queryDeviceStatus()
        negotiateFirmwareCapabilities()
        queryAllPictureStates()
    }

    /// 连接后协商入口：延迟 200ms 让首帧状态回包先行，再做 0x99 能力查询（与 Rhino 顺序一致）。
    private func negotiateFirmwareCapabilities() {
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.queryFirmwareCapabilities()
        }
    }

    /// 0x99 固件能力协商：最多重试 maxAttempts 次；
    /// 成功按 protocolVersion 定 mode，全失败按 firmwareMainVersion 回退 legacy / restrictedUnknown。
    /// 结果经 `.capabilitiesNegotiated` 事件进入快照投影（protocolMode → 核心投影，能力帧 → 诊断投影）。
    private func queryFirmwareCapabilities() async {
        var lastFailure = NSLocalizedString("设备未返回能力帧", comment: "")
        for attempt in 1 ... AhaKeyProtocolNegotiation.maxAttempts {
            do {
                let response = try await sendCommandAwaitingResponse(
                    AhaKeyCommand.queryCapabilities(),
                    expectedCommand: AhaKeyCommand.cmdCapabilities,
                    timeoutSeconds: AhaKeyProtocolNegotiation.attemptTimeoutSeconds
                )
                guard let capabilities = AhaKeyFirmwareCapabilities.parse(response.payload) else {
                    lastFailure = NSLocalizedString("能力帧长度或字段无效", comment: "")
                    continue
                }
                let mode = AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities)
                apply(.capabilitiesNegotiated(mode: mode, capabilities: capabilities))
                appendLog(
                    "协议 v\(capabilities.protocolVersion)，\(capabilities.modeCount) modes，"
                        + "\(capabilities.stateCount) states，BLE packet \(capabilities.maxPacketSize)B"
                )
                return
            } catch {
                lastFailure = error.localizedDescription
            }
            if AhaKeyProtocolNegotiation.shouldRetry(afterFailedAttempt: attempt) {
                appendLog("能力查询第 \(attempt) 次失败，正在重试：\(lastFailure)", isError: true)
                try? await Task.sleep(nanoseconds: AhaKeyProtocolNegotiation.retryDelayNanoseconds)
            }
        }

        let supportsLegacyTaskPictures = firmwareMainVersion == 1
            ? await probeLegacyTaskPictureSupport()
            : false
        let fallback = AhaKeyProtocolNegotiation.fallbackMode(
            firmwareMainVersion: firmwareMainVersion,
            supportsLegacyTaskPictures: supportsLegacyTaskPictures
        )
        apply(.capabilitiesNegotiated(mode: fallback, capabilities: nil))
        switch fallback {
        case .legacy:
            appendLog("连续三次能力查询失败；0x94 实探成功，按支持任务 GIF 的旧版固件兼容：\(lastFailure)", isError: true)
        case .legacyBaseOnly:
            appendLog("固件 1.x 未实现任务 GIF 命令（0x94 返回空载荷或无响应）；保留键位与灯效配置，停用任务图写入。", isError: true)
        default:
            appendLog("连续三次无法识别固件协议，进入受限兼容模式：\(lastFailure)", isError: true)
        }
    }

    /// 早期 1.x 固件会对未知命令返回 `AA BB <cmd> 00 CC DD`，不能仅凭 status=0 判断支持。
    /// 只有 0x94 返回完整且与请求一致的元数据，才启用 legacy 任务图上传。
    private func probeLegacyTaskPictureSupport() async -> Bool {
        do {
            let response = try await sendCommandAwaitingResponse(
                AhaKeyCommand.readTaskPictureState(mode: 0, state: UInt8(AhaKeyTaskDisplayState.working.rawValue)),
                expectedCommand: AhaKeyCommand.cmdReadTaskPicState,
                timeoutSeconds: 1.0
            )
            guard let picture = AhaKeyResponseParser.parseTaskPictureStateResponse(response.payload) else {
                appendLog("旧固件 0x94 实探返回 \(response.payload.count)B 载荷，不支持任务 GIF。", isError: true)
                return false
            }
            return picture.mode == 0 && picture.state == AhaKeyTaskDisplayState.working.rawValue
        } catch {
            appendLog("旧固件 0x94 实探失败：\(error.localizedDescription)", isError: true)
            return false
        }
    }

    /// 顺序查询每个 mode 的 0x83 图片元信息，结果累积到 keyboardPictureStates
    private func queryAllPictureStates() {
        Task { [weak self] in
            guard let self else { return }
            for slot in 0..<4 {
                do {
                    let state = try await self.readPictureState(mode: UInt8(slot))
                    self.keyboardPictureStates[slot] = KeyboardPictureState(
                        startIndex: state.startIndex,
                        frameCount: state.picLength,
                        frameIntervalMs: state.frameInterval,
                        totalCapacity: state.allModeMaxPic
                    )
                    self.appendLog("  mode\(slot) flash: 帧数=\(state.picLength) 间隔=\(state.frameInterval)ms")
                } catch {
                    self.appendLog("  mode\(slot) 图片状态查询失败: \(error)", isError: true)
                }
            }
        }
    }

    private func sendCommandAwaitingResponse(
        _ data: Data,
        expectedCommand: UInt8,
        timeoutSeconds: Double = 5.0,
        forceBLE: Bool = false
    ) async throws -> CommandResponse {
        let attemptedUSB = selectedConfigurationRoute(forceBLE: forceBLE) == .usb
        do {
            return try await sendCommandAwaitingResponseOnce(
                data,
                expectedCommand: expectedCommand,
                timeoutSeconds: timeoutSeconds,
                forceBLE: forceBLE
            )
        } catch OLEDUploadError.timeout
            where attemptedUSB && !forceBLE && peripheral != nil && commandChar != nil {
            if expectedCommand == AhaKeyCommand.cmdPrepareWrite ||
                expectedCommand == AhaKeyCommand.cmdPrepareSessionWrite {
                forceBLEPictureTransfer = true
            }
            appendLog(
                "USB 命令 0x\(String(format: "%02X", expectedCommand)) 响应超时，回退 BLE 重试",
                isError: true
            )
            bleFallbackCommands.insert(expectedCommand)
            defer { bleFallbackCommands.remove(expectedCommand) }
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
        if Task.isCancelled { throw OLEDUploadError.cancelled }
        let result = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResponse, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: OLEDUploadError.cancelled)
                    return
                }
                if protocolResponseWaiters[expectedCommand] != nil {
                    finishProtocolWaiter(expectedCommand, result: .failure(OLEDUploadError.cancelled))
                }
                protocolResponseWaiters[expectedCommand] = continuation
                protocolResponseTimeoutTasks[expectedCommand]?.cancel()
                protocolResponseTimeoutTasks[expectedCommand] = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Double(timeoutSeconds) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.finishProtocolWaiter(
                        expectedCommand,
                        result: .failure(OLEDUploadError.timeout(command: expectedCommand))
                    )
                }
                writeCommand(data, forceBLE: forceBLE)
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finishProtocolWaiter(expectedCommand, result: .failure(OLEDUploadError.cancelled))
            }
        })
            guard result.status == 0 else {
                throw OLEDUploadError.deviceRejected(command: expectedCommand, status: result.status)
            }
            return result
    }

    private func finishProtocolWaiter(_ command: UInt8, result: Result<CommandResponse, Error>) {
        guard let continuation = protocolResponseWaiters.removeValue(forKey: command) else { return }
        protocolResponseTimeoutTasks.removeValue(forKey: command)?.cancel()
        continuation.resume(with: result)
    }

    private func writeDataChunk(
        _ data: Data,
        to peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType,
        timeoutSeconds: Double = 5.0
    ) async throws {
        if Task.isCancelled { throw OLEDUploadError.cancelled }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: OLEDUploadError.cancelled)
                    return
                }
                dataWriteResultContinuation = continuation
                let usesUSB = selectedConfigurationRoute(forceBLE: forceBLEPictureTransfer) == .usb

                dataWriteTimeoutTask?.cancel()
                dataWriteTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Double(timeoutSeconds) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    if usesUSB {
                        self?.forceBLEPictureTransfer = true
                        self?.appendLog("USB 图片数据确认超时，当前上传后续重试改走 BLE", isError: true)
                    }
                    self?.finishDataWrite(.failure(OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult)))
                }
                if usesUSB {
                    dataPacketWriteTask?.cancel()
                    dataPacketWriteTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            try await self.usbTransport.sendData(data)
                            self.appendLog("→ USB DATA \(data.count)B", category: .verbose)
                        } catch is CancellationError {
                            return
                        } catch {
                            self.forceBLEPictureTransfer = true
                            self.appendLog("USB DATA 发送失败，等待回滚 session：\(error.localizedDescription)", isError: true)
                            self.finishDataWrite(.failure(error))
                        }
                    }
                } else {
                    startBLEDataWrite(data, to: peripheral, characteristic: characteristic, type: type)
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finishDataWrite(.failure(OLEDUploadError.cancelled))
            }
        })
    }

    private func startBLEDataWrite(
        _ data: Data,
        to peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType
    ) {
        let negotiatedLength = max(1, peripheral.maximumWriteValueLength(for: type))
        let sessionID = currentUploadSessionID
        let minimumPacketLength = sessionID == nil ? 1 : 3
        let firmwareLimit = max(
            minimumPacketLength,
            firmwareCapabilities?.maxPacketSize ?? AhaKeyCommand.oledPacketSize
        )
        let maxPacketLength = min(negotiatedLength, firmwareLimit)
        let packets = AhaKeyPictureDataPacketizer.packets(
            for: data,
            maxPacketLength: maxPacketLength,
            sessionID: sessionID
        )
        let payloadLength = max(1, maxPacketLength - (sessionID == nil ? 0 : 2))
        appendLog("→ BLE DATA \(data.count)B, 分片 \(payloadLength)B (协商上限 \(negotiatedLength)B)", category: .verbose)
        dataPacketWriteTask?.cancel()
        dataPacketWriteTask = Task { @MainActor in
            for packet in packets {
                guard !Task.isCancelled else { return }
                peripheral.writeValue(packet, for: characteristic, type: type)
                try? await Task.sleep(nanoseconds: UInt64(12) * 1_000_000)
            }
        }
    }

    private func finishDataWrite(_ result: Result<Void, Error>) {
        guard let continuation = dataWriteResultContinuation else { return }
        dataWriteResultContinuation = nil
        dataWriteTimeoutTask?.cancel()
        dataWriteTimeoutTask = nil
        dataPacketWriteTask?.cancel()
        dataPacketWriteTask = nil
        continuation.resume(with: result)
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
                title: NSLocalizedString("拨杆 → 自动批准", comment: ""),
                body: NSLocalizedString("Kimi：若已安装 AhaKey Kimi Hooks，自动档会直接接管当前会话批准；若刚装完或刚升级 kimi-cli，请先重开一次 kimi。Claude/Cursor/Codex 仍走各自钩子。", comment: ""),
                identifier: "lab.jawa.ahakey.switch.auto",
                isCritical: true
            )
        } else if switchedToManual {
            postNotification(
                title: NSLocalizedString("拨杆 → 手动批准", comment: ""),
                body: NSLocalizedString("Claude / Cursor / Codex：按各自确认链。Kimi：若已安装 AhaKey Kimi Hooks，手动档会直接把当前会话拉回手动批准。", comment: ""),
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
        alert.addButton(withTitle: NSLocalizedString("知道了", comment: ""))
        alert.runModal()
    }
}

enum OLEDUploadError: LocalizedError {
    case channelNotReady
    case noFrames
    case tooManyFrames(max: Int)
    case invalidEncodedFrameSize
    case unsupportedFirmwareProtocol
    case noAvailablePictureSlot(needed: Int, max: Int)
    case timeout(command: UInt8)
    case deviceRejected(command: UInt8, status: UInt8)
    case invalidPictureStatePayload
    case defaultPictureMetadataMismatch
    case invalidTaskPictureStatePayload
    case taskPictureMetadataMismatch
    case cancelled
    case connectionLost

    var errorDescription: String? {
        switch self {
        case .channelNotReady:
            return NSLocalizedString("BLE 数据通道还没准备好。", comment: "")
        case .noFrames:
            return NSLocalizedString("没有可上传的图片帧。", comment: "")
        case .tooManyFrames(let max):
            return String(format: NSLocalizedString("帧数超过设备上限，最多支持 %d 帧。", comment: ""), max)
        case .invalidEncodedFrameSize:
            return NSLocalizedString("图片帧编码尺寸无效；每帧必须是 160×80 RGB565。", comment: "")
        case .unsupportedFirmwareProtocol:
            return NSLocalizedString("当前固件协议不支持这项任务图操作。", comment: "")
        case .noAvailablePictureSlot(let needed, let max):
            return String(format: NSLocalizedString("动画需要 %d 帧，但设备当前没有足够连续空间。总容量上限约为 %d 帧。", comment: ""), needed, max)
        case .timeout(let command):
            return String(format: NSLocalizedString("等待设备响应超时: 0x%02X", comment: ""), command)
        case .deviceRejected(let command, let status):
            return String(format: NSLocalizedString("设备拒绝了命令 0x%02X，状态码 0x%02X", comment: ""), command, status)
        case .invalidPictureStatePayload:
            return NSLocalizedString("设备返回的动画槽位信息无法解析。", comment: "")
        case .defaultPictureMetadataMismatch:
            return NSLocalizedString("设备未保存刚写入的默认图片槽位；未标记为已同步，请重试。", comment: "")
        case .invalidTaskPictureStatePayload:
            return NSLocalizedString("设备返回的任务动画槽位信息无法解析；请确认键盘已烧录任务 GIF 固件。", comment: "")
        case .taskPictureMetadataMismatch:
            return NSLocalizedString("设备没有保存对应状态的任务动画槽位信息；请更新到支持任务图的固件后重试。", comment: "")
        case .cancelled:
            return NSLocalizedString("图片写入已取消。已完成的图片会保留，未完成的图片可稍后继续写入。", comment: "")
        case .connectionLost:
            return NSLocalizedString("键盘连接已中断，当前图片写入已停止。请重连后继续。", comment: "")
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
                self.appendLog(NSLocalizedString("蓝牙已关闭", comment: ""), isError: true)
                self.bleConnectionStatus = NSLocalizedString("蓝牙关闭", comment: "")
            case .unauthorized:
                self.refreshBluetoothAuthorization()
                self.appendLog(NSLocalizedString("蓝牙权限未开启", comment: ""), isError: true)
                self.bleConnectionStatus = NSLocalizedString("蓝牙权限未开启", comment: "")
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
        // 新固件广播在 manufacturer data 里带 4 位设备编号；
        // 旧固件没有，回退取 BLE 名后缀（"AhaKey 515C" → 515C），再不行连接后读序列号
        let advertisedIdentifier = AhaKeyDevicePresentation.advertisedIdentifier(
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        ) ?? AhaKeyDevicePresentation.nameSuffixIdentifier(name)

        Task { @MainActor in
            if let advertisedIdentifier {
                self.apply(.deviceIdentity(identifier: advertisedIdentifier, serialNumber: nil))
            }
            self.appendLog("发现设备: \(AhaKeyDevicePresentation.diagnosticLabel(identifier: advertisedIdentifier ?? "—")) RSSI=\(RSSI)")
            // 扫到目标设备广播：退避重置回 4s 并立即连接
            self.reconnectBackoff.reset()
            self.central?.stopScan()
            self.isScanning = false
            self.peripheral = peripheral
            peripheral.delegate = self
            self.central?.connect(peripheral, options: nil)
            self.bleConnectionStatus = NSLocalizedString("连接中…", comment: "")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.apply(.connected(name: peripheral.name, uuid: peripheral.identifier.uuidString))
            self.lastPeripheralUUID = peripheral.identifier
            self.bleConnectionStatus = NSLocalizedString("已连接", comment: "")
            self.appendLog("已连接: \(peripheral.name ?? "?") UUID=\(peripheral.identifier.uuidString)", category: .lifecycle)
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
            self.bleConnectionStatus = NSLocalizedString("连接失败", comment: "")
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
            // 不清 peripheral 和 lastPeripheralUUID——用于直连重试
            self.peripheral = nil
            self.writeQueue.removeAll()
            self.isWriting = false
            self.writeBatches.removeAll()
            self.didQueryAfterConnect = false
            self.keyboardPictureStates.removeAll()
            self.keyboardTaskPictureStates.removeAll()
            self.stopRSSIPolling()
            self.stopStatusPolling()
            self.startAutoReconnectPolling()
            self.appendLog("已断开: \(error?.localizedDescription ?? "正常")", category: .lifecycle)

            // 2 秒后自动重连
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Double(2) * 1_000_000_000))
                if !self.isConnected {
                    self.appendLog(NSLocalizedString("尝试自动重连…", comment: ""))
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
                        [Self.firmwareRevisionCharUUID, Self.modelNumberCharUUID, Self.serialNumberCharUUID],
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
                    self.appendLog(NSLocalizedString("数据特征(0x7341) 已订阅通知", comment: ""))
                case Self.commandCharUUID:
                    self.commandChar = char
                    self.commandCharReady = true
                    self.appendLog(NSLocalizedString("命令特征(0x7343) 就绪", comment: ""))
                case Self.notifyCharUUID:
                    self.notifyChar = char
                    self.notifyCharReady = true
                    peripheral.setNotifyValue(true, for: char)
                    self.appendLog(NSLocalizedString("通知特征(0x7344) 已订阅", comment: ""))
                case Self.infoCharUUID:
                    self.appendLog(NSLocalizedString("设备信息(0x7342) 就绪", comment: ""))

                // 标准 Battery Level
                case Self.batteryLevelCharUUID:
                    self.batteryLevelChar = char
                    peripheral.readValue(for: char)
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                    self.appendLog(NSLocalizedString("电池特征(0x2A19) 读取中", comment: ""))

                // 标准 Device Information
                case Self.firmwareRevisionCharUUID:
                    peripheral.readValue(for: char)
                case Self.modelNumberCharUUID:
                    peripheral.readValue(for: char)
                case Self.serialNumberCharUUID:
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
            self.apply(.rssi(RSSI.intValue))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
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
        case Self.serialNumberCharUUID:
            if let str = String(data: data, encoding: .utf8) {
                let serial = str.uppercased()
                // 旧固件 4 位序列号即设备编号；新格式 "AHX1-<uid>" 由 UID 提取
                let identifier = serial.count == 4 ? serial : AhaKeyDevicePresentation.shortIdentifier(from: serial)
                apply(.deviceIdentity(identifier: identifier, serialNumber: serial))
                appendLog("← 设备身份: \(AhaKeyDevicePresentation.diagnosticLabel(identifier: deviceIdentifier, serialNumber: serial))", category: .verbose)
            }
        default:
            appendLog("← 未知(\(uuid)): \(hex)")
        }
    }

    private func parseProtocolResponse(_ data: Data) {
        if let status = AhaKeyResponseParser.parseDeviceStatus(data) {
            // 唯一归并入口：workMode 真实变化时由 apply 内部发一次 ahaKeyKeyboardWorkModeChanged。
            apply(.fullStatus(
                battery: status.battery,
                firmwareMain: status.firmwareMain,
                firmwareSub: status.firmwareSub,
                workMode: status.workMode,
                lightMode: status.lightMode,
                switchState: status.switchState,
                brightness: status.brightness,
                activePictureSet: status.activePictureSet
            ))
            appendLog("  状态: 电量=\(status.battery) 固件=\(status.firmwareMain).\(status.firmwareSub) 模式=\(status.workMode) 灯=\(status.lightMode) 开关=\(status.switchState) 亮度=\(status.brightness) 任务套图=\(status.activePictureSet)", category: .verbose)
        } else if AhaKeyResponseParser.isProtocolFrame(data) {
            if let response = AhaKeyResponseParser.parseCommandResponse(data) {
                finishProtocolWaiter(response.cmd, result: .success((response.status, response.payload)))

                if response.cmd == AhaKeyCommand.cmdWriteResult {
                    if let expectedSession = currentUploadSessionID {
                        guard response.payload.count >= 2 else {
                            appendLog("忽略缺少 session 的图片写入确认", isError: true)
                            return
                        }
                        let responseSession = UInt16(response.payload[0]) | (UInt16(response.payload[1]) << 8)
                        guard responseSession == expectedSession else {
                            appendLog("忽略过期图片确认 session=\(responseSession)，当前=\(expectedSession)", isError: true)
                            return
                        }
                    }
                    if response.status == 0 {
                        finishDataWrite(.success(()))
                    } else {
                        finishDataWrite(.failure(OLEDUploadError.deviceRejected(command: response.cmd, status: response.status)))
                    }
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
            appendLog(NSLocalizedString("命令通道未就绪", comment: ""), isError: true)
            return
        }
        appendLog(NSLocalizedString("═══ 开始探测 ═══", comment: ""))

        let probes: [(String, Data)] = [
            (NSLocalizedString("设备状态查询", comment: ""), AhaKeyCommand.queryDeviceStatus()),
            (NSLocalizedString("读配置 0x01", comment: ""), Data([0xAA, 0xBB, 0x01, 0xCC, 0xDD])),
            (NSLocalizedString("读配置 0x03", comment: ""), Data([0xAA, 0xBB, 0x03, 0xCC, 0xDD])),
            (NSLocalizedString("读配置 0x05", comment: ""), Data([0xAA, 0xBB, 0x05, 0xCC, 0xDD])),
        ]
        for (label, data) in probes {
            appendLog("→ \(label): \(data.hexString)", category: .verbose)
            writeCommand(data)
        }

        if let batteryLevelChar {
            peripheral?.readValue(for: batteryLevelChar)
            appendLog(NSLocalizedString("→ 重读电池电量", comment: ""))
        }

        appendLog(NSLocalizedString("═══ 探测完毕，等待回调 ═══", comment: ""))
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
