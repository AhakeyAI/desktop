import AhaKeyConfigShared
import Combine
import Darwin
import Foundation
import UserNotifications

extension NSNotification.Name {
    /// workMode 真实变化（userInfo["workMode"] = Int）。原定义在 AhaKeyBLEManager，BLE 退场后迁到 Runtime store 边界。
    static let ahaKeyKeyboardWorkModeChanged = NSNotification.Name("ahaKeyKeyboardWorkModeChanged")
}

// MARK: - WBS 5.7 切片 3：Studio Runtime store（视图唯一事实源入口）
//
// 包装 `AhaKeyStudioRuntimeFacade`：把 view-state 流转成 @Published 派生属性供 SwiftUI 观察。
// 原则：
// - 设备事实（连接/协议/电量/模式/拨杆/任务图套图/固件版本）全部从 Runtime snapshot 派生，本地不复制；
// - 保存路径只走 facade.apply（ingestResources → apply），进度由 snapshot.operations 驱动；
// - Studio 不再扫描/连接/写设备：BLE/USB 由 Runtime 进程独占；
// - Runtime 共享文件（current-ide-state.json）的观察与 BLE 无关，原样迁移到本 store；
// - 诊断日志保留在 BLELogStore（仅 Studio 侧事件，不含设备 TX/RX）。

/// 从 Runtime view state 派生的设备展示投影。纯值类型，方便 reducer 级单测。
struct AhaKeyStudioDevicePresentation: Equatable {
    var isConnected: Bool = false
    /// 协议已就绪、可提交配置（旧 `commandCharReady && protocolMode == .current` 的 Runtime 对应物）。
    var isConfigurationReady: Bool = false
    var protocolMode: AhaKeyProtocolMode = .negotiating
    var deviceName: String? = nil
    /// Runtime 设备稳定 ID（同步基线 namespace 用）。
    var deviceKey: String? = nil
    var batteryLevel: Int = 0
    var workMode: Int = 0
    var lightMode: Int = 0
    /// 拨杆：up=0（自动批准）/down=1（手动批准）；设备尚未上报时保持 nil 语义见 `currentConnectionSwitchState`。
    var switchState: Int = 0
    var hasReportedSwitchState: Bool = false
    var brightness: Int = 35
    var firmwareVersion: String? = nil
    var activeTaskPictureSets: [Int: Int] = [:]
    var preferredTransport: AhaKeyRuntimeTransport = .none
    var usbAttached: Bool = false
    var configurationRevision: AhaKeyConfigurationRevision = .init(0)
    var activeDeviceID: AhaKeyRuntimeDeviceID? = nil

    /// 与旧 `currentConnectionSwitchState` 对齐：仅在连接且设备已上报真实档位后提供。
    var currentConnectionSwitchState: Int? {
        isConnected && hasReportedSwitchState ? switchState : nil
    }

    var allowsTaskPictureConfiguration: Bool {
        protocolMode.allowsTaskPictureConfiguration
    }

    /// 任务图协议计划：Runtime 侧能力协商细节不随快照下发，current 协议按完整能力处理。
    var taskPictureProtocolPlan: AhaKeyTaskPictureProtocolPlan? {
        AhaKeyTaskPictureProtocolPlan.make(mode: protocolMode, capabilities: nil)
    }

    var supportedTaskDisplayStates: [AhaKeyTaskDisplayState] {
        taskPictureProtocolPlan?.states ?? []
    }

    var isUSBConfigurationActive: Bool {
        usbAttached && preferredTransport == .usb
    }

    var configurationTransportLabel: String {
        if isUSBConfigurationActive {
            return NSLocalizedString("USB 有线（current 协议）", comment: "")
        }
        if isConnected {
            return NSLocalizedString("蓝牙 BLE", comment: "")
        }
        return NSLocalizedString("未连接", comment: "")
    }

    /// v0.2 OLED/resource 与协商无关；视图用此关闭图片编辑并展示延后原因。
    var releaseFeatureProjection: AhaKeyReleaseFeatureProjection {
        AhaKeyReleaseFeaturePolicy.current.projection(.negotiating)
    }
}

/// 纯派生函数：Runtime view state → 设备展示投影。视图与单测共用同一入口。
enum AhaKeyStudioRuntimeDerivation {
    /// C3A：page-operation 只读投影，不含 UI 锁或续传按钮。
    static func pageOperationProjection(
        package: AhaKeyConfigurationPackage,
        queue: AhaKeyRuntimeDeviceQueue
    ) -> AhaKeyRuntimePageOperationProjection? {
        AhaKeyRuntimePageOperationProjection(package: package, queue: queue)
    }

    static func presentation(
        for viewState: AhaKeyStudioRuntimeViewState
    ) -> AhaKeyStudioDevicePresentation {
        var presentation = AhaKeyStudioDevicePresentation()
        guard viewState.connection == .online || viewState.connection == .resyncing,
              let snapshot = viewState.snapshot else {
            return presentation
        }
        presentation.configurationRevision = snapshot.configurationRevision
        presentation.activeDeviceID = snapshot.activeDeviceID
        guard let activeID = snapshot.activeDeviceID,
              let device = snapshot.devices.first(where: { $0.id == activeID }) else {
            return presentation
        }
        presentation.deviceKey = activeID.rawValue
        presentation.deviceName = device.displayName
        presentation.usbAttached = device.usbAttached
        presentation.preferredTransport = device.preferredTransport
        presentation.isConnected = device.bluetoothConnected || device.usbAttached
        presentation.protocolMode = protocolMode(for: device.protocolState)
        presentation.isConfigurationReady = presentation.isConnected && device.protocolState == .currentReady

        let state = device.state
        if let battery = state.batteryLevel { presentation.batteryLevel = Int(battery.rawValue) }
        if let workMode = state.workMode { presentation.workMode = Int(workMode.rawValue) }
        if let lightMode = state.lightMode { presentation.lightMode = Int(lightMode.rawValue) }
        if let lever = state.leverPosition, let mapped = switchState(for: lever) {
            presentation.switchState = mapped
            presentation.hasReportedSwitchState = true
        }
        if let brightness = state.brightness { presentation.brightness = Int(brightness.rawValue) }
        presentation.firmwareVersion = state.firmwareVersion
        presentation.activeTaskPictureSets = state.activeTaskPictureSets.reduce(into: [:]) { result, pair in
            result[Int(pair.key.rawValue)] = Int(pair.value.rawValue)
        }
        return presentation
    }

    static func protocolMode(for state: AhaKeyRuntimeDeviceProtocolState) -> AhaKeyProtocolMode {
        switch state {
        case .currentReady: return .current
        case .legacyDenied: return .legacyBaseOnly
        case .restricted, .failed: return .restrictedUnknown
        case .probing, .disconnected: return .negotiating
        }
    }

    /// Runtime 拨杆位置 → 旧 switchState 语义（0=自动批准，1=手动批准）。
    /// middle 无对应旧值，保守按手动处理。
    static func switchState(for position: AhaKeyRuntimeLeverPosition) -> Int? {
        switch position {
        case .up: return 0
        case .middle, .down: return 1
        }
    }
}

/// Studio 侧 Runtime store：视图观察它，而不是任何 BLE 对象。
@MainActor
final class AhaKeyStudioRuntimeClient: ObservableObject {
    /// facade 发布的最近一次视图状态（含 snapshot 与事件游标）。
    @Published private(set) var viewState = AhaKeyStudioRuntimeViewState()
    /// 由 viewState 派生的设备投影（reducer 级纯函数，见 `AhaKeyStudioRuntimeDerivation`）。
    @Published private(set) var presentation = AhaKeyStudioDevicePresentation()

    // MARK: - Runtime 共享文件状态（与 BLE 无关，自 BLEManager 原样迁移）

    /// 由 ahakeyconfig-agent 写入的当前 IDE hook 状态值（IDEState.rawValue），画布 LED 实时还原用。
    @Published private(set) var liveIDEStateValue: Int?
    /// Runtime 端 BLE 轮询缓存的 lightMode/switchState/workMode（Studio 不直连设备时经共享文件对齐）。
    @Published private(set) var runtimeLightMode: Int?
    @Published private(set) var runtimeSwitchState: Int?
    @Published private(set) var runtimeWorkMode: Int?
    /// 用户点虚拟拨杆后的乐观值；Runtime 共享文件回读一致后确认清除，3s 超时回退。
    @Published private(set) var optimisticSwitchOverride: Int?

    /// Studio 侧诊断日志（仅诊断窗口展示；不含任何设备 TX/RX——那是 Runtime 的边界）。
    let logStore = BLELogStore()

    /// 后台服务活性判定由 RuntimeServiceManager 注入（socket status 心跳为准）。
    var runtimeBLEConnectedProvider: () -> Bool = { false }

    private let facade: AhaKeyStudioRuntimeFacade
    private var followTask: Task<Void, Never>?
    private var switchOverrideTimeoutTask: Task<Void, Never>?
    private var lastPostedWorkMode: Int?

    init(facade: AhaKeyStudioRuntimeFacade) {
        self.facade = facade
    }

    // MARK: - 生命周期（跟随 app active/退出；stop 不影响 Runtime 已受理 operation）

    /// 启动 facade 跟随并订阅 view-state 流（幂等）。
    func connect() {
        guard followTask == nil else { return }
        followTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.facade.start()
            let stream = await self.facade.viewStates()
            for await state in stream {
                guard !Task.isCancelled else { return }
                self.applyViewState(state)
            }
        }
        startIDEStateMonitoring()
    }

    /// 停止跟随并发布 offline；不取消 Runtime 已受理的 operation。
    func disconnect() {
        followTask?.cancel()
        followTask = nil
        Task { await facade.stop() }
        viewState = AhaKeyStudioRuntimeViewState()
        presentation = AhaKeyStudioDevicePresentation()
        stopIDEStateMonitoring()
    }

    private func applyViewState(_ state: AhaKeyStudioRuntimeViewState) {
        viewState = state
        let next = AhaKeyStudioRuntimeDerivation.presentation(for: state)
        if next != presentation {
            let oldWorkMode = presentation.workMode
            let wasConnected = presentation.isConnected
            presentation = next
            if next.isConnected, wasConnected, next.workMode != oldWorkMode {
                NotificationCenter.default.post(
                    name: .ahaKeyKeyboardWorkModeChanged,
                    object: nil,
                    userInfo: ["workMode": next.workMode]
                )
            }
        }
    }

    // MARK: - 便捷派生（视图读取入口；全部来自 presentation / viewState，无本地复制）

    var connectionState: AhaKeyStudioRuntimeConnectionState { viewState.connection }
    var isOnline: Bool { viewState.connection == .online || viewState.connection == .resyncing }
    var runtimeSnapshot: AhaKeyRuntimeSnapshot? { viewState.snapshot }
    var activeDevice: AhaKeyRuntimeDeviceSnapshot? {
        guard let snapshot = viewState.snapshot,
              let activeID = snapshot.activeDeviceID else { return nil }
        return snapshot.devices.first { $0.id == activeID }
    }
    var lastError: String? { viewState.lastError }

    var isConnected: Bool { presentation.isConnected }
    var isConfigurationReady: Bool { presentation.isConfigurationReady }
    var protocolMode: AhaKeyProtocolMode { presentation.protocolMode }
    var deviceName: String? { presentation.deviceName }
    var deviceKey: String? { presentation.deviceKey }
    var batteryLevel: Int { presentation.batteryLevel }
    var workMode: Int { presentation.workMode }
    var lightMode: Int { presentation.lightMode }
    var switchState: Int { presentation.switchState }
    var currentConnectionSwitchState: Int? { presentation.currentConnectionSwitchState }
    var brightness: Int { presentation.brightness }
    var firmwareVersion: String? { presentation.firmwareVersion }
    var activeTaskPictureSets: [Int: Int] { presentation.activeTaskPictureSets }
    var allowsTaskPictureConfiguration: Bool { presentation.allowsTaskPictureConfiguration }
    var taskPictureProtocolPlan: AhaKeyTaskPictureProtocolPlan? { presentation.taskPictureProtocolPlan }
    var supportedTaskDisplayStates: [AhaKeyTaskDisplayState] { presentation.supportedTaskDisplayStates }
    var isUSBConfigurationActive: Bool { presentation.isUSBConfigurationActive }
    var configurationTransportLabel: String { presentation.configurationTransportLabel }
    var releaseFeatureProjection: AhaKeyReleaseFeatureProjection { presentation.releaseFeatureProjection }

    /// 最近一次 apply 受理的 operation 进度（来自 Runtime snapshot.operations，事实源在 Runtime）。
    var lastApplyOperation: AhaKeyRuntimeOperationSummary? {
        guard let operationID = viewState.lastApplyOperationID else { return nil }
        return viewState.snapshot?.operations.first { $0.id == operationID }
    }

    // MARK: - 保存路径（唯一写入口：draft → facade.apply；取消 → requestCancellation）

    /// 提交当前编辑模式：必须显式 scope；空范围 fail-closed，不扫描其它模式草稿。
    func applyDraft(
        _ draft: AhaKeyStudioDraft,
        scope: AhaKeyStudioApplyScope
    ) async throws -> AhaKeyRuntimeOperationID {
        guard isOnline, let snapshot = viewState.snapshot else {
            throw AhaKeyStudioStoreApplyError.runtimeOffline
        }
        guard let targetDeviceID = snapshot.activeDeviceID else {
            throw AhaKeyStudioStoreApplyError.noActiveDevice
        }
        guard let rawSlot = scope.modeSlot,
              let modeSlot = AhaKeyModeSlot(rawValue: Int(rawSlot)) else {
            throw AhaKeyStudioStoreApplyError.emptyApplyScope
        }
        return try await facade.apply(
            modes: [draft.draft(for: modeSlot).packageInput()],
            scope: scope,
            targetDeviceID: targetDeviceID,
            baseRevision: snapshot.configurationRevision
        )
    }

    /// 使用点击写入时冻结的模式快照提交，避免长上传期间的后续编辑进入包内。
    func applyDraft(_ submission: AhaKeyStudioSubmittedWrite) async throws -> AhaKeyRuntimeOperationID {
        try await applyDraft(AhaKeyStudioDraft(modes: [submission.modeDraft]), scope: submission.scope)
    }

    /// 成功写入后只把已提交模式的已写入面合并进同步基线。
    /// `includeOLED == false` 时保留旧 OLED 基线，避免把未下发的图片草稿记成已同步。
    nonisolated static func mergingSubmittedMode(
        _ submitted: AhaKeyModeDraft,
        into baseline: AhaKeyStudioDraft,
        includeOLED: Bool
    ) -> AhaKeyStudioDraft {
        var merged = submitted
        if !includeOLED {
            merged.oled = baseline.draft(for: submitted.mode).oled
        }
        var next = baseline
        next.updateMode(merged)
        return next
    }

    /// 取消已受理的 operation（透传 facade）。
    func requestCancellation(
        of operationID: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimeCancellationDisposition {
        try await facade.requestCancellation(operationID)
    }

    /// 取消最近一次 apply 受理的 operation；无在途 operation 时返回 nil。
    @discardableResult
    func cancelLastApply() async throws -> AhaKeyRuntimeCancellationDisposition? {
        guard let operationID = viewState.lastApplyOperationID else { return nil }
        return try await facade.requestCancellation(operationID)
    }

    /// 直接提交已组装的配置包（测试/诊断用；生产视图请走 `applyDraft`）。
    func apply(_ package: AhaKeyConfigurationPackage) async throws -> AhaKeyRuntimeOperationID {
        try await facade.apply(package)
    }

    // MARK: - 诊断日志（Studio 侧事件；设备协议日志归 Runtime 诊断边界）

    func appendCommLogLine(_ message: String, isError: Bool = false) {
        logStore.append(BLELogEntry(timestamp: Date(), message: message, isError: isError))
    }

    // MARK: - 虚拟拨杆乐观覆盖（软件覆盖经 Runtime socket，与 BLE 无关）

    func applyOptimisticSwitchOverride(_ value: UInt8) {
        optimisticSwitchOverride = Int(value)
        switchOverrideTimeoutTask?.cancel()
        switchOverrideTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.optimisticSwitchOverride != nil {
                self.optimisticSwitchOverride = nil
                self.appendCommLogLine(
                    NSLocalizedString("虚拟拨杆切换未在 3s 内收到确认，已回退到最后确认值", comment: ""),
                    isError: true
                )
            }
        }
    }

    /// 主动触发一次共享文件读取（用户点击虚拟拨杆后立即调用，避免等下一次定时 poll）。
    func refreshRuntimeStateFromFileNow() {
        pollIDEStateFile()
    }

    private func clearOptimisticSwitchOverrideIfMatched() {
        guard let opt = optimisticSwitchOverride else { return }
        // Runtime 共享文件轮询确认：值对齐才清除；Runtime 快照回包的一致性由 presentation 对齐负责。
        if runtimeSwitchState == opt || (presentation.isConnected && presentation.currentConnectionSwitchState == opt) {
            optimisticSwitchOverride = nil
            switchOverrideTimeoutTask?.cancel()
            switchOverrideTimeoutTask = nil
        }
    }

    // MARK: - Runtime IDE 状态共享文件观察（目录监听 + 过期调度 + 兼容回退轮询）

    private var ideStateDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
    }

    private var ideStateFileURL: URL {
        ideStateDirectoryURL.appendingPathComponent("current-ide-state.json")
    }

    private let ideStateMonitorQueue = DispatchQueue(label: "lab.jawa.ahakeyconfig.studio.ide-state")
    private var ideStateDirectoryMonitor: DispatchSourceFileSystemObject?
    private var ideStateRefreshTask: Task<Void, Never>?
    private var ideStateExpiryTimer: Timer?
    private var ideStateFallbackTimer: Timer?

    /// Runtime 通常以临时文件 + rename 的方式更新状态，因此监听目录而不是单个文件。
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

    private func pollIDEStateFile() {
        guard let data = try? Data(contentsOf: ideStateFileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            scheduleIDEStateExpiry(at: nil)
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
            if runtimeLightMode != nil { runtimeLightMode = nil }
            if runtimeSwitchState != nil { runtimeSwitchState = nil }
            if runtimeWorkMode != nil { runtimeWorkMode = nil }
            return
        }
        let now = Date().timeIntervalSince1970
        var expiryDeadlines: [TimeInterval] = []
        // stateValue 是瞬时态（hook 触发的事件时间戳），30s 过期；超时则置空，固件 LED 也会回到无 state 默认。
        // 注意它故意仍按内容里的 stateTs 判断，不随 mtime：Runtime 的 30s touch 会刷新 mtime，
        // 若按 mtime 判断，瞬时态会被 Runtime 保活永不落空。
        if let value = obj["stateValue"] as? Int,
           let stateTs = (obj["stateTs"] as? Double) ?? (obj["ts"] as? Double),
           now < stateTs + 30 {
            if liveIDEStateValue != value { liveIDEStateValue = value }
            expiryDeadlines.append(stateTs + 30)
        } else {
            if liveIDEStateValue != nil { liveIDEStateValue = nil }
        }
        // lightMode/switchState/workMode 来自 Runtime 的 BLE 轮询。过期判断统一按文件 mtime 语义：
        // mtime = 「状态最后确认时间」（Runtime 无变化时每 30s touch 一次）。
        // Runtime 活性以 socket status 心跳为准：Runtime 持有 BLE 连接时不因文件老化作废，120s 后复查；
        // Runtime 不在/未连接时按 mtime 超过 120s 过期清理。
        let fileMtime = ((try? FileManager.default.attributesOfItem(atPath: ideStateFileURL.path))?[.modificationDate] as? Date)?.timeIntervalSince1970
        let runtimeStateFresh: Bool
        if runtimeBLEConnectedProvider() {
            runtimeStateFresh = true
            expiryDeadlines.append(now + 120)
        } else if let mtime = fileMtime, now < mtime + 120 {
            runtimeStateFresh = true
            expiryDeadlines.append(mtime + 120)
        } else {
            runtimeStateFresh = false
        }
        if runtimeStateFresh {
            let lightMode = obj["lightMode"] as? Int
            let switchState = obj["switchState"] as? Int
            let workMode = obj["workMode"] as? Int
            if runtimeLightMode != lightMode { runtimeLightMode = lightMode }
            if runtimeSwitchState != switchState { runtimeSwitchState = switchState }
            if runtimeWorkMode != workMode { runtimeWorkMode = workMode }
        } else {
            if runtimeLightMode != nil { runtimeLightMode = nil }
            if runtimeSwitchState != nil { runtimeSwitchState = nil }
            if runtimeWorkMode != nil { runtimeWorkMode = nil }
        }
        scheduleIDEStateExpiry(at: expiryDeadlines.min())
        clearOptimisticSwitchOverrideIfMatched()
    }
}

/// v0.2 关闭 OLED 面时，dirty 与成功基线都不得把未写入图片当已同步。
enum AhaKeyStudioDraftDirtyPolicy {
    static func includeOLEDSurface(_ projection: AhaKeyReleaseFeatureProjection) -> Bool {
        projection.showsOLEDInspector
    }

    static func unsyncedCount(
        current: AhaKeyStudioDraft,
        baseline: AhaKeyStudioDraft,
        includeOLED: Bool,
        oledIsDirty: (AhaKeyOLEDDraft, AhaKeyOLEDDraft) -> Bool
    ) -> Int {
        AhaKeyModeSlot.allCases.reduce(into: 0) { count, mode in
            let currentMode = current.draft(for: mode)
            let baselineMode = baseline.draft(for: mode)
            for role in AhaKeyKeyRole.allCases where currentMode.key(for: role) != baselineMode.key(for: role) {
                count += 1
            }
            if includeOLED, oledIsDirty(currentMode.oled, baselineMode.oled) {
                count += 1
            }
            if currentMode.lightBar != baselineMode.lightBar {
                count += 1
            }
        }
    }
}

/// 点击「写入键盘」瞬间冻结的当前模式。apply 与成功 baseline 只使用这份快照。
struct AhaKeyStudioSubmittedWrite: Equatable {
    let modeSlot: AhaKeyModeSlot
    let modeDraft: AhaKeyModeDraft

    var scope: AhaKeyStudioApplyScope {
        AhaKeyStudioApplyScope(modeSlot: UInt8(modeSlot.rawValue))
    }

    static func capturing(selectedMode: AhaKeyModeSlot, draft: AhaKeyStudioDraft) -> AhaKeyStudioSubmittedWrite {
        AhaKeyStudioSubmittedWrite(
            modeSlot: selectedMode,
            modeDraft: draft.draft(for: selectedMode)
        )
    }

    func merging(into baseline: AhaKeyStudioDraft, includeOLED: Bool) -> AhaKeyStudioDraft {
        AhaKeyStudioRuntimeStore.mergingSubmittedMode(modeDraft, into: baseline, includeOLED: includeOLED)
    }
}

/// 任务卡命名别名：store 即 client（并行测试引用 `AhaKeyStudioRuntimeClient`）。
typealias AhaKeyStudioRuntimeStore = AhaKeyStudioRuntimeClient

/// store 保存路径错误。
enum AhaKeyStudioStoreApplyError: LocalizedError {
    /// Runtime 离线（未握手/重连中）。
    case runtimeOffline
    /// Runtime 快照中没有活动设备。
    case noActiveDevice
    /// 未显式给出当前编辑模式。
    case emptyApplyScope

    var errorDescription: String? {
        switch self {
        case .runtimeOffline:
            return NSLocalizedString("AhaKey Runtime 离线：请确认后台服务已安装并运行后重试。", comment: "")
        case .noActiveDevice:
            return NSLocalizedString("尚未识别到键盘：请确认 AhaKey Runtime 已连接设备后重试。", comment: "")
        case .emptyApplyScope:
            return NSLocalizedString("未指定当前编辑模式，拒绝把其它模式的草稿一并提交。", comment: "")
        }
    }
}

// MARK: - 拨杆档位变更通知（自 BLEManager 迁移；数据源换成 Runtime store）

final class SwitchStateNotifier: ObservableObject {
    static let shared = SwitchStateNotifier()

    private weak var store: AhaKeyStudioRuntimeClient?
    private var switchStateCancellable: AnyCancellable?
    private var runtimeSwitchStateCancellable: AnyCancellable?
    private var lastObservedState: Int?
    private var lastNotificationAt: Date?
    private var hasInitialState = false
    private var hasRequestedAuthorization = false

    private init() {}

    @MainActor
    func bind(to store: AhaKeyStudioRuntimeClient) {
        if self.store === store, switchStateCancellable != nil, runtimeSwitchStateCancellable != nil { return }

        self.store = store
        lastObservedState = nil
        hasInitialState = false
        // Runtime 快照拨杆（Studio 未直连时也可能有值；事实源在 Runtime）
        switchStateCancellable = store.$presentation
            .map(\.currentConnectionSwitchState)
            .removeDuplicates()
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
        runtimeSwitchStateCancellable = store.$runtimeSwitchState
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
            center.add(request, withCompletionHandler: nil)
            _ = self
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized:
                deliver()
            case .notDetermined:
                Task { @MainActor in
                    guard !self.hasRequestedAuthorization else { return }
                    self.hasRequestedAuthorization = true
                }
                center.requestAuthorization(options: [.alert, .sound, .criticalAlert]) { granted, _ in
                    if granted { deliver() }
                }
            default:
                break
            }
        }
    }
}

enum AhaKeyStudioWriteProgressText {
    static func status(for operation: AhaKeyRuntimeOperationSummary, elapsedSeconds: Int) -> String {
        if let completed = operation.completedBytes, let total = operation.totalBytes, total > 0 {
            let percent = Int(min(100, (Double(completed) * 100.0) / Double(total)))
            return String(
                format: NSLocalizedString("Runtime 正在上传图片资源（%llu/%llu 字节，%d%%）…", comment: ""),
                completed, total, percent
            )
        }
        let format = operation.completedSteps == 0
            ? NSLocalizedString("Runtime 正在上传图片资源（%u/%u，已用 %d 秒）…", comment: "")
            : NSLocalizedString("Runtime 正在写入设备（%u/%u，已用 %d 秒）…", comment: "")
        return String(format: format, operation.completedSteps, operation.totalSteps, elapsedSeconds)
    }
}

enum AhaKeyStudioFailureText {
    static func message(for operation: AhaKeyRuntimeOperationSummary) -> String {
        let detail = detail(for: operation)
        switch operation.state {
        case .failedWithoutWrites:
            return String(
                format: NSLocalizedString("Runtime 写入失败（%@），未提交任何改动。", comment: ""),
                detail
            )
        default:
            return String(
                format: NSLocalizedString("部分完成：Runtime 报告部分步骤未写入（%@）。可再次点击写入重试。", comment: ""),
                detail
            )
        }
    }

    static func detail(for operation: AhaKeyRuntimeOperationSummary) -> String {
        if let context = operation.failureContext, !context.isEmpty {
            return structuredDetail(context)
        }
        if let code = operation.messageCode {
            return localizedCategory(code)
        }
        return "—"
    }

    private static func structuredDetail(_ context: AhaKeyRuntimeOperationFailureContext) -> String {
        if let step = context.failedStepID, let opcode = context.opcode, let status = context.deviceStatus {
            return String(
                format: NSLocalizedString("步骤 %@，命令 0x%02X，status=%u", comment: ""),
                step.rawValue, opcode, status
            )
        }
        var parts: [String] = []
        if let step = context.failedStepID {
            parts.append(String(format: NSLocalizedString("步骤 %@", comment: ""), step.rawValue))
        }
        if let opcode = context.opcode {
            parts.append(String(format: NSLocalizedString("命令 0x%02X", comment: ""), opcode))
        }
        if let status = context.deviceStatus {
            parts.append(String(format: NSLocalizedString("status=%u", comment: ""), status))
        }
        return parts.joined(separator: "，")
    }

    private static func localizedCategory(_ code: AhaKeyRuntimeEventCode) -> String {
        switch code.rawValue {
        case AhaKeyRuntimeEventCode.configurationDeviceRejected.rawValue:
            return NSLocalizedString("设备拒绝了配置命令", comment: "")
        case AhaKeyRuntimeEventCode.configurationCommandTimeout.rawValue:
            return NSLocalizedString("配置命令超时", comment: "")
        case AhaKeyRuntimeEventCode.configurationDisconnected.rawValue:
            return NSLocalizedString("设备连接已断开", comment: "")
        case AhaKeyRuntimeEventCode.configurationResourceMissing.rawValue:
            return NSLocalizedString("资源缺失或无法读取", comment: "")
        case AhaKeyRuntimeEventCode.configurationEncodingFailed.rawValue:
            return NSLocalizedString("图片编码失败", comment: "")
        case AhaKeyRuntimeEventCode.configurationPlanRejected.rawValue:
            return NSLocalizedString("配置方案无法执行", comment: "")
        case AhaKeyRuntimeEventCode.configurationMalformedFrame.rawValue:
            return NSLocalizedString("配置命令格式错误", comment: "")
        default:
            return code.rawValue
        }
    }
}
