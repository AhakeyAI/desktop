import Combine
import CoreBluetooth
import Foundation
import os.log
import AhaKeyConfigShared

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig.agent", category: "BLE")

/// 设备 8 字节状态解析结果。
///
/// 与 Sources/BLE/AhaKeyProtocol.swift 的 `AhaKeyDeviceStatus` 保持同构；
/// Agent 是独立 target，不共享源码，所以这里内联一份极简解析器。
struct AgentDeviceStatus {
    let battery: Int
    let signal: Int
    let firmwareMain: Int
    let firmwareSub: Int
    let workMode: Int
    let lightMode: Int
    let switchState: Int
}

/// 轻量 BLE 守护进程：维持连接 + 接收 Unix socket 命令 → 发送 LED 状态 / 回传拨杆状态
final class AhaKeyAgent: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// 兼容默认策略：保持现有生产行为（AI Hook + 动态灯效开启），
    /// 其余模块按策略显式启停。随策略化装配成熟后可改为全部关闭。
    public static let compatibleDefaultPolicy: AhaKeyRuntimePolicy = {
        var policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.claude, .cursor, .codex, .kimi]
        policy.devicePresentation.ledEnabled = true
        return policy
    }()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var lastUUID: UUID?
    private let serviceUUID = CBUUID(string: "7340")
    private let commandCharUUID = CBUUID(string: "7343")
    private let notifyCharUUID = CBUUID(string: "7344")
    private let deviceNamePrefix = "AhaKey"
    private let socketPath: String

    private let header: [UInt8] = [0xAA, 0xBB]
    private let trailer: [UInt8] = [0xCC, 0xDD]

    // MARK: 缓存（供 hook 查询使用）
    /// 最新 switchState（0=auto, 1=manual），未知时 nil
    private(set) var cachedSwitchState: UInt8?
    /// 最新 lightMode
    private(set) var cachedLightMode: UInt8?
    /// 用户刚点击画布虚拟拨杆时的短暂模拟值。它只用于等待设备下一次真实状态回包，
    /// 真实硬件状态一到就立即清除，不能覆盖物理拨杆。
    private(set) var userSwitchOverride: UInt8?

    private static let switchOverrideDefaultsKey = "lab.jawa.ahakeyconfig.agent.userSwitchOverride"

    /// 等待下一次 status 回包的回调队列（用于 querySwitchState）
    private var statusWaiters: [(AgentDeviceStatus?) -> Void] = []
    /// 工具完成 / 用户提交等短暂态的自动回落。
    private var pendingStateReset: DispatchWorkItem?
    /// 固件不会在拨杆变动时主动通知，因此 Agent 占用蓝牙时也必须轮询真实状态。
    private var statusPollTimer: DispatchSourceTimer?
    /// 共享文件写前去重（阶段 4）：相同快照不重复落盘，30s 无任何写入时仅 touch mtime。
    private var liveStateCoalescer = LiveStateWriteCoalescer()

    // MARK: 看门狗（CLI 崩溃/退出或 Codex PostToolUse 后缺少 Stop 时兜底归位；长工具执行不归位）
    /// 最近一次 hook 发来状态命令的时间（nil = 尚未收到）
    private var lastHookStateAt: Date?
    /// 最近一次我们主动发给键盘的 LED 状态
    private var lastSentState: UInt8 = 0
    private var watchdogTimer: DispatchSourceTimer?

    // MARK: 合盖运行
    private let powerProtection = PowerProtectionManager()
    private let processDetector = ProcessDetector(pollInterval: 5.0)
    /// 当前是否有 hook 发来的活跃状态（与 processDetector 独立）
    private var hookActivityActive = false

    // MARK: Runtime 编排（WBS 5.3 切片 3：防休眠作为 RuntimeModule 接入，行为不变）
    private let runtimeModuleRegistry = RuntimeModuleRegistry()
    private let orchestrator: RuntimeOrchestrator
    private var powerProtectionModule: PowerProtectionRuntimeModule?
    /// 切片 4：AI 集成（Hook 状态链看门狗 + 进程兜底即时检测）
    private var aiIntegrationModule: AIIntegrationRuntimeModule?
    /// 切片 5：动态灯效发送能力门控（sendState 与状态仍留 Agent）
    private var lightingModule: LightingRuntimeModule?
    /// 切片 6：AhaType 生命周期 seam（引擎实体仍在 Studio/Utilities，此处仅登记生命周期）
    private var ahaTypeModule: AhaTypeRuntimeModule?

    // MARK: - Hook Socket Server（HIL-RUNTIME-1-HOOK-SERVER）
    private var hookServer: AhaKeyRuntimeHookSocketServer?
    private let hookSocketURL: URL

    /// 各活跃态超时时长（秒）：
    ///   1=PermissionRequest / 7=UserPromptSubmit → 30s（等待阶段，手动停止后无 hook 跟进）
    ///   其余工具执行态 → 60s（工具可能运行较久，避免误触发）
    private func watchdogTimeout(for state: UInt8) -> Double {
        switch state {
        case 1, 7: return 30   // PermissionRequest / UserPromptSubmit：短超时
        default:   return 60   // PreToolUse / PostToolUse / SessionStart / TaskCompleted
        }
    }

    var onLog: ((String) -> Void)?

    init(
        socketPath: String = AhaKeyPaths.agentSocketPath,
        hookSocketURL: URL = AhaKeyPaths.runtimeHookSocketURL,
        initialPolicy: AhaKeyRuntimePolicy = AhaKeyAgent.compatibleDefaultPolicy
    ) {
        self.socketPath = socketPath
        self.hookSocketURL = hookSocketURL
        self.orchestrator = RuntimeOrchestrator(registry: runtimeModuleRegistry, initialPolicy: initialPolicy)
        // 旧版会持久化虚拟拨杆覆盖，导致真实硬件档位永远无法回写。迁移时清除它。
        UserDefaults.standard.removeObject(forKey: Self.switchOverrideDefaultsKey)
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        Self.clearLiveSwitchState()
        registerModules()
        Task {
            await orchestrator.updatePolicy(initialPolicy)
        }
    }

    /// 切片 6：AhaType seam 装配——仅登记生命周期；引擎实体（转写/优化器/HUD）
    /// 仍在 Studio 进程（Sources/Utilities，本卡禁改），策略桥接待 WBS 5.7。
    private func registerAhaTypeModule() {
        let module = AhaTypeRuntimeModule(
            onStart: { [weak self] in self?.emit("AhaType seam 已启动（引擎实体由 Studio 承载，策略桥接待 5.7）") },
            onStop: { [weak self] in self?.emit("AhaType seam 已停止") }
        )
        ahaTypeModule = module
        Task {
            await runtimeModuleRegistry.register(module)
        }
    }

    /// 切片 5：灯效模块装配——registry 注册（启动由 orchestrator 策略驱动）。
    private func registerLightingModule() {
        let module = LightingRuntimeModule()
        lightingModule = module
        Task {
            await runtimeModuleRegistry.register(module)
        }
    }

    func shutdown() {
        hookServer?.stop()
        hookServer = nil
        processDetector.stop()
        processDetector.stop()
        _ = powerProtection.deactivateAll()
        // 编排器侧同步清理（模块 stop 委托到 deactivate，与上面幂等重叠无害）
        Task { await runtimeModuleRegistry.stopAll() }
        lockRetryItem?.cancel()
        lockRetryItem = nil
        connectionLock.release()
    }

    private func registerPowerProtectionModule() {
        // 防休眠经 RuntimeModuleRegistry 编排（切片 3）：模块 start/stop 委托到
        // 原有 activate/deactivate 行为，策略化 gating 随 orchestrator 装配切片接入。
        let module = PowerProtectionRuntimeModule(
            onStart: { [weak self] in self?.activatePowerProtectionBehavior() },
            onStop: { [weak self] in self?.deactivatePowerProtectionBehavior() }
        )
        powerProtectionModule = module
        Task {
            await runtimeModuleRegistry.register(module)
        }
    }

    /// 注册所有 Runtime 模块到 Registry（只注册，不启动；启停由 orchestrator 策略驱动）。
    private func registerModules() {
        registerPowerProtectionModule()
        registerLightingModule()
        registerAhaTypeModule()
        registerAIIntegrationModule()
    }

    /// 切片 4：AI 集成模块注册（看门狗 + 进程兜底即时检测）。
    private func registerAIIntegrationModule() {
        let module = AIIntegrationRuntimeModule(
            onStart: { [weak self] in
                self?.startWatchdog()
                self?.processDetector.checkNow()
            },
            onStop: { [weak self] in
                self?.stopWatchdog()
            }
        )
        aiIntegrationModule = module
        Task {
            await runtimeModuleRegistry.register(module)
        }
    }

    /// 策略更新入口。外部（Studio XPC / CLI）通过此处驱动模块启停。
    func updatePolicy(_ policy: AhaKeyRuntimePolicy) async {
        await orchestrator.updatePolicy(policy)
    }

    /// 原 setupPowerProtection 的实际行为：启动时自清 + 进程兜底检测驱动防护。
    private func activatePowerProtectionBehavior() {
        // 启动时自清，防止上次崩溃遗留断言或虚拟显示器。
        _ = powerProtection.deactivateAll()

        // 进程兜底检测：只要目标 IDE/CLI 在跑，就保持防护。
        // 修复 F3：移除 .dropFirst()，避免订阅时目标已在运行导致 begin() 永不被调用。
        processDetector.$isAnyTargetRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.updatePowerProtectionFromProcessDetector(running: running)
            }
            .store(in: &cancellables)
        processDetector.start()
    }

    private func deactivatePowerProtectionBehavior() {
        processDetector.stop()
        _ = powerProtection.deactivateAll()
    }

    private var cancellables = Set<AnyCancellable>()

    private func updatePowerProtectionFromProcessDetector(running: Bool) {
        if running {
            powerProtection.begin(.aiCodingIdleProcess)
            powerProtection.begin(.aiCodingLidCloseProcess)
        } else {
            powerProtection.end(.aiCodingIdleProcess)
            powerProtection.end(.aiCodingLidCloseProcess)
        }
    }

    private func updatePowerProtectionFromHook(state: UInt8) {
        let activeStates: [UInt8] = [1, 2, 3, 4, 6, 7]
        let wasActive = hookActivityActive
        hookActivityActive = activeStates.contains(state)

        if hookActivityActive {
            powerProtection.begin(.aiCodingIdleHook)
            powerProtection.begin(.aiCodingLidCloseHook)
        } else if wasActive {
            powerProtection.end(.aiCodingIdleHook)
            powerProtection.end(.aiCodingLidCloseHook)
        }
    }

    /// 虚拟拨杆只在等待真实回包的短暂窗口内生效；随后一律使用键盘 GPIO 状态。
    var effectiveSwitchState: UInt8? {
        userSwitchOverride ?? cachedSwitchState
    }

    func setSwitchOverride(_ value: UInt8?) {
        userSwitchOverride = value
        scheduleUserSwitchOverrideTimeout()
        // 最新固件中 0x91 已用于灯效预览；拨杆只保留 hook 软件覆盖，不再向键盘发送旧 0x91。
        if let v = value {
            emit("拨杆 \(v) 仅作临时软件模拟，下一次真实状态回包会接管。")
        }
        // 把覆盖值写进共享文件，主 App 立刻看到画布拨杆位置更新（事件性写入：每次必写，
        // 但同步去重基准，避免下一次轮询回包因基准过期而误判变化）
        Self.writeLiveState(switchState: effectiveSwitchState)
        liveStateCoalescer.noteEventWrite(
            LiveStateWriteCoalescer.Snapshot(switchState: effectiveSwitchState.map { Int($0) }),
            at: Date().timeIntervalSince1970
        )
        emit("拨杆覆盖 = \(value.map { String($0) } ?? "清除")（effective=\(effectiveSwitchState.map { String($0) } ?? "未知")）")
    }

    /// 虚拟拨杆覆盖的确认超时任务（3s ≈ 两个轮询周期）。真实回包到达即取消。
    private var userSwitchOverrideTimeout: DispatchWorkItem?

    /// 与主 App 的 pendingSwitchOverride 同一语义：3s 未收到真实状态回包确认则清除覆盖并记日志。
    private func scheduleUserSwitchOverrideTimeout() {
        userSwitchOverrideTimeout?.cancel()
        userSwitchOverrideTimeout = nil
        guard userSwitchOverride != nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.userSwitchOverride != nil else { return }
            self.userSwitchOverride = nil
            self.userSwitchOverrideTimeout = nil
            self.emit("虚拟拨杆覆盖 3s 未收到真实状态回包，已超时清除")
        }
        userSwitchOverrideTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    // MARK: - Public

    func sendState(_ state: UInt8) {
        updatePowerProtectionFromHook(state: state)
        pendingStateReset?.cancel()
        pendingStateReset = nil
        // 切片 5：发送能力受灯效模块 `.running` 门控（启停「发送能力」）；
        // lastSentState / pendingStateReset / live-state 仍留在 Agent（Codex 13:52-2）。
        guard lightingModule?.status == .running else {
            emit("LED 状态 \(state): 灯效模块未运行，发送被门控")
            return
        }
        guard let commandChar, let peripheral else {
            emit("LED 状态 \(state): 未连接")
            return
        }
        let data = Data(header + [0x90, state] + trailer)
        let writeKind = StateCommandWritePolicy.choose(
            supportsWrite: commandChar.properties.contains(.write),
            supportsWriteWithoutResponse: commandChar.properties.contains(.writeWithoutResponse)
        )
        let wt: CBCharacteristicWriteType
        switch writeKind {
        case .withResponse:
            wt = .withResponse
        case .withoutResponse:
            wt = .withoutResponse
        case .unavailable:
            emit("LED 状态 \(state): 命令通道不支持写入")
            return
        }
        peripheral.writeValue(data, for: commandChar, type: wt)
        lastSentState = state
        let confirmation = writeKind == .withResponse ? "等待 BLE 确认" : "无 BLE 确认"
        emit("→ LED 状态 \(state)（\(confirmation)）: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        Self.writeLiveState(stateValue: state)
        // 事件性写入每次必写；stateValue 不参与去重比较，但文件 mtime 已刷新，需重置 touch 计时
        liveStateCoalescer.noteEventWrite(LiveStateWriteCoalescer.Snapshot(), at: Date().timeIntervalSince1970)
    }

    /// 把 agent 当前对键盘的认知（最近一次 hook 发送的 stateValue + BLE 上报的 lightMode/switchState/workMode）
    /// merge-write 到共享文件，供主 App 在 agent 拥有 BLE 时读取实时状态。
    /// 任意调用方只传自己负责更新的字段；未传的字段保留文件中的旧值。
    static func writeLiveState(stateValue: UInt8? = nil,
                               lightMode: UInt8? = nil,
                               switchState: UInt8? = nil,
                               workMode: UInt8? = nil) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("current-ide-state.json")
        var obj: [String: Any] = [:]
        if let existing = try? Data(contentsOf: url),
           let parsed = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] {
            obj = parsed
        }
        let now = Date().timeIntervalSince1970
        if let s = stateValue {
            obj["stateValue"] = Int(s)
            obj["stateTs"] = now
        }
        if let lm = lightMode {
            obj["lightMode"] = Int(lm)
            obj["lightModeTs"] = now
        }
        if let sw = switchState {
            obj["switchState"] = Int(sw)
        }
        if let wm = workMode {
            obj["workMode"] = Int(wm)
        }
        obj["ts"] = now
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 阶段 4：内容无变化时仅 touch mtime 不重写，把 mtime 作为「状态最后确认时间」，
    /// 供 GUI 及任何仍依赖 mtime 的读方判断新鲜度（不触发 JSON 重写，仅一次 attrib 变更）。
    private static func touchLiveStateFile() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/current-ide-state.json")
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func clearLiveSwitchState() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/current-ide-state.json")
        guard let data = try? Data(contentsOf: url),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        obj.removeValue(forKey: "switchState")
        obj["ts"] = Date().timeIntervalSince1970
        guard let encoded = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    private func requestDeviceStatus() {
        guard let commandChar, let peripheral else { return }
        let query = Data(header + [0x00] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(query, for: commandChar, type: wt)
    }

    private func startStatusPolling() {
        statusPollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.5)
        timer.setEventHandler { [weak self] in
            guard let self, self.statusWaiters.isEmpty else { return }
            self.requestDeviceStatus()
        }
        statusPollTimer = timer
        timer.resume()
    }

    private func stopStatusPolling() {
        statusPollTimer?.cancel()
        statusPollTimer = nil
    }

    /// 主动查询一次设备状态，等待下一个 notify 回包 (timeout 秒内)。
    /// 超时时用缓存兜底；仍然没有则返回 nil。完成回调在 main 队列。
    func querySwitchState(timeout: TimeInterval = 1.5,
                          completion: @escaping (AgentDeviceStatus?) -> Void) {
        guard peripheral != nil else {
            completion(nil)
            return
        }
        // 发设备状态查询命令 AA BB 00 CC DD
        requestDeviceStatus()

        statusWaiters.append(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            // 把目前仍在队列里的 waiter 全部用缓存兜底 fire 掉
            guard !self.statusWaiters.isEmpty else { return }
            let waiters = self.statusWaiters
            self.statusWaiters.removeAll()
            let fallback = self.cachedStatus()
            for w in waiters { w(fallback) }
        }
    }

    private func cachedStatus() -> AgentDeviceStatus? {
        guard let sw = cachedSwitchState else { return nil }
        return AgentDeviceStatus(
            battery: -1, signal: -1, firmwareMain: -1, firmwareSub: -1,
            workMode: -1, lightMode: Int(cachedLightMode ?? 0), switchState: Int(sw)
        )
    }

    func startSocketListener() {
        // socket 传输与命令分发保持原位，wire 协议逐字不变。
        // AI 集成模块已在 registerModules() 中注册，启停由 orchestrator 策略驱动。

        // 确保 socket 所在目录仅当前用户可访问
        do {
            try AhaKeyPaths.ensureApplicationSupportDirectory()
        } catch {
            emit("创建 socket 目录失败: \(error.localizedDescription)")
            return
        }

        // 清理旧 socket
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { emit(NSLocalizedString("socket() 失败", comment: "")); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let buf = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                strcpy(buf, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { emit("bind() 失败: \(errno)"); close(fd); return }

        // 限制 socket 文件仅当前用户可读写
        chmod(socketPath, 0o600)

        listen(fd, 5)
        emit("监听 Unix socket: \(socketPath)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFd = accept(fd, nil, nil)
                guard clientFd >= 0 else { continue }
                self?.handleClient(clientFd)
            }
        }
    }

    // MARK: - Hook Socket Server

    func startHookServer() throws {
        let handler: AhaKeyRuntimeHookSocketServer.Handler = { [weak self] handshake, request in
            guard let self else {
                return .acknowledged
            }
            switch request {
            case .aiState(let state):
                DispatchQueue.main.async { [weak self] in
                    self?.handleAIState(state)
                }
                return .acknowledged

            case .approvalQuery(let query):
                let decision = self.approvalDecisionForCurrentState()
                return .approvalDecision(requestID: query.requestID, decision: decision)

            case .leverQuery:
                let position = self.leverPositionForCurrentState()
                return .leverPosition(position)

            case .handshake:
                // Server handles handshake internally; this path should not be reached.
                return .acknowledged
            }
        }

        let server = AhaKeyRuntimeHookSocketServer(
            socketURL: hookSocketURL,
            handler: handler
        )
        try server.start()
        hookServer = server
        emit("监听 Hook socket: \(hookSocketURL.path)")
    }

    private func handleAIState(_ state: AhaKeyRuntimeHookAIState) {
        let stateValue: UInt8
        switch state.event {
        case .idle, .sessionEnded:
            stateValue = 5
        case .working:
            stateValue = 3
        case .permissionRequested:
            stateValue = 1
        case .awaitingFollowup:
            stateValue = 7
        }
        sendState(stateValue)
    }

    private func approvalDecisionForCurrentState() -> AhaKeyRuntimeHookApprovalDecision {
        guard let switchState = effectiveSwitchState else {
            return .unavailable
        }
        switch switchState {
        case 0: return .automatic
        case 1: return .manual
        default: return .unavailable
        }
    }

    private func leverPositionForCurrentState() -> AhaKeyRuntimeLeverPosition? {
        guard let switchState = effectiveSwitchState else { return nil }
        switch switchState {
        case 0: return .up
        case 1: return .down
        default: return nil
        }
    }

    // MARK: - 看门狗

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.checkWatchdog()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        didLogWatchdogHold = false
    }

    /// 「超时但进程仍存活」的保持日志每个 episode 只记一次，避免 10s 周期刷屏。
    private var didLogWatchdogHold = false

    private func checkWatchdog() {
        guard let lastAt = lastHookStateAt else { return }
        let elapsed = Date().timeIntervalSince(lastAt)
        let threshold = watchdogTimeout(for: lastSentState)
        // 归位门控：一般执行态只有目标 CLI 进程全部退出才归位；PostToolUse(2)
        // 已表示工具结束，Codex Desktop 若漏发 Stop，则允许其超时归位。
        switch HookStateWatchdog.decide(HookStateWatchdog.Input(
            lastSentState: lastSentState,
            elapsedSinceLastHook: elapsed,
            timeout: threshold,
            isTargetProcessRunning: processDetector.isAnyTargetRunning
        )) {
        case .notActiveState, .withinTimeout:
            return
        case .heldProcessAlive:
            if !didLogWatchdogHold {
                didLogWatchdogHold = true
                emit("⏰ 看门狗：\(Int(elapsed))s 无 hook 活动（上次 LED=\(lastSentState)，阈值 \(Int(threshold))s），但目标进程仍在运行，保持灯效")
            }
            return
        case .resetToIdle:
            let reason = lastSentState == 2 ? "PostToolUse 后未收到 Stop" : "目标进程已退出"
            emit("⏰ 看门狗：\(Int(elapsed))s 无 hook 活动且\(reason)（上次 LED=\(lastSentState)，阈值 \(Int(threshold))s），自动发 Stop(5)")
            didLogWatchdogHold = false
            hookActivityActive = false
            powerProtection.end(.aiCodingIdleHook)
            powerProtection.end(.aiCodingLidCloseHook)
            sendState(5)
            lastHookStateAt = nil  // 重置，避免重复触发
        }
    }

    // MARK: - Socket handling

    /// 单个客户端的处理：读一包请求，按 JSON 或旧版纯数字分发。
    ///
    /// 协议：
    /// - JSON 一行：`{"cmd":"state","value":3}` / `{"cmd":"permission","value":1}` / `{"cmd":"status"}`
    /// - 纯数字（兼容旧 `ahakey-state.sh`）：`3` → sendState(3)，不回包
    private func handleClient(_ clientFd: Int32) {
        // 校验对端 UID，拒绝其他用户连接
        var peerUid: uid_t = 0
        var peerGid: gid_t = 0
        if getpeereid(clientFd, &peerUid, &peerGid) != 0 || peerUid != getuid() {
            emit("拒绝非当前用户的 socket 连接 (uid=\(peerUid))")
            close(clientFd)
            return
        }

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = read(clientFd, &buf, buf.count)
        guard n > 0 else { close(clientFd); return }

        let line = String(bytes: buf[0 ..< Int(n)], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // JSON 请求
        if let lineData = line.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
           let cmd = obj["cmd"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.handleJsonCommand(cmd: cmd, obj: obj, clientFd: clientFd)
            }
            return // fd 在命令 handler 里最终关闭
        }

        // 旧协议：纯数字当作 state，fire-and-forget
        if let state = UInt8(line) {
            DispatchQueue.main.async { [weak self] in self?.sendState(state) }
        }
        close(clientFd)
    }

    /// 在主队列执行的 JSON 命令分发。回包由 `replyAndClose` 负责异步写入 + 关 fd。
    private func handleJsonCommand(cmd: String, obj: [String: Any], clientFd: Int32) {
        switch cmd {
        case "state":
            if let v = obj["value"] as? Int {
                lastHookStateAt = Date()
                didLogWatchdogHold = false
                sendState(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, ["ok": true])

        case "state_with_reset":
            let stateValue = obj["value"] as? Int ?? 0
            let resetValue = obj["resetValue"] as? Int ?? 4
            let delayMs = max(0, obj["delayMs"] as? Int ?? 1200)
            sendState(UInt8(clamping: stateValue))
            scheduleStateReset(
                to: UInt8(clamping: resetValue),
                afterMs: delayMs,
                reason: "temporary state \(stateValue) -> reset \(resetValue)"
            )
            Self.replyAndClose(clientFd, ["ok": true])

        case "permission":
            // 发 PermissionRequest 对应的 state（默认 1），同时主动查询拨杆
            let stateValue = obj["value"] as? Int ?? 1
            lastHookStateAt = Date()
            didLogWatchdogHold = false
            sendState(UInt8(clamping: stateValue))
            querySwitchState(timeout: 1.5) { status in
                let body = Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode)
                self.emit("← permission 回包 switchState=\(String(describing: body["switchState"]))")
                if let s = body["switchState"] as? Int, s != 0 {
                    self.emit(NSLocalizedString("（拨杆非 0：PermissionRequest 将交回终端手动确认）", comment: ""))
                } else if body["switchState"] is NSNull {
                    self.emit(NSLocalizedString("（switchState 缺省：批准链可能仍交回手动；请把「蓝牙」交给 Agent 并连上键盘。）", comment: ""))
                }
                Self.replyAndClose(clientFd, body)
            }

        case "status":
            // 每次都请求真实 GPIO 状态，不能因旧缓存或虚拟模拟而返回过期档位。
            querySwitchState(timeout: 1.5) { status in
                Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode))
            }

        case "approval_status":
            // 给 Kimi CLI 的实时批准判断用：每次都主动向设备要当前拨杆，避免会话内沿用旧的 yolo/state。
            querySwitchState(timeout: 1.5) { status in
                Self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode))
            }

        case "set_switch_override":
            // 主 App 画布虚拟拨杆点击 → 设置 / 清除覆盖
            // value=null / 缺省 → 清除（恢复用真实 BLE 上报）
            // value=0/1/2 → 设置短暂模拟，真实状态回包会自动清除
            if obj["value"] is NSNull || obj["value"] == nil {
                setSwitchOverride(nil)
            } else if let v = obj["value"] as? Int {
                setSwitchOverride(UInt8(clamping: v))
            }
            Self.replyAndClose(clientFd, [
                "ok": true,
                "switchState": effectiveSwitchState.map { Int($0) } ?? NSNull(),
                "override": userSwitchOverride.map { Int($0) } ?? NSNull(),
            ])

        default:
            Self.replyAndClose(clientFd, ["error": "unknown cmd: \(cmd)"])
        }
    }

    private static func statusReply(_ status: AgentDeviceStatus?,
                                    cachedSwitch: UInt8?,
                                    cachedLight: UInt8?) -> [String: Any] {
        if let s = status {
            return ["switchState": s.switchState, "lightMode": s.lightMode]
        }
        return [
            "switchState": cachedSwitch.map { Int($0) } ?? NSNull(),
            "lightMode": cachedLight.map { Int($0) } ?? NSNull(),
        ]
    }

    private func scheduleStateReset(to state: UInt8, afterMs: Int, reason: String) {
        pendingStateReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sendState(state)
            self.emit("自动回落灯态：\(reason)")
        }
        pendingStateReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(afterMs), execute: work)
    }

    private static func replyAndClose(_ fd: Int32, _ dict: [String: Any]) {
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                var out = data
                out.append(0x0A) // \n 作为消息边界
                _ = out.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return write(fd, base, ptr.count)
                }
            }
            close(fd)
        }
    }

    // MARK: - Connection

    /// 跨进程 BLE 连接锁（阶段 3，flock）：发起连接前必须持有；抢不到绝对不 attach（含系统已连接外设）
    private let connectionLock = BLEConnectionLock()
    /// 锁被 GUI 占用的提示是否已记录（只记一次状态转换，重试不刷日志）
    private var didLogLockBusy = false
    /// 抢锁失败后的 15s 重试项
    private var lockRetryItem: DispatchWorkItem?

    private func connectAutomatically() {
        // 跨进程锁：抢不到不连接，15s 后重试
        guard acquireConnectionLock() else { return }
        // 1. 用已知 UUID
        if let uuid = lastUUID {
            let known = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = known.first {
                emit("直连已知设备: \(uuid.uuidString.prefix(8))…")
                peripheral = p
                p.delegate = self
                central.connect(p, options: nil)
                return
            }
        }

        // 2. 系统已连接
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let p = connected.first(where: { ($0.name ?? "").lowercased().hasPrefix(deviceNamePrefix.lowercased()) }) {
            emit("系统已连接: \(p.name ?? "?")")
            peripheral = p
            p.delegate = self
            central.connect(p, options: nil)
            return
        }

        // 3. 扫描
        emit(NSLocalizedString("开始扫描…", comment: ""))
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    /// 发起连接前必须持有跨进程连接锁；被 GUI 持有时不 attach，15s 后重试（不刷日志）。
    private func acquireConnectionLock() -> Bool {
        guard !connectionLock.holdsLock else { return true }
        if connectionLock.acquire() {
            if didLogLockBusy {
                emit(NSLocalizedString("GUI 已释放蓝牙，恢复连接", comment: ""))
                didLogLockBusy = false
            }
            return true
        }
        if !didLogLockBusy {
            emit(NSLocalizedString("蓝牙被 GUI 占用，等待释放后重试", comment: ""))
            didLogLockBusy = true
        }
        scheduleLockRetry()
        return false
    }

    /// 抢锁失败后的 15s 低频重试；抢到锁后继续走正常连接流程。
    private func scheduleLockRetry() {
        guard lockRetryItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lockRetryItem = nil
            guard !self.connectionLock.holdsLock, self.peripheral == nil else { return }
            self.connectAutomatically()
        }
        lockRetryItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
    }

    private func emit(_ msg: String) {
        log.info("\(msg)")
        onLog?(msg)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            emit(NSLocalizedString("蓝牙就绪", comment: ""))
            connectAutomatically()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.lowercased().hasPrefix(deviceNamePrefix.lowercased()) else { return }
        central.stopScan()
        emit("发现: \(name)")
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        lastUUID = peripheral.identifier
        emit("已连接: \(peripheral.name ?? "?")")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopStatusPolling()
        commandChar = nil
        notifyChar = nil
        self.peripheral = nil
        cachedSwitchState = nil
        cachedLightMode = nil
        // 把 pending 的 waiter 全部通知为 nil（避免 hook 客户端一直等）
        if !statusWaiters.isEmpty {
            let waiters = statusWaiters
            statusWaiters.removeAll()
            for w in waiters { w(nil) }
        }
        emit(NSLocalizedString("已断开，2s 后重连", comment: ""))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectAutomatically()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([commandCharUUID, notifyCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == commandCharUUID {
                commandChar = char
                emit(NSLocalizedString("命令通道就绪", comment: ""))
            } else if char.uuid == notifyCharUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                emit(NSLocalizedString("通知通道已订阅", comment: ""))
            }
        }
        // 两个特征都就绪后发一次初始状态查询
        if commandChar != nil, notifyChar != nil {
            requestDeviceStatus()
            startStatusPolling()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == commandCharUUID || characteristic.uuid == notifyCharUUID,
              let data = characteristic.value else { return }
        if let acknowledgement = StateCommandAcknowledgement.parse(data) {
            if acknowledgement.resultCode == 0 {
                emit("← 固件已应用 LED/OLED 状态命令 0x90")
            } else {
                emit("← 固件拒绝 LED/OLED 状态命令 0x90，错误码 \(acknowledgement.resultCode)")
            }
            return
        }
        guard let status = Self.parseDeviceStatus(data) else { return }

        let hardwareSwitchState = UInt8(clamping: status.switchState)
        let previousSwitchState = cachedSwitchState
        cachedSwitchState = hardwareSwitchState
        cachedLightMode = UInt8(clamping: status.lightMode)
        if userSwitchOverride != nil {
            userSwitchOverride = nil
            userSwitchOverrideTimeout?.cancel()
            userSwitchOverrideTimeout = nil
            emit("← 收到真实拨杆状态 \(hardwareSwitchState)，已清除虚拟拨杆覆盖")
        }
        if previousSwitchState != hardwareSwitchState {
            KimiTUIAdapter.applyModeIfNeeded(for: Int(hardwareSwitchState))
        }
        emit("← status battery=\(status.battery) light=\(status.lightMode) switch=\(status.switchState)")
        // 阶段 4 写前去重：与最后已发布快照比较，相同不重复落盘（GUI 目录监听零唤醒）；
        // 30s 无任何写入时仅 touch mtime。真实变化（或首次发布）才落盘——
        // 一律写入键盘真实 GPIO 状态，避免旧虚拟模拟把 UI / hook 锁在错误档位。
        let snapshot = LiveStateWriteCoalescer.Snapshot(
            lightMode: status.lightMode,
            switchState: Int(hardwareSwitchState),
            workMode: max(0, status.workMode)
        )
        switch liveStateCoalescer.decision(for: snapshot, at: Date().timeIntervalSince1970) {
        case .write:
            Self.writeLiveState(
                lightMode: UInt8(clamping: status.lightMode),
                switchState: hardwareSwitchState,
                workMode: UInt8(clamping: max(0, status.workMode))
            )
        case .touchOnly:
            Self.touchLiveStateFile()
        case .skip:
            break
        }

        guard !statusWaiters.isEmpty else { return }
        let waiters = statusWaiters
        statusWaiters.removeAll()
        for w in waiters { w(status) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == commandCharUUID else { return }
        if let error {
            emit("← LED/OLED 状态 BLE 写入失败：\(error.localizedDescription)")
        } else {
            emit("← LED/OLED 状态 BLE 写入已确认")
        }
    }

    // MARK: - 协议内联解析

    /// 解析 AA BB 00 [battery][signal][fw_main][fw_sub][work][light][switch][reserve] CC DD
    /// 与 Sources/BLE/AhaKeyProtocol.swift:parseDeviceStatus 等价
    private static func parseDeviceStatus(_ data: Data) -> AgentDeviceStatus? {
        guard data.count >= 12,
              data[0] == 0xAA, data[1] == 0xBB,
              data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD else {
            return nil
        }
        let payload = data[2 ..< data.count - 2]
        guard payload.count >= 8, payload[payload.startIndex] == 0x00 else { return nil }
        let base = payload.startIndex + 1 // 跳过 cmd echo
        return AgentDeviceStatus(
            battery: Int(payload[base]),
            signal: Int(Int8(bitPattern: payload[base + 1])),
            firmwareMain: Int(payload[base + 2]),
            firmwareSub: Int(payload[base + 3]),
            workMode: Int(payload[base + 4]),
            lightMode: Int(payload[base + 5]),
            switchState: Int(payload[base + 6])
        )
    }
}
