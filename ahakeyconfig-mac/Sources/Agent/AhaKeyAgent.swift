import Combine
import CoreBluetooth
import Foundation
import ObjectiveC
import os.log
import AhaKeyConfigShared
import RuntimeXPCServer

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig.agent", category: "BLE")
/// 冻结在真实 callback 对象上的订阅身份；对象复用时只标 ambiguous，不得覆写为新代。
private var oledNotifyCallbackBindingAssociationKey: UInt8 = 0

/// 配置事务期间暂缓 0x90 的协调器。隔离由 `@MainActor` 表达；begin/end 必须配对。
@MainActor
final class AhaKeyConfigurationTransportWindow {
    enum SendDecision: Equatable {
        /// 窗口未开，调用方应立即下发。
        case sendNow
        /// 首次暂缓或值变化：调用方记一条常规日志。
        case deferAndLog(UInt8)
        /// 与当前暂缓值相同：不写下发、不写常规日志。
        case deferSilent
    }

    enum CloseDecision: Equatable {
        case stillOpen
        /// 窗口归零且有暂缓值：恰好补发一次。
        case replayAndLog(UInt8)
        /// 窗口归零且无暂缓值：不补发。
        case idle
        /// end 次数超过 begin：不静默归零、不补发。
        case unmatchedEnd
    }

    private var inFlight = 0
    private var deferred: UInt8?

    var isActive: Bool { inFlight > 0 }

    /// - Returns: `true` 当 0→1，调用方记「窗口进入」。
    @discardableResult
    func begin() -> Bool {
        let opened = inFlight == 0
        inFlight += 1
        return opened
    }

    func evaluateSend(_ state: UInt8) -> SendDecision {
        guard inFlight > 0 else { return .sendNow }
        if deferred == state { return .deferSilent }
        deferred = state
        return .deferAndLog(state)
    }

    func end() -> CloseDecision {
        guard inFlight > 0 else { return .unmatchedEnd }
        inFlight -= 1
        guard inFlight == 0 else { return .stillOpen }
        if let value = deferred {
            deferred = nil
            return .replayAndLog(value)
        }
        return .idle
    }
}

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
    /// 兼容默认策略：保持现有生产行为（AI Hook + 动态灯效 + 防休眠开启），
    /// 其余模块按策略显式启停。随策略化装配成熟后可改为全部关闭。
    public static let compatibleDefaultPolicy: AhaKeyRuntimePolicy = {
        var policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.claude, .cursor, .codex, .kimi]
        policy.devicePresentation.ledEnabled = true
        policy.powerProtectionEnabled = true
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
    /// 数据特征（配置事务资源块直写，WBS-5.6）
    private let dataCharUUID = CBUUID(string: "7341")
    private var dataChar: CBCharacteristic?
    /// Device Information：改名设备（无 4 位名后缀）靠 2A25 序列号推导稳定身份
    private let deviceInfoServiceUUID = CBUUID(string: "180A")
    private let serialNumberCharUUID = CBUUID(string: "2A25")
    private let deviceNamePrefix = "AhaKey"
    private let socketPath: String
    private let legacySocketLock = NSLock()
    private var legacyListenGeneration: UInt64 = 0
    private var legacySession: LegacyListenSession?
    private var legacyOwnerUnlinkCount = 0
    private var legacyLastAcceptWorkerExited = true
    /// Test-only: replace `listen(2)`. Production nil.
    var legacyListenHookForTesting: ((Int32) -> Int32)?
    /// Test-only reply-before-write barrier for `status` / `permission`. Production nil.
    var legacyReplyBeforeWriteGate: AhaKeyRuntimeLegacyReplyGate?

    /// One listen generation: listener fd, accept worker, and in-flight accepted clients.
    private final class LegacyListenSession {
        let generation: UInt64
        var listenFD: Int32
        let socketPath: String
        let workers = DispatchGroup()
        var clientFDs: Set<Int32> = []

        init(generation: UInt64, listenFD: Int32, socketPath: String) {
            self.generation = generation
            self.listenFD = listenFD
            self.socketPath = socketPath
        }
    }

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

    /// 状态查询 waiter 的完成回调（requestID → completion）。
    /// 注册/路由全部经 DeviceTransportCore（五元绑定）；本表只挂回调。
    private var waiterCompletions: [UInt64: (AgentDeviceStatus?) -> Void] = [:]
    /// operationID → requestID（回包路由用）
    private var operationWaiters: [UInt64: UInt64] = [:]
    private var operationCounter: UInt64 = 0
    /// head 命令超时（无应答时放行下一条，防止队列卡死）
    private var headTimeoutItem: DispatchWorkItem?

    // MARK: 设备 transport 核心（WBS-5.5 切片 3）
    /// 生命周期/代际/waiter 归属的唯一决策点；本类只做 CoreBluetooth 适配与动作落地。
    /// fileprivate：程序执行 transport（本文件内）需读 isReady 做取消检查点。
    private let bleLifecycle = AhaKeyBLELifecycleAdapter()
    fileprivate var transportCore: DeviceTransportCore {
        get { bleLifecycle.core }
        set { bleLifecycle.core = newValue }
    }
    /// 同一次 `retrieveConnectedPeripherals` 得到的外设；connect 不得再查。
    private var retrievedSystemAttached: [CBPeripheral] = []
    /// 0x99 协商进度
    private var negotiationAttempts = 0
    private var awaitingCapabilityResponse = false
    private var negotiationTimeoutItem: DispatchWorkItem?
    /// 协商出的固件能力（配置事务 planner 输入，WBS-5.6）
    private var negotiatedCapabilities: AhaKeyFirmwareCapabilities?
    /// 密封 OLED 兼容事实。只能从 0x99 解析或 no-0x99 + v1 + 0x94 实探得到。
    private var negotiatedOLEDContext: AhaKeyOLEDCompatibilityContext?
    /// 收到过无法解析的 0x99：不得再走 Standard 回退。
    private var sawMalformedCapabilityFrame = false
    private enum OLEDLegacyProbePhase {
        case idle
        case awaitingFirmwareVersion
        case awaitingTaskPicture
    }
    private var oledLegacyProbePhase: OLEDLegacyProbePhase = .idle
    private var legacyProbeFirmwareMainVersion: Int?
    /// OLED 协商归属的连接代际。新连接/断连递增；过期 timeout/response 必须零状态变化。
    private var oledConnectionGeneration: UInt64 = 0
    /// 当前在途 `0x99/0x00/0x94` 请求身份。response 必须同时匹配 source generation 与 peripheral。
    private var oledInFlightRequest: OLEDNotifySource?
    /// 仍存活的 callback 对象弱集；不持有 source/tombstone 账本。
    private let oledNotifyBoundIdentities = NSHashTable<AnyObject>.weakObjects()

    private struct OLEDNotifySource: Equatable {
        let generation: UInt64
        let peripheralID: UUID
    }

    private enum OLEDNotifyCallbackState {
        case source(OLEDNotifySource)
        case ambiguous
        case invalid
    }

    private final class OLEDNotifyCallbackBinding {
        var state: OLEDNotifyCallbackState
        init(state: OLEDNotifyCallbackState) {
            self.state = state
        }
    }

    // MARK: 配置事务（WBS-5.6）：sequencer 命令 waiter + 0x81 数据写 waiter + 恢复接线
    /// 配置类命令走 DeviceTransportCore 串行队列 + 五元 waiter（与状态查询同一纪律）；
    /// requestID → continuation；operationID → requestID 路由表。
    private var configWaiterContinuations: [UInt64: CheckedContinuation<(status: UInt8, payload: Data), Error>] = [:]
    private var configOperationWaiters: [UInt64: UInt64] = [:]
    /// 0x81 图片写入确认 waiter（数据通道；session 校验在路由处）。
    private var dataWriteContinuation: CheckedContinuation<Void, Error>?
    private var dataWriteTimeoutItem: DispatchWorkItem?
    /// 在途 0x9B 会话（0x81 须匹配；失败/取消时 0x9A 回滚）。
    private var activeUploadSessionID: UInt16?
    /// 编码字节流缓存（digest → RGB565 流；CAS 源绝不直接当 flash 数据）。
    private var encodedStreamCache: [AhaKeySHA256Digest: Data] = [:]
    /// 配置事务窗口：>0 期间不下发 0x90（固件收到 0x90 会全屏重绘 OLED）。
    /// 隔离由窗口类型的 `@MainActor` 保证。
    @MainActor
    private let configurationTransportWindow = AhaKeyConfigurationTransportWindow()

    // MARK: 状态归并（WBS-5.5 切片 4：周期帧与连接生命周期经 DeviceStateReducer）
    private var coreSnapshot = CoreDeviceSnapshot()
    private var diagnosticsSnapshot = DeviceDiagnosticsSnapshot()
    /// 工具完成 / 用户提交等短暂态的自动回落。
    private var pendingStateResetTask: Task<Void, Never>?
    /// 递增令牌：已取消或过时的 reset 即使已过 delay、已在 MainActor 排队也必须无效。
    private var pendingStateResetGeneration: UInt64 = 0
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

    // MARK: Runtime 编排（WBS 5.4 切片 3：策略驱动模块启停，唯一入口为 RuntimeOrchestrator）
    private let orchestrator = RuntimeOrchestrator()
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

    // MARK: - XPC Server（WBS-5.6 R1：生产配置入口）
    private var xpcServer: AhaKeyRuntimeXPCLibXPCServer?

    // MARK: Runtime 生产投影 / 事件回放（WBS-5.7 R1）
    /// 投影事件序列号（单调递增；0 = 尚无事件）。仅 main 队列读写。
    private var projectionLatestSequence = AhaKeyRuntimeEventSequence(0)
    /// 有界回放缓冲：超界丢弃最老事件，断档客户端收 snapshotRequired。仅 main 队列读写。
    private var projectionEventBuffer: AhaKeyRuntimeEventReplayBuffer
    /// events long-poll 挂起的 waiter（新事件或超时唤醒）。仅 main 队列读写。
    /// R2-5：continuation 携带复查结果——非 nil 为临界区内二次复查的即时结果，
    /// nil 为「被唤醒/超时/取消，请最终复查」信号。
    private var projectionEventWaiters: [UUID: CheckedContinuation<AhaKeyRuntimeEventReplayVerdict?, Never>] = [:]
    /// 本会话已知 operation 摘要（含终态窗口；snapshot.operations 与 WAL 合并）。仅 main 队列。
    private var projectionOperations: [AhaKeyRuntimeOperationID: AhaKeyRuntimeOperationSummary] = [:]
    /// C-2：资源字节进度内存投影，不进 WAL。仅 main 队列。
    private var byteProgressByOperation: [AhaKeyRuntimeOperationID: AhaKeyByteProgressProjector] = [:]
    /// 最近一次真正发出的 operationChanged（完整 summary 去重）。仅 main 队列。
    private var lastPublishedOperationSummaries: [AhaKeyRuntimeOperationID: AhaKeyRuntimeOperationSummary] = [:]
    /// 最近一次 running operationChanged 的单调 tick（所有 running 事件共享 ≤4Hz）。仅 main 队列。
    private var lastRunningPublishAtNanos: [AhaKeyRuntimeOperationID: UInt64] = [:]
    /// C-2R1 测试：skip-BLE 路径上已成功 0x81 ACK 的 chunk 数。仅 main 队列。
    private var configurationChunkAckCount = 0
    /// 终态 operation 插入序（投影终态缓存上限 64，超出淘汰最老；WAL 仍持久）。
    private var projectionTerminalOrder: [AhaKeyRuntimeOperationID] = []
    /// 诊断/安全事件留存（diagnostics 请求用；有界小表）。
    private var projectionDiagnosticEvents: [AhaKeyRuntimeEvent] = []
    /// 最近发布的设备投影（内容不变不重复发 deviceChanged）。
    private var lastPublishedDeviceSnapshot: AhaKeyRuntimeDeviceSnapshot?
    /// deviceChanged 触发的 live CAS 持久化；测试 seam 等待该任务完成。
    private var authoritativeObjectPersistTask: Task<Void, Never>?
    /// 最近一次应用的策略（projection policy 字段来源）。
    private var currentPolicy: AhaKeyRuntimePolicy
    /// R2-2 / R3：串行执行协调器。init 内同步一次构造（非 lazy），避免双 XPC 竞态出两个 actor。
    private var configurationCoordinator: AhaKeyConfigurationExecutionCoordinator!
    /// R2-2：Runtime Store 缓存收敛进 actor（多 XPC session 并发读写隔离）。
    private let runtimeStoreCache = AhaKeyAgentRuntimeStoreCache()
    /// events 空批 long-poll 时长（秒）；测试注入短值。
    var runtimeEventsLongPollInterval: TimeInterval = 2.0
    /// R4：long-poll 会话状态机。仅 main 队列。
    private enum LongPollSession {
        case registering
        case waiting(CheckedContinuation<AhaKeyRuntimeEventReplayVerdict?, Never>)
        case cancelled
    }
    private var longPollSessions: [UUID: LongPollSession] = [:]
    /// long-poll 超时任务句柄（continuation 闭包为 @Sendable，不能捕获 inout）。
    private final class LongPollTimeoutBox: @unchecked Sendable {
        var task: Task<Void, Never>?
    }
    /// 集成测试 seam（仅 @testable；生产为 nil）。
    var executionTestHooks: AhaKeyAgentExecutionTestHooks?
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
        initialPolicy: AhaKeyRuntimePolicy = AhaKeyAgent.compatibleDefaultPolicy,
        eventReplayCapacity: Int = 256,
        enableRuntimeModules: Bool = true
    ) {
        self.socketPath = socketPath
        self.hookSocketURL = hookSocketURL
        self.currentPolicy = initialPolicy
        self.projectionEventBuffer = AhaKeyRuntimeEventReplayBuffer(capacity: eventReplayCapacity)
        // 旧版会持久化虚拟拨杆覆盖，导致真实硬件档位永远无法回写。迁移时清除它。
        UserDefaults.standard.removeObject(forKey: Self.switchOverrideDefaultsKey)
        super.init()
        bleLifecycle.host = self
        central = CBCentralManager(delegate: self, queue: nil)
        Self.clearLiveSwitchState()
        self.configurationCoordinator = AhaKeyConfigurationExecutionCoordinator(
            pendingPackages: { [weak self] in
                guard let self,
                      let store = try? await self.makeRuntimeStore(),
                      let candidates = try? await store.recoveryCandidates() else { return [] }
                return candidates.map { $0.package }
            },
            settleQueuedCancellations: { [weak self] in
                await self?.settleQueuedCancellations()
            },
            executePackage: { [weak self] package in
                guard let self else { return false }
                do {
                    if let store = try? await self.makeRuntimeStore(),
                       let record = try? await store.transaction(package.operationID) {
                        if record.state == .paused || record.state == .resumablePartial {
                            let ready = await MainActor.run { self.configurationWriteIsReady() }
                            let isPage = record.package.schemaVersion
                                == AhaKeyConfigurationPackage.pageScopedSchemaVersion
                            if !isPage || !ready {
                                return false
                            }
                        }
                        if record.state.isTerminal { return true }
                    }
                    let state = try await self.applyConfigurationPackage(package, resourceFiles: [:])
                    self.emit("配置事务 \(package.operationID.rawValue.uuidString.prefix(8))… 执行结果：\(state.rawValue)")
                    await self.publishOperationProgress(operationID: package.operationID)
                    return state.isTerminal
                } catch {
                    self.emit("配置事务 \(package.operationID.rawValue.uuidString.prefix(8))… 执行延迟/中断：\(error.localizedDescription)")
                    await self.publishOperationProgress(operationID: package.operationID)
                    return false
                }
            }
        )
        if enableRuntimeModules {
            Task {
                await registerModules()
                await orchestrator.applyPolicy(initialPolicy)
            }
        }
    }

    /// 切片 6：AhaType seam 装配——仅登记生命周期；引擎实体（转写/优化器/HUD）
    /// 仍在 Studio 进程（Sources/Utilities，本卡禁改），策略桥接待 WBS 5.7。
    private func registerAhaTypeModule() async {
        let module = AhaTypeRuntimeModule(
            onStart: { [weak self] in self?.emit("AhaType seam 已启动（引擎实体由 Studio 承载，策略桥接待 5.7）") },
            onStop: { [weak self] in self?.emit("AhaType seam 已停止") }
        )
        ahaTypeModule = module
        await orchestrator.register(module)
    }

    /// 切片 5：灯效模块装配——orchestrator 注册（启动由策略驱动）。
    private func registerLightingModule() async {
        let module = LightingRuntimeModule()
        lightingModule = module
        await orchestrator.register(module)
    }

    func shutdown() {
        stopLegacySocketListener()
        hookServer?.stop()
        hookServer = nil
        processDetector.stop()
        _ = powerProtection.deactivateAll()
        // 编排器侧清理（模块 stop 委托到 deactivate，与上面幂等重叠无害）
        Task { await orchestrator.stopAll() }
        lockRetryItem?.cancel()
        lockRetryItem = nil
        AhaKeyBLELifecycleSeam.run { [weak self] in
            self?.bleLifecycle.shutdown(now: Date())
        }
        connectionLock.release()
        // R1：events long-poll 挂起 waiter 收尾（进程退出路径，绝不泄漏 continuation）。
        let flushWaiters = { [weak self] in
            guard let self else { return }
            let pendingWaiters = self.projectionEventWaiters
            self.projectionEventWaiters.removeAll()
            self.longPollSessions.removeAll()
            for (_, continuation) in pendingWaiters { continuation.resume(returning: nil) }
        }
        if Thread.isMainThread {
            flushWaiters()
        } else {
            DispatchQueue.main.async(execute: flushWaiters)
        }
    }

    private func registerPowerProtectionModule() async {
        // 防休眠经 RuntimeOrchestrator 编排（切片 3）：模块 start/stop 委托到
        // 原有 activate/deactivate 行为，策略化 gating 由 orchestrator 策略驱动。
        let module = PowerProtectionRuntimeModule(
            onStart: { [weak self] in self?.activatePowerProtectionBehavior() },
            onStop: { [weak self] in self?.deactivatePowerProtectionBehavior() }
        )
        powerProtectionModule = module
        await orchestrator.register(module)
    }

    /// 注册所有 Runtime 模块到 Orchestrator（只注册，不启动；启停由策略驱动）。
    private func registerModules() async {
        await registerPowerProtectionModule()
        await registerLightingModule()
        await registerAhaTypeModule()
        await registerAIIntegrationModule()
    }

    /// 切片 4：AI 集成模块注册（看门狗 + 进程兜底即时检测）。
    private func registerAIIntegrationModule() async {
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
        await orchestrator.register(module)
    }

    /// 策略更新入口。外部（Studio XPC / CLI）通过此处驱动模块启停。
    func updatePolicy(_ policy: AhaKeyRuntimePolicy) async {
        await orchestrator.applyPolicy(policy)
        await MainActor.run {
            guard self.currentPolicy != policy else { return }
            self.currentPolicy = policy
            self.publishRuntimeEvent(.policyChanged(policy))
        }
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

    @MainActor
    func sendState(_ state: UInt8) {
        traceCommand(.sendState(state))
        updatePowerProtectionFromHook(state: state)
        invalidatePendingStateReset()
        // 切片 5：发送能力受灯效模块 `.running` 门控（启停「发送能力」）；
        // lastSentState / pendingStateReset / live-state 仍留在 Agent（Codex 13:52-2）。
        // 测试可跳过 BLE 写出门控，但仍必须走命令构造与 `transportCore.enqueue`。
        let skipBLEWriteGates = executionTestHooks?.skipStateCommandBLEWriteGates == true
        if !skipBLEWriteGates {
            guard lightingModule?.status == .running else {
                emit("LED 状态 \(state): 灯效模块未运行，发送被门控")
                return
            }
            guard let commandChar, let peripheral else {
                emit("LED 状态 \(state): 未连接")
                return
            }
        }
        switch configurationTransportWindow.evaluateSend(state) {
        case .deferAndLog(let value):
            emit("LED 状态 \(value): 配置事务进行中，暂缓下发")
            return
        case .deferSilent:
            return
        case .sendNow:
            break
        }
        // current-only（WBS-5.5）：0x99 协商未到 .current 前不下发业务命令。
        guard transportCore.isReady else {
            emit("LED 状态 \(state): 协议协商未完成或非 current，发送被门控")
            return
        }
        // 串行队列（WBS-5.5 ①）：sendState 不得绕过队列直写。
        operationCounter &+= 1
        let cmd = DeviceCommand(
            operationID: operationCounter,
            deviceID: transportCore.stableDeviceID ?? "",
            generations: transportCore.currentGenerations,
            opcode: 0x90,
            payload: Data([state])
        )
        // enqueue 总是入队；返回值只表示是否提升为可立即写出的 head。
        let head = transportCore.enqueue(cmd)
        traceCommand(.enqueuedState(state))
        if let head {
            writeCommand(head)
        }
    }

    /// 仅用于真正非隔离 ingress（socket 读线程上的旧纯数字协议）。
    /// 已在 `@MainActor` 上的命令入口必须同步调用 `sendState`，不得再 hop。
    private func sendStateHoppingToMain(_ state: UInt8) {
        Task { @MainActor [weak self] in
            self?.sendState(state)
        }
    }

    private func traceCommand(_ event: AhaKeyAgentCommandTraceEvent) {
        executionTestHooks?.commandTrace?(event)
    }

    /// head 命令的真实 BLE 写入（wire 协议逐字不变）。
    private func writeCommand(_ cmd: DeviceCommand) {
        guard let commandChar, let peripheral else { return }
        let frame: Data
        switch cmd.opcode {
        case 0x90:
            guard let state = cmd.payload.first else { return }
            frame = Data(header + [0x90, state] + trailer)
        case 0x00:
            frame = Data(header + [0x00] + trailer)
        default:
            frame = Data(header + [cmd.opcode] + cmd.payload + trailer)
        }
        let writeKind = StateCommandWritePolicy.choose(
            supportsWrite: commandChar.properties.contains(.write),
            supportsWriteWithoutResponse: commandChar.properties.contains(.writeWithoutResponse)
        )
        let wt: CBCharacteristicWriteType
        switch writeKind {
        case .withResponse: wt = .withResponse
        case .withoutResponse: wt = .withoutResponse
        case .unavailable:
            emit("命令 0x\(String(cmd.opcode, radix: 16)): 命令通道不支持写入")
            _ = transportCore.completeHeadCommand()
            return
        }
        peripheral.writeValue(frame, for: commandChar, type: wt)
        if cmd.opcode == 0x90, let state = cmd.payload.first {
            lastSentState = state
            emit("→ LED 状态 \(state): \(frame.map { String(format: "%02X", $0) }.joined(separator: " "))")
            Self.writeLiveState(stateValue: state)
            liveStateCoalescer.noteEventWrite(LiveStateWriteCoalescer.Snapshot(), at: Date().timeIntervalSince1970)
        }
        // head 超时：无应答时放行下一条，防止队列卡死
        headTimeoutItem?.cancel()
        let op = cmd.operationID
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.transportCore.inFlightCommand?.operationID == op else { return }
            self.emit("命令 op=\(op) 应答超时，放行下一条")
            self.failWaiter(forOperation: op, outcome: .timedOut)
            self.advanceQueue()
        }
        headTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    /// head 完成（收到对应应答）：失败其 waiter（若有）并放行下一条。
    private func advanceQueue() {
        headTimeoutItem?.cancel()
        headTimeoutItem = nil
        if let next = transportCore.completeHeadCommand() {
            writeCommand(next)
        }
    }

    private func failWaiter(forOperation op: UInt64, outcome: DeviceWaiterOutcome) {
        guard let rid = operationWaiters.removeValue(forKey: op),
              let completion = waiterCompletions.removeValue(forKey: rid) else { return }
        switch outcome {
        case .timedOut: completion(cachedStatus())
        default: completion(nil)
        }
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

    /// 经串行队列发一次 0x00 状态查询（不带 waiter）。
    private func requestDeviceStatus() {
        guard transportCore.isReady else { return }
        operationCounter &+= 1
        let cmd = DeviceCommand(
            operationID: operationCounter,
            deviceID: transportCore.stableDeviceID ?? "",
            generations: transportCore.currentGenerations,
            opcode: 0x00,
            payload: Data()
        )
        if let head = transportCore.enqueue(cmd) {
            writeCommand(head)
        }
    }

    private func startStatusPolling() {
        statusPollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // waiter 超时收集（querySwitchState 的兜底 fire）
            let expired = self.transportCore.collectWaiterTimeouts(now: Date())
            for (rid, outcome) in expired {
                if let completion = self.waiterCompletions.removeValue(forKey: rid) {
                    self.operationWaiters = self.operationWaiters.filter { $0.value != rid }
                    completion(outcome == .timedOut ? self.cachedStatus() : nil)
                }
                // 配置命令 waiter 超时（registry 是唯一超时 owner）。
                // 只有当超时 waiter 属于当前 head 时才推进队列，且推进后
                // 迟到 ACK 因 outcome==nil 不会二次推进（见 didUpdateValue 路由）。
                if let continuation = self.configWaiterContinuations.removeValue(forKey: rid) {
                    let isHeadWaiter = self.configOperationWaiters
                        .first(where: { $0.value == rid })
                        .map { $0.key == self.transportCore.inFlightCommand?.operationID } ?? false
                    self.configOperationWaiters = self.configOperationWaiters.filter { $0.value != rid }
                    continuation.resume(throwing: AhaKeyAgentCommandError.ackTimedOut)
                    if isHeadWaiter { self.advanceQueue() }
                }
            }
            // 无 waiter 时周期轮询真实状态（固件不主动通知拨杆变动）
            guard self.waiterCompletions.isEmpty else { return }
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
        traceCommand(.querySwitchState)
        // current-only：未 ready（未连/未协商/身份未识别）直接 nil，不注册 waiter
        guard transportCore.isReady, peripheral != nil else {
            completion(nil)
            return
        }
        operationCounter &+= 1
        let op = operationCounter
        guard let rid = transportCore.registerWaiter(operationID: op, now: Date(), timeout: timeout) else {
            completion(nil)
            return
        }
        waiterCompletions[rid] = completion
        operationWaiters[op] = rid
        let cmd = DeviceCommand(
            operationID: op,
            deviceID: transportCore.stableDeviceID ?? "",
            generations: transportCore.currentGenerations,
            opcode: 0x00,
            payload: Data()
        )
        if let head = transportCore.enqueue(cmd) {
            writeCommand(head)
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

        // 先等旧 accept worker 退出，再开新 fd，避免 fd 号复用让旧 worker accept 到新 listener。
        if !stopLegacySocketListener() {
            emit("停止旧 Unix socket listener 超时，放弃重启")
            return
        }

        do {
            try AhaKeyPaths.ensureApplicationSupportDirectory()
        } catch {
            emit("创建 socket 目录失败: \(error.localizedDescription)")
            return
        }

        if FileManager.default.fileExists(atPath: socketPath) {
            unlink(socketPath)
        }

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
        guard bindResult == 0 else { emit("bind() 失败: \(errno)"); Darwin.close(fd); return }

        guard chmod(socketPath, 0o600) == 0 else {
            emit("chmod() 失败: \(errno)")
            Darwin.close(fd)
            unlink(socketPath)
            return
        }

        let listenRC = legacyListenHookForTesting?(fd) ?? Darwin.listen(fd, 5)
        guard listenRC == 0 else {
            emit("listen() 失败: \(errno)")
            Darwin.close(fd)
            unlink(socketPath)
            return
        }

        let session: LegacyListenSession
        legacySocketLock.lock()
        legacyListenGeneration &+= 1
        session = LegacyListenSession(
            generation: legacyListenGeneration,
            listenFD: fd,
            socketPath: socketPath
        )
        session.workers.enter()
        legacySession = session
        legacyLastAcceptWorkerExited = false
        legacySocketLock.unlock()
        emit("监听 Unix socket: \(socketPath)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let capturedFD = fd
            defer { session.workers.leave() }
            while true {
                guard let self else { return }
                self.legacySocketLock.lock()
                let live = self.legacyListenGeneration == session.generation
                    && session.listenFD == capturedFD
                    && capturedFD >= 0
                self.legacySocketLock.unlock()
                guard live else { return }
                let clientFd = accept(capturedFD, nil, nil)
                if clientFd < 0 {
                    if errno == EINTR { continue }
                    return
                }
                self.legacySocketLock.lock()
                let stillLive = self.legacyListenGeneration == session.generation
                if stillLive {
                    session.clientFDs.insert(clientFd)
                    session.workers.enter()
                }
                self.legacySocketLock.unlock()
                if !stillLive {
                    Darwin.close(clientFd)
                    return
                }
                guard AhaKeyRuntimeLegacySocketIO.prepareAcceptedClient(clientFd) else {
                    self.releaseLegacyClient(clientFd, session: session)
                    continue
                }
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self else {
                        session.workers.leave()
                        return
                    }
                    self.handleClient(clientFd, session: session)
                }
            }
        }
    }

    /// 失效当前代际、关闭 listener 与该代 active clients、等待 accept+handler。
    /// 超时不得丢掉仍需回收的 owner；未启动过时为 true。
    @discardableResult
    private func stopLegacySocketListener(waitTimeout: TimeInterval = 2) -> Bool {
        legacySocketLock.lock()
        legacyListenGeneration &+= 1
        guard let session = legacySession else {
            legacyLastAcceptWorkerExited = true
            legacySocketLock.unlock()
            return true
        }
        var listenFD = session.listenFD
        session.listenFD = -1
        let clients = Array(session.clientFDs)
        session.clientFDs.removeAll()
        let path = session.socketPath
        legacySocketLock.unlock()

        if listenFD >= 0 {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            AhaKeyRuntimeLegacySocketIO.closeOnce(&listenFD)
        }
        for var clientFD in clients {
            Darwin.shutdown(clientFD, SHUT_RDWR)
            AhaKeyRuntimeLegacySocketIO.closeOnce(&clientFD)
        }

        let deadline = DispatchTime.now() + waitTimeout
        let exited = session.workers.wait(timeout: deadline) == .success

        legacySocketLock.lock()
        legacyLastAcceptWorkerExited = exited
        if exited, legacySession === session {
            unlink(path)
            legacyOwnerUnlinkCount += 1
            legacySession = nil
        }
        legacySocketLock.unlock()
        return exited
    }

    private func releaseLegacyClient(_ fd: Int32, session: LegacyListenSession) {
        legacySocketLock.lock()
        let owned = session.clientFDs.remove(fd) != nil
        legacySocketLock.unlock()
        if owned {
            var clientFD = fd
            AhaKeyRuntimeLegacySocketIO.closeOnce(&clientFD)
        }
        session.workers.leave()
    }

    var legacyListenFDForTesting: Int32 {
        legacySocketLock.lock()
        defer { legacySocketLock.unlock() }
        return legacySession?.listenFD ?? -1
    }

    var legacyListenGenerationForTesting: UInt64 {
        legacySocketLock.lock()
        defer { legacySocketLock.unlock() }
        return legacyListenGeneration
    }

    var legacyOwnerUnlinkCountForTesting: Int {
        legacySocketLock.lock()
        defer { legacySocketLock.unlock() }
        return legacyOwnerUnlinkCount
    }

    var legacyLastAcceptWorkerExitedForTesting: Bool {
        legacySocketLock.lock()
        defer { legacySocketLock.unlock() }
        return legacyLastAcceptWorkerExited
    }

    var legacyActiveClientCountForTesting: Int {
        legacySocketLock.lock()
        defer { legacySocketLock.unlock() }
        return legacySession?.clientFDs.count ?? 0
    }

    func stopLegacySocketListenerForTesting() -> Bool {
        stopLegacySocketListener()
    }

    // MARK: - Hook Socket Server

    // MARK: XPC Server

    /// 生产 XPC handshake。capabilities 与 `handleRuntimeXPCRequest` 实际处理的分支一一对应：
    /// configuration=apply/ingestResources/requestCancellation，snapshot=.snapshot，
    /// eventReplay=.events（有界回放+long-poll），diagnostics=.diagnostics。
    var runtimeServerHandshake: AhaKeyRuntimeXPCServerHandshake {
        AhaKeyRuntimeXPCServerHandshake(
            runtimeVersion: .development,
            interfaceVersion: .current,
            // R2-3：schema 广告以包 schema 为单一来源（与 AhaKeyRuntimeSnapshot 默认一致），不写裸常量。
            supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
            capabilities: [.configuration, .snapshot, .eventReplay, .diagnostics]
        )
    }

    func startXPCServer() throws {
        let serviceName = "lab.jawa.ahakeyconfig.runtime"
        let peerPolicy = AhaKeyRuntimeXPCPeerPolicy.production()
        let handshake = runtimeServerHandshake
        let endpointFactory: AhaKeyRuntimeXPCLibXPCServer.EndpointFactory = { [weak self] in
            guard let self else {
                return AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: handshake) { _ in
                    .failure(try! AhaKeyRuntimeEventCode("unsupported-request"))
                }
            }
            return AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: handshake) { [weak self] request in
                guard let self else {
                    throw AhaKeyRuntimeXPCTransportError.invalidResponse
                }
                return try await self.handleRuntimeXPCRequest(request)
            }
        }
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: serviceName,
            peerPolicy: peerPolicy,
            endpointFactory: endpointFactory
        )
        server.start()
        xpcServer = server
        emit("监听 XPC service: \(serviceName)")
    }

    /// XPC 请求处理（生产 server 与进程内集成测试共用同一路径）。
    ///
    /// 纪律（WBS-5.7 R1/R2）：
    /// - apply：store.accept durable 受理成功 → 立即返回 .operationAccepted；
    ///   事务执行经串行协调器（AhaKeyConfigurationExecutionCoordinator）排空 WAL，
    ///   Studio 断连/退出不影响；受理失败一律 .failure，绝不伪装 accepted。
    /// - snapshot：单一权威投影（BLE 设备状态 + WAL operation 摘要 + policy + 单调事件序号）。
    /// - events：有事件/断档立即返回；空批 long-poll（≤ runtimeEventsLongPollInterval），
    ///   新事件立即唤醒，超时返回空批（客户端空闲请求率 ≤ 0.5/s）。
    func handleRuntimeXPCRequest(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        switch request {
        case .apply(let package):
            if let rejection = await oledDurableWriteRejectionCode() {
                return .failure(rejection)
            }
            // 生产路径：资源必须已入 CAS（由 Studio 预上传或先前恢复）；不接受 staging/ 裸读。
            let store = try await makeRuntimeStore()
            do {
                _ = try await store.accept(package, resourceFiles: [:])
            } catch let error as AhaKeyRuntimePersistenceError {
                switch error {
                case .missingResourceFile(let identifier):
                    return .failure(try! AhaKeyRuntimeEventCode("missing-resource:\(identifier.rawValue)"))
                case .resourceDigestMismatch, .resourceByteCountMismatch, .resourceMetadataMismatch:
                    return .failure(try! AhaKeyRuntimeEventCode("resource-validation-failed"))
                case .resourceTooLarge, .resourceQuotaExceeded:
                    return .failure(try! AhaKeyRuntimeEventCode("resource-oversized"))
                default:
                    return .failure(try! AhaKeyRuntimeEventCode("accept-failed"))
                }
            }
            // durable 裁决必须 fail-closed：读失败不得合成 accepted / 重建 projector。
            let record: AhaKeyRuntimePersistedTransaction
            do {
                guard let existing = try await store.transaction(package.operationID) else {
                    return .failure(try! AhaKeyRuntimeEventCode("accept-failed"))
                }
                record = existing
            } catch {
                return .failure(try! AhaKeyRuntimeEventCode("accept-failed"))
            }
            if record.state.isTerminal {
                await publishOperationProgress(from: record)
                return .operationAccepted(package.operationID)
            }
            // durable acceptance 成功：投影立即发布 accepted，执行交给串行协调器排空 WAL。
            await beginByteProgressIfNeeded(for: package)
            await noteOperationAccepted(package)
            await configurationCoordinator.kick()
            return .operationAccepted(package.operationID)

        case .ingestResources(let items):
            if let rejection = await oledDurableWriteRejectionCode() {
                return .failure(rejection)
            }
            let store = try await makeRuntimeStore()
            do {
                try await store.ingestResources(items)
            } catch let error as AhaKeyRuntimePersistenceError {
                switch error {
                case .resourceTooLarge, .resourceQuotaExceeded:
                    return .failure(try! AhaKeyRuntimeEventCode("resource-oversized"))
                case .resourceDigestMismatch, .resourceByteCountMismatch:
                    return .failure(try! AhaKeyRuntimeEventCode("resource-validation-failed"))
                default:
                    return .failure(try! AhaKeyRuntimeEventCode("ingest-failed"))
                }
            }
            return .resourcesIngested

        case .requestCancellation(let operationID):
            return .cancellation(await cancelConfiguration(operationID: operationID))

        case .snapshot:
            return .snapshot(await projectedRuntimeSnapshot())

        case .events(let after):
            return await handleEventsRequest(after: after)

        case .diagnostics(let after):
            return await MainActor.run { self.diagnosticsResponse(after: after) }

        default:
            return .failure(try! AhaKeyRuntimeEventCode("unsupported-request"))
        }
    }

    func startHookServer() throws {
        let handler: AhaKeyRuntimeHookSocketServer.Handler = { [weak self] handshake, request in
            guard let self else {
                return .acknowledged
            }
            switch request {
            case .aiState(let state):
                Task { @MainActor [weak self] in
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

    @MainActor
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
            Task { @MainActor in
                self?.checkWatchdog()
            }
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

    @MainActor
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
    private func handleClient(_ clientFd: Int32, session: LegacyListenSession) {
        // 校验对端 UID，拒绝其他用户连接
        var peerUid: uid_t = 0
        var peerGid: gid_t = 0
        if getpeereid(clientFd, &peerUid, &peerGid) != 0 || peerUid != getuid() {
            emit("拒绝非当前用户的 socket 连接 (uid=\(peerUid))")
            releaseLegacyClient(clientFd, session: session)
            return
        }

        let line: String
        switch AhaKeyRuntimeLegacySocketIO.readLine(clientFd, timeout: 5) {
        case .line(let data):
            line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .peerClosed, .overflow, .failed:
            releaseLegacyClient(clientFd, session: session)
            return
        }

        // JSON 请求
        if let lineData = line.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
           let cmd = obj["cmd"] as? String {
            Task { @MainActor [weak self] in
                guard let self else {
                    session.workers.leave()
                    return
                }
                self.handleJsonCommand(cmd: cmd, obj: obj, clientFd: clientFd, session: session)
            }
            return // fd 在命令 handler 里最终关闭
        }

        // 旧协议：纯数字当作 state，fire-and-forget
        if let state = UInt8(line) {
            sendStateHoppingToMain(state)
        }
        releaseLegacyClient(clientFd, session: session)
    }

    /// 在 MainActor 上执行的 JSON 命令分发。回包由 `replyAndClose` 负责异步写入 + 关 fd。
    @MainActor
    private func handleJsonCommand(cmd: String, obj: [String: Any], clientFd: Int32, session: LegacyListenSession?) {
        switch cmd {
        case "state":
            if let v = obj["value"] as? Int {
                lastHookStateAt = Date()
                didLogWatchdogHold = false
                sendState(UInt8(clamping: v))
            }
            replyAndClose(clientFd, ["ok": true], session: session)

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
            replyAndClose(clientFd, ["ok": true], session: session)

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
                    self.emit(NSLocalizedString("（switchState 缺省：批准链可能仍交回手动；请确认 AhaKey Runtime 已连接键盘。）", comment: ""))
                }
                self.replyAfterLegacyHold(clientFd, body, session: session)
            }

        case "status":
            // 每次都请求真实 GPIO 状态，不能因旧缓存或虚拟模拟而返回过期档位。
            querySwitchState(timeout: 1.5) { status in
                self.replyAfterLegacyHold(
                    clientFd,
                    Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode),
                    session: session
                )
            }

        case "approval_status":
            // 给 Kimi CLI 的实时批准判断用：每次都主动向设备要当前拨杆，避免会话内沿用旧的 yolo/state。
            querySwitchState(timeout: 1.5) { status in
                self.replyAndClose(clientFd, Self.statusReply(status, cachedSwitch: self.effectiveSwitchState, cachedLight: self.cachedLightMode), session: session)
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
            replyAndClose(clientFd, [
                "ok": true,
                "switchState": effectiveSwitchState.map { Int($0) } ?? NSNull(),
                "override": userSwitchOverride.map { Int($0) } ?? NSNull(),
            ], session: session)

        case "apply_config":
            // R1: ahakey.sock 拒绝配置命令；生产入口走 XPC (AhaKeyRuntimeXPCRequest.apply)
            replyAndClose(clientFd, ["error": "apply_config rejected: configuration commands must use XPC (AhaKeyRuntimeXPCRequest.apply)"], session: session)

        case "cancel_config":
            // R1: ahakey.sock 拒绝配置命令；生产入口走 XPC (AhaKeyRuntimeXPCRequest.requestCancellation)
            replyAndClose(clientFd, ["error": "cancel_config rejected: configuration commands must use XPC (AhaKeyRuntimeXPCRequest.requestCancellation)"], session: session)

        default:
            replyAndClose(clientFd, ["error": "unknown cmd: \(cmd)"], session: session)
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

    @MainActor
    private func invalidatePendingStateReset() {
        pendingStateResetGeneration &+= 1
        pendingStateResetTask?.cancel()
        pendingStateResetTask = nil
    }

    @MainActor
    private func scheduleStateReset(to state: UInt8, afterMs: Int, reason: String) {
        pendingStateResetGeneration &+= 1
        let generation = pendingStateResetGeneration
        pendingStateResetTask?.cancel()
        pendingStateResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(afterMs) * 1_000_000)
            } catch {
                return
            }
            guard let self else { return }
            self.firePendingStateResetIfCurrent(generation: generation, to: state, reason: reason)
        }
        traceCommand(.installStateReset(state))
    }

    /// 确认仍是当前 generation 再发送：与清理同在 MainActor 临界区，过时 reset 即使已排队也无效。
    @MainActor
    private func firePendingStateResetIfCurrent(generation: UInt64, to state: UInt8, reason: String) {
        guard pendingStateResetGeneration == generation else { return }
        pendingStateResetTask = nil
        sendState(state)
        emit("自动回落灯态：\(reason)")
    }

    private func replyAfterLegacyHold(_ fd: Int32, _ dict: [String: Any], session: LegacyListenSession?) {
        if let gate = legacyReplyBeforeWriteGate {
            DispatchQueue.global(qos: .utility).async {
                gate.markAcceptedAndWaitForRelease()
                self.replyAndCloseNow(fd, dict, session: session)
                gate.markWriteFinished()
            }
            return
        }
        replyAndClose(fd, dict, session: session)
    }

    private func replyAndClose(_ fd: Int32, _ dict: [String: Any], session: LegacyListenSession?) {
        guard let session else {
            guard fd >= 0 else { return }
            DispatchQueue.global(qos: .utility).async {
                self.replyAndCloseNow(fd, dict, session: nil)
            }
            return
        }
        guard fd >= 0 else {
            releaseLegacyClient(fd, session: session)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            self.replyAndCloseNow(fd, dict, session: session)
        }
    }

    private func replyAndCloseNow(_ fd: Int32, _ dict: [String: Any], session: LegacyListenSession?) {
        defer {
            if let session {
                releaseLegacyClient(fd, session: session)
            } else if fd >= 0 {
                var clientFD = fd
                AhaKeyRuntimeLegacySocketIO.closeOnce(&clientFD)
            }
        }
        guard fd >= 0 else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return }
        var out = data
        out.append(0x0A) // \n 作为消息边界
        switch AhaKeyRuntimeLegacySocketIO.writeAll(out, to: fd) {
        case .completed, .peerClosed:
            break
        case .failed(let code):
            fputs("legacy ahakey.sock write failed errno=\(code)\n", stderr)
        }
    }

    // MARK: - Connection

    /// 跨进程 BLE 连接锁（阶段 3，flock）：发起连接前必须持有；抢不到绝对不 attach（含系统已连接外设）
    private let connectionLock = BLEConnectionLock()
    /// 锁被 GUI 占用的提示是否已记录（只记一次状态转换，重试不刷日志）
    private var didLogLockBusy = false
    /// 抢锁失败后的 15s 重试项
    private var lockRetryItem: DispatchWorkItem?

    /// 连接入口：全部决策交给 DeviceTransportCore，本类只落地动作。
    private func connectAutomatically() {
        bleLifecycle.handle(.bluetoothPoweredOn, now: Date())
    }

    /// transport 核心动作 → 生产 Adapter 落地（同一 main 生命周期边界）。
    private func performTransportActions(_ actions: [DeviceTransportAction]) {
        bleLifecycle.perform(actions, now: Date())
    }

    /// 发起连接前必须持有跨进程连接锁；被 GUI 持有时不 attach，15s 后重试（不刷日志）。
    func acquireConnectionLock() -> Bool {
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
            // 仍在等锁：只重试取锁动作，不重置连接退避
            self.performTransportActions([.acquireConnectionLock])
        }
        lockRetryItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
    }

    func emit(_ msg: String) {
        log.info("\(msg)")
        onLog?(msg)
    }
}

extension AhaKeyAgent: AhaKeyBLELifecycleAdapter.Host {
    func retrieveSystemAttached() -> [AhaKeySystemAttachedProbe.PeripheralRef] {
        AhaKeyBLELifecycleSeam.assertIsolated()
        let list = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        retrievedSystemAttached = list
        return list.map { AhaKeySystemAttachedProbe.PeripheralRef(name: $0.name, uuid: $0.identifier.uuidString) }
    }

    func connectRetrieved(uuid: String) -> Bool {
        AhaKeyBLELifecycleSeam.assertIsolated()
        guard let p = retrievedSystemAttached.first(where: { $0.identifier.uuidString == uuid }) else {
            return false
        }
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
        return true
    }

    func connectKnown(uuid uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return }
        if let p = peripheral, p.identifier == uuid {
            p.delegate = self
            central.connect(p, options: nil)
        } else if let p = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            emit("直连已知设备: \(uuidString.prefix(8))…")
            peripheral = p
            p.delegate = self
            central.connect(p, options: nil)
        } else {
            emit(NSLocalizedString("开始扫描…", comment: ""))
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func startScan() {
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func stopScan() {
        central.stopScan()
    }

    func discoverServices(uuid: String) {
        peripheral?.discoverServices([serviceUUID, deviceInfoServiceUUID])
    }

    func sendCapabilityNegotiation(uuid: String) {
        sendNegotiationQuery()
    }

    func disconnect(uuid: String) {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    func scheduleReconnect(after: TimeInterval) {
        emit(String(format: NSLocalizedString("已断开，%.0fs 后重连", comment: ""), after))
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self else { return }
            self.bleLifecycle.handle(.reconnectTimerFired, now: Date())
        }
    }
}

extension AhaKeyAgent {
    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            emit(NSLocalizedString("蓝牙就绪", comment: ""))
            connectAutomatically()
        } else {
            performTransportActions(transportCore.handle(.bluetoothUnavailable, now: Date()))
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
        // 动作由 transport 核心决策并执行（不得丢弃 handle 返回的 actions）
        let deviceID = advertisedDeviceID(from: advertisementData, name: name)
        if let deviceID {
            cacheIdentity(uuid: peripheral.identifier.uuidString, deviceID: deviceID)
        }
        performTransportActions(transportCore.handle(.discovered(uuid: peripheral.identifier.uuidString, deviceID: deviceID), now: Date()))
    }

    /// 稳定设备编号：manufacturer data 4 位编号 → 设备名后缀（对齐 Studio 的解析顺序）。
    private func advertisedDeviceID(from advertisementData: [String: Any], name: String) -> String? {
        AhaKeyDevicePresentation.advertisedIdentifier(
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        ) ?? AhaKeyDevicePresentation.nameSuffixIdentifier(name)
    }

    // MARK: - 稳定身份缓存（改名设备/系统持有路径没有广播包）

    private func cacheIdentity(uuid: String, deviceID: String) {
        let url = AhaKeyPaths.deviceIdentityCacheURL
        var map: [String: String] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            map = obj
        }
        guard map[uuid] != deviceID else { return }
        map[uuid] = deviceID
        if let data = try? JSONSerialization.data(withJSONObject: map) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func cachedIdentity(for uuid: String) -> String? {
        guard let data = try? Data(contentsOf: AhaKeyPaths.deviceIdentityCacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return obj[uuid]
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        resetOLEDNegotiationState(reason: "didConnect")
        lastUUID = peripheral.identifier
        emit("已连接: \(peripheral.name ?? "?")")
        let r = DeviceStateReducer.apply(.connected(name: peripheral.name, uuid: peripheral.identifier.uuidString),
                                         core: coreSnapshot, diagnostics: diagnosticsSnapshot)
        coreSnapshot = r.core; diagnosticsSnapshot = r.diagnostics
        var actions = transportCore.handle(.connected(uuid: peripheral.identifier.uuidString), now: Date())
        // 已知 UUID/系统已连路径无广播包：设备名后缀 → 身份缓存 → 2A25 序列号，逐级补稳定身份
        let uuid = peripheral.identifier.uuidString
        if let id = AhaKeyDevicePresentation.nameSuffixIdentifier(peripheral.name ?? "") {
            actions += transportCore.handle(.deviceIdentified(deviceID: id), now: Date())
        } else if let id = cachedIdentity(for: uuid) {
            actions += transportCore.handle(.deviceIdentified(deviceID: id), now: Date())
        }
        performTransportActions(actions)
        publishDeviceChangedIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        emit("连接失败: \(error?.localizedDescription ?? "?")")
        bleLifecycle.handle(.lookupOrConnectFailed, now: Date())
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopStatusPolling()
        commandChar = nil
        notifyChar = nil
        dataChar = nil
        self.peripheral = nil
        cachedSwitchState = nil
        cachedLightMode = nil
        resetOLEDNegotiationState(reason: "didDisconnect")
        let r = DeviceStateReducer.apply(.disconnected, core: coreSnapshot, diagnostics: diagnosticsSnapshot)
        coreSnapshot = r.core; diagnosticsSnapshot = r.diagnostics
        // 断连：核心强败全部 waiter（含当前代际），回调以 nil 收尾，队列清空
        headTimeoutItem?.cancel()
        headTimeoutItem = nil
        if !waiterCompletions.isEmpty {
            let completions = waiterCompletions
            waiterCompletions.removeAll()
            operationWaiters.removeAll()
            for (_, c) in completions { c(nil) }
        }
        // 配置事务 waiter 一并强败（WAL 里有恢复点，重连后 recovery 续跑）；
        // 断连瞬间无法补 0x9A，固件侧会话靠自身超时回收。
        activeUploadSessionID = nil
        if !configWaiterContinuations.isEmpty {
            let pending = configWaiterContinuations
            configWaiterContinuations.removeAll()
            configOperationWaiters.removeAll()
            for (_, c) in pending { c.resume(throwing: AhaKeyAgentCommandError.disconnected) }
        }
        if let dataContinuation = dataWriteContinuation {
            dataWriteContinuation = nil
            dataWriteTimeoutItem?.cancel()
            dataWriteTimeoutItem = nil
            dataContinuation.resume(throwing: AhaKeyAgentCommandError.disconnected)
        }
        emit(NSLocalizedString("连接断开", comment: ""))
        performTransportActions(transportCore.handle(.disconnected(uuid: peripheral.identifier.uuidString), now: Date()))
        publishDeviceChangedIfNeeded()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
            peripheral.discoverCharacteristics([commandCharUUID, notifyCharUUID, dataCharUUID], for: service)
        }
        if let infoService = peripheral.services?.first(where: { $0.uuid == deviceInfoServiceUUID }) {
            peripheral.discoverCharacteristics([serialNumberCharUUID], for: infoService)
        } else if error == nil {
            // 无 Device Information 服务：序列号路径不存在，直接用 UUID 兜底身份
            applyUUIDFallbackIdentityIfNeeded(peripheral)
        }
    }

    /// 无广播编号/名后缀/有效序列号时的最后身份来源（CB UUID 同机稳定）。
    /// 已识别（名后缀/缓存/真实序列号先到）时不覆盖：transport 核心本身也只认首个身份。
    private func applyUUIDFallbackIdentityIfNeeded(_ peripheral: CBPeripheral) {
        guard let id = AhaKeyDevicePresentation.uuidFallbackIdentifier(peripheral.identifier.uuidString) else { return }
        emit("无广播编号/有效序列号：使用 UUID 兜底身份 \(id)")
        cacheIdentity(uuid: peripheral.identifier.uuidString, deviceID: id)
        performTransportActions(transportCore.handle(.deviceIdentified(deviceID: id), now: Date()))
        publishDeviceChangedIfNeeded()
        if transportCore.isReady {
            emit(NSLocalizedString("current 协议协商完成，开始状态轮询", comment: ""))
            requestDeviceStatus()
            startStatusPolling()
            scheduleConfigurationRecovery()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if service.uuid == deviceInfoServiceUUID {
            for char in service.characteristics ?? [] where char.uuid == serialNumberCharUUID {
                peripheral.readValue(for: char)
            }
            return
        }
        for char in service.characteristics ?? [] {
            if char.uuid == commandCharUUID {
                commandChar = char
                emit(NSLocalizedString("命令通道就绪", comment: ""))
            } else if char.uuid == notifyCharUUID {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
                emit(NSLocalizedString("通知通道已订阅", comment: ""))
            } else if char.uuid == dataCharUUID {
                dataChar = char
                emit(NSLocalizedString("数据通道就绪", comment: ""))
            }
        }
        let source = OLEDNotifySource(
            generation: oledConnectionGeneration,
            peripheralID: peripheral.identifier
        )
        if let notifyChar {
            bindOLEDNotifySource(source, to: notifyChar)
        }
        if let commandChar {
            bindOLEDNotifySource(source, to: commandChar)
        }
        // 两个特征都就绪 → transport 核心推进到协商（current-only：协商成功才允许业务写入与轮询）
        if commandChar != nil, notifyChar != nil {
            performTransportActions(transportCore.handle(.servicesReady(uuid: peripheral.identifier.uuidString), now: Date()))
        }
    }

    // MARK: - 0x99 能力协商（current-only）

    /// 新连接/断连原子撤销 OLED 协商事实，使下一连接在密封前不可写。
    private func resetOLEDNegotiationState(reason: String) {
        oledConnectionGeneration &+= 1
        negotiatedOLEDContext = nil
        negotiatedCapabilities = nil
        sawMalformedCapabilityFrame = false
        oledLegacyProbePhase = .idle
        legacyProbeFirmwareMainVersion = nil
        negotiationAttempts = 0
        awaitingCapabilityResponse = false
        oledInFlightRequest = nil
        negotiationTimeoutItem?.cancel()
        negotiationTimeoutItem = nil
        emit("OLED 协商已随连接代际撤销（\(reason)，gen=\(oledConnectionGeneration)）")
    }

    private func currentOLEDPeripheralID() -> UUID? {
        executionTestHooks?.oledNotifyPeripheralID ?? peripheral?.identifier
    }

    /// 把冻结 source 一次性绑到本次 callback 对象。已有不同代身份则标 ambiguous，不得覆写为新代。
    private func bindOLEDNotifySource(_ source: OLEDNotifySource, to object: AnyObject) {
        oledNotifyBoundIdentities.add(object)
        if let binding = oledNotifyCallbackBinding(attachedTo: object) {
            switch binding.state {
            case .source(let existing) where existing == source:
                return
            case .source, .ambiguous, .invalid:
                binding.state = .ambiguous
            }
            return
        }
        objc_setAssociatedObject(
            object,
            &oledNotifyCallbackBindingAssociationKey,
            OLEDNotifyCallbackBinding(state: .source(source)),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func invalidateOLEDNotifyCallbackIdentity(_ object: AnyObject) {
        oledNotifyCallbackBinding(attachedTo: object)?.state = .invalid
    }

    private func oledNotifyCallbackBinding(attachedTo object: AnyObject) -> OLEDNotifyCallbackBinding? {
        objc_getAssociatedObject(object, &oledNotifyCallbackBindingAssociationKey) as? OLEDNotifyCallbackBinding
    }

    /// 只信本次 callback 对象上的冻结 source；未知、ambiguous、invalid 均为 nil。
    private func resolveOLEDNotifySource(attachedTo object: AnyObject) -> OLEDNotifySource? {
        guard let binding = oledNotifyCallbackBinding(attachedTo: object) else { return nil }
        if case .source(let source) = binding.state {
            return source
        }
        return nil
    }

    private func noteOLEDInFlight() {
        guard let peripheralID = currentOLEDPeripheralID() else { return }
        oledInFlightRequest = OLEDNotifySource(
            generation: oledConnectionGeneration,
            peripheralID: peripheralID
        )
    }

    /// 解析或改协商状态之前：source 必须来自回调自身的 generation/peripheral，不得用当前请求反推。
    private func shouldAcceptOLEDResponse(source: OLEDNotifySource) -> Bool {
        guard let inFlight = oledInFlightRequest else { return false }
        guard source.generation == inFlight.generation else { return false }
        guard source.peripheralID == inFlight.peripheralID else { return false }
        guard isCurrentOLEDGeneration(source.generation) else { return false }
        guard let current = currentOLEDPeripheralID(), current == source.peripheralID else { return false }
        return true
    }

    private func isCurrentOLEDGeneration(_ generation: UInt64) -> Bool {
        generation == oledConnectionGeneration
    }

    private func scheduleOLEDNegotiationTimeout(_ handler: @escaping (AhaKeyAgent) -> Void) {
        let generation = oledConnectionGeneration
        negotiationTimeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrentOLEDGeneration(generation) else { return }
            handler(self)
        }
        negotiationTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    /// 发送 0x99 能力查询；最多 3 次，每次 2s 超时（对齐 Shared/AhaKeyProtocolNegotiation）。
    private func sendNegotiationQuery() {
        guard let commandChar, let peripheral else { return }
        negotiationAttempts += 1
        awaitingCapabilityResponse = true
        noteOLEDInFlight()
        let frame = Data(header + [0x99] + trailer)
        let wt: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(frame, for: commandChar, type: wt)
        emit("→ 0x99 能力查询（第 \(negotiationAttempts) 次）")
        scheduleOLEDNegotiationTimeout { $0.negotiationTimedOut() }
    }

    private func negotiationTimedOut() {
        guard awaitingCapabilityResponse else { return }
        awaitingCapabilityResponse = false
        if negotiationAttempts < 3 {
            emit("0x99 超时，重试")
            sendNegotiationQuery()
        } else if sawMalformedCapabilityFrame {
            emit("0x99 畸形应答：拒绝猜测协议，保持只读")
            finishOLEDNegotiation(.malformedResponse)
        } else {
            emit("0x99 三次无应答：探测 firmware v1 与 0x94 任务图能力")
            beginLegacyOLEDProbe()
        }
    }

    /// 0x99 应答帧：AA BB 99 [payload≥14B] CC DD
    private func handleCapabilityResponse(_ data: Data, source: OLEDNotifySource) {
        guard shouldAcceptOLEDResponse(source: source) else { return }
        guard awaitingCapabilityResponse else { return }
        oledInFlightRequest = nil
        awaitingCapabilityResponse = false
        negotiationTimeoutItem?.cancel()
        negotiationTimeoutItem = nil
        // 帧格式与 AhaKeyResponseParser 一致：AA BB [cmd] [status] [payload] CC DD
        let payload = data.dropFirst(4).dropLast(2)
        emit("← 0x99 原始应答: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        guard let caps = AhaKeyFirmwareCapabilities.parse(Data(payload)) else {
            sawMalformedCapabilityFrame = true
            emit("0x99 应答无法解析，不按 Standard 回退")
            if negotiationAttempts < 3 {
                sendNegotiationQuery()
            } else {
                finishOLEDNegotiation(.malformedResponse)
            }
            return
        }
        let mode = AhaKeyProtocolNegotiation.mode(forCapabilities: caps)
        negotiatedCapabilities = caps
        negotiatedOLEDContext = .parsed(caps)
        emit("← 0x99 能力帧：protocol v\(caps.protocolVersion)，mode=\(mode)")
        if caps.flags & AhaKeyFirmwareCapabilities.factoryAssetsFlag != 0, payload.count == 14 {
            emit("← 0x99 compact factory：primary 0..<\(caps.userSlotLimit)，factory reserved \(caps.factorySlotBase)，reclaim \(caps.reclaimSlotBase)..<\(caps.reclaimSlotLimit)")
        }
        let uuid = peripheral?.identifier.uuidString ?? ""
        performTransportActions(transportCore.handle(.negotiationFinished(uuid: uuid, mode: mode), now: Date()))
        publishDeviceChangedIfNeeded()
        if transportCore.isReady {
            emit(NSLocalizedString("current 协议协商完成，开始状态轮询", comment: ""))
            requestDeviceStatus()
            startStatusPolling()
            scheduleConfigurationRecovery()
        } else if mode == .current {
            emit("协议 v3 已确认，等待稳定设备身份（广播编号或 2A25 序列号）…")
        } else {
            emit("协议 mode=\(mode) 非 current，保持连接但不做业务写入")
        }
    }

    private func sendDirectCommandFrame(_ opcode: UInt8, payload: [UInt8] = []) {
        guard let commandChar, let peripheral else { return }
        noteOLEDInFlight()
        let frame = Data(header + [opcode] + payload + trailer)
        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(frame, for: commandChar, type: writeType)
    }

    private func beginLegacyOLEDProbe() {
        oledLegacyProbePhase = .awaitingFirmwareVersion
        legacyProbeFirmwareMainVersion = nil
        sendDirectCommandFrame(0x00)
        emit("→ 0x00 固件版本探测（no-0x99 Standard 路径）")
        scheduleOLEDNegotiationTimeout { $0.legacyOLEDProbeTimedOut() }
    }

    private func legacyOLEDProbeTimedOut() {
        switch oledLegacyProbePhase {
        case .idle:
            return
        case .awaitingFirmwareVersion:
            emit("0x00 探测超时：未知固件，拒绝写入")
            finishOLEDNegotiation(
                AhaKeyOLEDLegacyProbe.negotiationState(firmwareMainVersion: nil, taskPicture: nil)
            )
        case .awaitingTaskPicture:
            emit("0x94 探测超时：拒绝把未知命令当成 Standard")
            finishOLEDNegotiation(
                AhaKeyOLEDLegacyProbe.negotiationState(
                    firmwareMainVersion: legacyProbeFirmwareMainVersion,
                    taskPicture: nil
                )
            )
        }
    }

    private func handleLegacyFirmwareProbeResponse(_ data: Data, source: OLEDNotifySource) {
        guard shouldAcceptOLEDResponse(source: source) else { return }
        guard oledLegacyProbePhase == .awaitingFirmwareVersion else { return }
        oledInFlightRequest = nil
        negotiationTimeoutItem?.cancel()
        negotiationTimeoutItem = nil
        let status = Self.parseDeviceStatus(data)
        let main = status?.firmwareMain
        legacyProbeFirmwareMainVersion = main
        emit("← 0x00 探测 firmwareMain=\(main.map(String.init) ?? "nil")")
        guard main == 1 else {
            finishOLEDNegotiation(
                AhaKeyOLEDLegacyProbe.negotiationState(firmwareMainVersion: main, taskPicture: nil)
            )
            return
        }
        oledLegacyProbePhase = .awaitingTaskPicture
        sendDirectCommandFrame(0x94, payload: [
            AhaKeyLegacyTaskPictureProbe.probeMode,
            AhaKeyLegacyTaskPictureProbe.probeState,
        ])
        emit("→ 0x94 任务图实探（mode=0 state=done）")
        scheduleOLEDNegotiationTimeout { $0.legacyOLEDProbeTimedOut() }
    }

    private func handleLegacyTaskPictureProbeResponse(_ data: Data, source: OLEDNotifySource) {
        guard shouldAcceptOLEDResponse(source: source) else { return }
        guard oledLegacyProbePhase == .awaitingTaskPicture else { return }
        oledInFlightRequest = nil
        negotiationTimeoutItem?.cancel()
        negotiationTimeoutItem = nil
        let classified = AhaKeyLegacyTaskPictureProbe.classify(frame: data)
        emit("← 0x94 实探结果 \(String(describing: classified))")
        finishOLEDNegotiation(
            AhaKeyOLEDLegacyProbe.negotiationState(
                firmwareMainVersion: legacyProbeFirmwareMainVersion,
                taskPicture: classified
            )
        )
    }

    private func finishOLEDNegotiation(_ state: AhaKeyReleaseNegotiationState) {
        oledLegacyProbePhase = .idle
        awaitingCapabilityResponse = false
        oledInFlightRequest = nil
        negotiationTimeoutItem?.cancel()
        negotiationTimeoutItem = nil
        let context = AhaKeyOLEDCompatibilityContext.make(state)
        negotiatedOLEDContext = context
        let mode = context.protocolMode
        // DeviceTransportCore 仍 current-only ready；Standard 不得伪装 .current。
        _ = transportCore.handle(.negotiationFinished(
            uuid: peripheral?.identifier.uuidString ?? "", mode: mode
        ), now: Date())
        publishDeviceChangedIfNeeded()
        if transportCore.isReady {
            emit(NSLocalizedString("current 协议协商完成，开始状态轮询", comment: ""))
            requestDeviceStatus()
            startStatusPolling()
            scheduleConfigurationRecovery()
        } else if context.allowsIngestAndApply {
            emit("OLED 兼容路径 \(String(describing: context.profile)) 已确认；transport 保持非 current ready")
            scheduleConfigurationRecovery()
        } else {
            emit("OLED 兼容路径 unsupported，保持连接但不做图片写入")
        }
    }

    /// 生产 notify 与测试 seam 共用：按本次 callback 对象解析冻结 source，再分发。
    private func ingestOLEDNegotiationNotify(_ data: Data, callbackIdentity: AnyObject) {
        guard let source = resolveOLEDNotifySource(attachedTo: callbackIdentity) else { return }
        _ = consumeOLEDNegotiationNotify(data, source: source)
    }

    /// 生产 notify 与测试 seam 共用：source 必须是订阅时冻结的身份，再按 opcode/phase 分发。
    @discardableResult
    private func consumeOLEDNegotiationNotify(_ data: Data, source: OLEDNotifySource) -> Bool {
        if data.count >= 5, data[0] == 0xAA, data[1] == 0xBB, data[2] == 0x99 {
            handleCapabilityResponse(data, source: source)
            return true
        }
        if oledLegacyProbePhase == .awaitingTaskPicture,
           data.count >= 5, data[0] == 0xAA, data[1] == 0xBB, data[2] == 0x94 {
            handleLegacyTaskPictureProbeResponse(data, source: source)
            return true
        }
        if oledLegacyProbePhase == .awaitingFirmwareVersion,
           data.count >= 5, data[0] == 0xAA, data[1] == 0xBB, data[2] == 0x00 {
            handleLegacyFirmwareProbeResponse(data, source: source)
            return true
        }
        return false
    }

    private func isOLEDNegotiationNotifyFrame(_ data: Data) -> Bool {
        guard data.count >= 5, data[0] == 0xAA, data[1] == 0xBB else { return false }
        if data[2] == 0x99 { return true }
        if oledLegacyProbePhase == .awaitingTaskPicture, data[2] == 0x94 { return true }
        if oledLegacyProbePhase == .awaitingFirmwareVersion, data[2] == 0x00 { return true }
        return false
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // 2A25 序列号 → 稳定设备身份（改名设备的关键路径）
        if characteristic.uuid == serialNumberCharUUID {
            let serial = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let serial, let shortID = AhaKeyDevicePresentation.shortIdentifier(from: serial) {
                emit("← 2A25 序列号 \(serial) → 设备编号 \(shortID)")
                performTransportActions(transportCore.handle(.deviceIdentified(deviceID: shortID), now: Date()))
                publishDeviceChangedIfNeeded()
                if transportCore.isReady {
                    emit(NSLocalizedString("current 协议协商完成，开始状态轮询", comment: ""))
                    requestDeviceStatus()
                    startStatusPolling()
                    scheduleConfigurationRecovery()
                }
            } else {
                // 占位符序列号（如 Rhino 固件硬编码 "Serial Number"）：UUID 兜底
                emit("← 2A25 序列号 \(serial ?? "< unreadable >") 非编号格式，启用 UUID 兜底身份")
                applyUUIDFallbackIdentityIfNeeded(peripheral)
            }
            return
        }
        guard characteristic.uuid == commandCharUUID || characteristic.uuid == notifyCharUUID,
              let data = characteristic.value else { return }
        if isOLEDNegotiationNotifyFrame(data) {
            // 只信本次 characteristic 上的冻结身份，不得用可复用 peripheral 的当前关联兜底。
            ingestOLEDNegotiationNotify(data, callbackIdentity: characteristic)
            return
        }
        // 0x81 图片写入确认（数据通道收尾；session 必须匹配当前在途会话）
        if data.count >= 6, data[0] == 0xAA, data[1] == 0xBB, data[2] == AhaKeyWireFrameBuilder.cmdWriteResult,
           data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD {
            handlePictureWriteResult(status: data[3], payload: data[4 ..< data.count - 2])
            return
        }
        // 配置事务命令 ACK（sequencer head 五元匹配；0x00/0x90 走各自既有路径）
        if data.count >= 6, data[0] == 0xAA, data[1] == 0xBB,
           data[data.count - 2] == 0xCC, data[data.count - 1] == 0xDD,
           data[2] != 0x00, data[2] != 0x90,
           let head = transportCore.inFlightCommand, head.opcode == data[2],
           let rid = configOperationWaiters[head.operationID] {
            let outcome = transportCore.resolveWaiter(
                requestID: rid, operationID: head.operationID,
                payload: Data(data[3 ..< data.count - 2])
            )
            // 只有五元真正匹配才完成 waiter 并推进队列；迟到 ACK（outcome==nil）
            // 既不续 continuation 也不 advanceQueue——head 推进的唯一时机是
            // 「waiter 完成」或「head 自己的 waiter 超时」，两者互斥。
            if outcome != nil {
                configOperationWaiters.removeValue(forKey: head.operationID)
                if let continuation = configWaiterContinuations.removeValue(forKey: rid) {
                    continuation.resume(returning: (status: data[3], payload: Data(data[4 ..< data.count - 2])))
                }
                advanceQueue()
            }
            return
        }
        if let acknowledgement = StateCommandAcknowledgement.parse(data) {
            if acknowledgement.resultCode == 0 {
                emit("← 固件已应用 LED/OLED 状态命令 0x90")
            } else {
                emit("← 固件拒绝 LED/OLED 状态命令 0x90，错误码 \(acknowledgement.resultCode)")
            }
            // 0x90 ACK 完成 head，放行下一条
            if transportCore.inFlightCommand?.opcode == 0x90 {
                advanceQueue()
            }
            return
        }
        guard let status = MainActor.assumeIsolated({ self.consumeDeviceStatus(data) }) else { return }

        // 0x00 应答路由到 head 命令的 waiter（五元绑定；代际不符=迟到回包，nil 收尾）
        if let head = transportCore.inFlightCommand, head.opcode == 0x00,
           let rid = operationWaiters.removeValue(forKey: head.operationID) {
            let outcome = transportCore.resolveWaiter(requestID: rid, operationID: head.operationID, payload: data)
            if let completion = waiterCompletions.removeValue(forKey: rid) {
                completion(outcome != nil ? status : nil)
            }
        }
        if transportCore.inFlightCommand?.opcode == 0x00 {
            advanceQueue()
        }
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

    /// 生产 0x00 回包与测试注入的唯一消费入口（parse → reducer → cache/log/publish）。
    @MainActor
    @discardableResult
    private func consumeDeviceStatus(_ data: Data) -> AgentDeviceStatus? {
        guard let status = Self.parseDeviceStatus(data) else { return nil }
        let coreBefore = coreSnapshot
        let reduced = DeviceStateReducer.apply(
            .fullStatus(battery: status.battery, firmwareMain: status.firmwareMain,
                        firmwareSub: status.firmwareSub, workMode: status.workMode,
                        lightMode: status.lightMode, switchState: status.switchState,
                        brightness: -1, activePictureSet: -1),
            core: coreSnapshot, diagnostics: diagnosticsSnapshot
        )
        coreSnapshot = reduced.core
        diagnosticsSnapshot = reduced.diagnostics

        let hardwareSwitchState = UInt8(clamping: reduced.core.switchState)
        let previousSwitchState = cachedSwitchState
        cachedSwitchState = hardwareSwitchState
        cachedLightMode = UInt8(clamping: reduced.core.lightMode)
        if userSwitchOverride != nil {
            userSwitchOverride = nil
            userSwitchOverrideTimeout?.cancel()
            userSwitchOverrideTimeout = nil
            emit("← 收到真实拨杆状态 \(hardwareSwitchState)，已清除虚拟拨杆覆盖")
        }
        if previousSwitchState != hardwareSwitchState {
            KimiTUIAdapter.applyModeIfNeeded(for: Int(hardwareSwitchState))
        }
        if reduced.core != coreBefore {
            emit("← status battery=\(status.battery) light=\(status.lightMode) switch=\(status.switchState)")
        }
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
        publishDeviceChangedOnMain()
        return status
    }

    // MARK: - 配置事务恢复与程序执行（WBS-5.6 切片 5b）

    /// ready 后捞起 WAL 里未竟事务续跑（断线/重启恢复入口）。
    /// R2-2：统一走串行协调器 kick——与新受理共用同一 worker，互不插队、不并行。
    private func scheduleConfigurationRecovery() {
        Task { await configurationCoordinator.kick() }
    }

    // MARK: 生产受理 / 取消入口（WBS-5.6 R7；WBS-5.7 R1 改为 durable accept + 异步执行）

    private func resolvedOLEDContext() -> AhaKeyOLEDCompatibilityContext {
        if let override = executionTestHooks?.oledContext {
            return override
        }
        if let capabilities = executionTestHooks?.capabilities {
            return .parsed(capabilities)
        }
        return negotiatedOLEDContext ?? .make(.negotiating)
    }

    /// XPC ingest/apply 与 step/command/chunk 共用同一 ready 门；未就绪不得构造 store 或写 CAS/WAL。
    private func oledDurableWriteRejectionCode() async -> AhaKeyRuntimeEventCode? {
        let (context, ready) = await MainActor.run { () -> (AhaKeyOLEDCompatibilityContext, Bool) in
            (self.resolvedOLEDContext(), self.configurationWriteIsReady())
        }
        guard ready else {
            let code = context.allowsIngestAndApply ? "not-ready" : "unsupported-protocol"
            return try! AhaKeyRuntimeEventCode(code)
        }
        return nil
    }

    /// Store 构造：默认生产目录；测试经 executionTestHooks.storeDirectory 重定向到临时目录。
    /// 缓存收敛进 AhaKeyAgentRuntimeStoreCache（actor）：同一目录复用单实例，
    /// 多 XPC session 并发访问由 actor 隔离（R2-2）。
    private func makeRuntimeStore() async throws -> AhaKeyRuntimePersistentStore {
        let directory = executionTestHooks?.storeDirectory ?? AhaKeyPaths.runtimeStoreDirectory
        return try await runtimeStoreCache.store(for: directory)
    }

    /// 生产受理入口：新配置包（current-only）。
    /// R2-2：串行性由 AhaKeyConfigurationExecutionCoordinator 保证（单 worker），此处不再单飞闸门；
    /// 仅由协调器 worker 调用（XPC handler 不直接执行）。
    func applyConfigurationPackage(
        _ package: AhaKeyConfigurationPackage,
        resourceFiles: [AhaKeyResourceIdentifier: URL]
    ) async throws -> AhaKeyRuntimeOperationState {
        let (context, ready) = await MainActor.run { () -> (AhaKeyOLEDCompatibilityContext, Bool) in
            (self.resolvedOLEDContext(), self.configurationWriteIsReady())
        }
        guard context.allowsIngestAndApply, ready else {
            throw AhaKeyAgentCommandError.disconnected
        }
        let store = try await makeRuntimeStore()
        let state = try await runConfigurationTransaction(
            package: package, resourceFiles: resourceFiles, store: store, context: context
        )
        emit("配置事务 \(package.operationID.rawValue.uuidString.prefix(8))… 受理结果：\(state.rawValue)")
        return state
    }

    /// 生产取消入口：落 cancellationRequested；执行器在步间安全点结算。
    /// 返回真实受理结果（notFound / alreadyFinished / requested），绝不伪装。
    @discardableResult
    func cancelConfiguration(operationID: AhaKeyRuntimeOperationID) async -> AhaKeyRuntimeCancellationDisposition {
        do {
            let store = try await makeRuntimeStore()
            guard let record = try await store.transaction(operationID) else { return .notFound }
            guard !record.state.isTerminal else { return .alreadyFinished }
            do {
                try await AhaKeyConfigurationTransactionRunner(store: store).requestCancel(operationID: operationID)
            } catch AhaKeyConfigurationCancelError.refusedWhileActive {
                emit("配置事务 \(operationID.rawValue.uuidString.prefix(8))… 拒绝取消（page operation 仍可恢复）")
                return .refused
            }
            emit("配置事务 \(operationID.rawValue.uuidString.prefix(8))… 已请求取消")
            await publishOperationProgress(operationID: operationID)
            await configurationCoordinator.kick()
            return .requested
        } catch {
            emit("配置事务取消失败：\(error.localizedDescription)")
            return .notFound
        }
    }

    /// R4：纯 WAL 取消结算。不得发 BLE，可在 paused 队首之前把排队取消推到终态。
    private func settleQueuedCancellations() async {
        guard let store = try? await makeRuntimeStore(),
              let candidates = try? await store.recoveryCandidates() else { return }
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        for candidate in candidates where candidate.state == .cancellationRequested {
            if let settled = try? await runner.settleCancellation(operationID: candidate.operationID) {
                emit("配置事务 \(candidate.operationID.rawValue.uuidString.prefix(8))… 排队取消已结算：\(settled.rawValue)")
                await publishOperationProgress(operationID: candidate.operationID)
            }
        }
    }

    /// 决策-执行循环（恢复与新受理共用；transport 经 AgentProgramTransport 落到 BLE）。
    private func runConfigurationTransaction(
        package: AhaKeyConfigurationPackage,
        resourceFiles: [AhaKeyResourceIdentifier: URL],
        store: AhaKeyRuntimePersistentStore,
        context: AhaKeyOLEDCompatibilityContext
    ) async throws -> AhaKeyRuntimeOperationState {
        let runner = AhaKeyConfigurationTransactionRunner(store: store)
        return try await withConfigurationTransportWindow {
            try await self.runConfigurationProgram(
                runner: runner, package: package, resourceFiles: resourceFiles,
                store: store, context: context
            )
        }
    }

    /// 生产事务窗口配对：成功、抛错、取消都走同一条 begin/end。
    private func withConfigurationTransportWindow<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        await MainActor.run {
            if self.configurationTransportWindow.begin() {
                self.emit("配置事务窗口开启，暂缓 0x90")
            }
            self.traceCommand(.transportWindowBegin)
        }
        do {
            let value = try await work()
            await MainActor.run { self.endConfigurationTransportWindow() }
            return value
        } catch {
            await MainActor.run { self.endConfigurationTransportWindow() }
            throw error
        }
    }

    /// 事务窗口收尾：计数归零时补发窗口内被暂缓的最后一次灯态。
    @MainActor
    private func endConfigurationTransportWindow() {
        traceCommand(.transportWindowEnd)
        switch configurationTransportWindow.end() {
        case .stillOpen:
            break
        case .idle:
            break
        case .replayAndLog(let deferred):
            emit("配置事务窗口关闭，补发 LED 状态 \(deferred)")
            sendState(deferred)
        case .unmatchedEnd:
            emit("配置事务窗口 end 无匹配 begin，忽略此次收尾")
        }
    }

    private func runConfigurationProgram(
        runner: AhaKeyConfigurationTransactionRunner,
        package: AhaKeyConfigurationPackage,
        resourceFiles: [AhaKeyResourceIdentifier: URL],
        store: AhaKeyRuntimePersistentStore,
        context: AhaKeyOLEDCompatibilityContext
    ) async throws -> AhaKeyRuntimeOperationState {
        try await runner.run(
            package: package,
            resourceFiles: resourceFiles,
            context: context,
            release: releaseProjection(for: context),
            pagePreconditions: await pageExecutionPreconditions(
                package: package, context: context, store: store
            )
        ) { [weak self] step in
            guard let self else { return .retryableFailure }
            await MainActor.run {
                self.noteEnteredConfigurationStep(operationID: package.operationID, stepID: step)
            }
            if let hook = await MainActor.run(body: { self.executionTestHooks?.afterEnteringConfigurationStep }) {
                await hook(step)
            }
            let result: AhaKeyConfigurationStepResult
            if let override = self.executionTestHooks?.stepExecutor {
                // 集成测试 seam：替代 BLE 步骤执行（可观察 WAL 取消态）。
                result = await override(step)
            } else {
                result = await self.executeConfigurationStep(
                    step, package: package, store: store, context: context
                )
            }
            // 每步后从 WAL 读进度并发布 operationChanged（终态由外层再发布一次）。
            await self.publishOperationProgress(operationID: package.operationID)
            return result
        }
    }

    private func pageExecutionPreconditions(
        package: AhaKeyConfigurationPackage,
        context: AhaKeyOLEDCompatibilityContext,
        store: AhaKeyRuntimePersistentStore
    ) async -> AhaKeyRuntimePageExecutionPreconditions? {
        guard package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion,
              package.pageOperation != nil else { return nil }
        let deviceID = await MainActor.run { () -> AhaKeyRuntimeDeviceID? in
            if let simulated = self.executionTestHooks?.simulatedDevice?.id {
                return simulated
            }
            if let stable = self.executionTestHooks?.stableDeviceID ?? self.transportCore.stableDeviceID,
               let parsed = try? AhaKeyRuntimeDeviceID(stable) {
                return parsed
            }
            return nil
        }
        guard let deviceID else { return nil }
        let confirmed = (try? await store.confirmedSteps(for: package.operationID)) ?? []
        let plan = pagePlanForWriteFact(package: package, userSlotLimit: context.layout.userSlotLimit)
        let hasDeviceWrites = AhaKeyRuntimePageSemantic.hasDeviceWrites(confirmed: confirmed, plan: plan)
        let live = try? await store.authoritativeObjectFingerprint(for: deviceID)
        if !hasDeviceWrites, live == nil {
            return nil
        }
        return AhaKeyRuntimePageExecutionPreconditions(
            deviceID: deviceID,
            profile: context.profile,
            baseObjectFingerprint: live
        )
    }

    private func pagePlanForWriteFact(
        package: AhaKeyConfigurationPackage,
        userSlotLimit: Int
    ) -> AhaKeyRuntimePageExecutionPlan? {
        if let plan = try? AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: userSlotLimit
        ) {
            return plan
        }
        return try? AhaKeyRuntimePageSemantic.executionPlan(
            package: package,
            userSlotLimit: AhaKeyOLEDCompatibilityContext.standardUserSlotLimit
        )
    }

    private func releaseProjection(
        for context: AhaKeyOLEDCompatibilityContext
    ) -> AhaKeyReleaseFeatureProjection {
        executionTestHooks?.release
            ?? AhaKeyReleaseFeaturePolicy.current.projection(context.negotiation)
    }

    /// 执行单个 WAL 步骤：映射为线协议程序并经 BLE 执行。
    private func executeConfigurationStep(
        _ step: AhaKeyRuntimeStepIdentifier,
        package: AhaKeyConfigurationPackage,
        store: AhaKeyRuntimePersistentStore,
        context: AhaKeyOLEDCompatibilityContext
    ) async -> AhaKeyConfigurationStepResult {
        let bleReady = await MainActor.run { self.configurationWriteIsReady() }
        guard bleReady else {
            return .failure(.init(
                retryable: true,
                messageCode: .configurationDisconnected,
                context: .init(failedStepID: step)
            ))
        }
        if package.schemaVersion == AhaKeyConfigurationPackage.pageScopedSchemaVersion {
            return await executePageScopedStep(
                step, package: package, store: store, context: context
            )
        }
        guard let desired = try? AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration) else {
            return .failure(.init(
                retryable: false,
                messageCode: .configurationEncodingFailed,
                context: .init(failedStepID: step)
            ))
        }
        let release = releaseProjection(for: context)
        let planning = AhaKeyConfigurationPlanner.plan(
            desired: desired, resources: package.resources,
            context: context, release: release
        )
        guard case .success(let plan) = planning,
              let program = AhaKeyConfigurationStepMapper.program(
                  for: step, desired: desired, plan: plan,
                  resources: package.resources, context: context,
                  release: release
              ) else {
            return .failure(.init(
                retryable: false,
                messageCode: .configurationPlanRejected,
                context: .init(failedStepID: step)
            ))
        }
        let transport = AgentProgramTransport(
            agent: self, store: store, operationID: package.operationID, stepID: step
        )
        return await executeDeviceProgram(program, step: step, transport: transport)
    }

    private func executePageScopedStep(
        _ step: AhaKeyRuntimeStepIdentifier,
        package: AhaKeyConfigurationPackage,
        store: AhaKeyRuntimePersistentStore,
        context: AhaKeyOLEDCompatibilityContext
    ) async -> AhaKeyConfigurationStepResult {
        let pagePlan: AhaKeyRuntimePageExecutionPlan
        do {
            pagePlan = try AhaKeyRuntimePageSemantic.executionPlan(
                package: package,
                userSlotLimit: context.layout.userSlotLimit
            )
        } catch {
            return .failure(.init(
                retryable: false,
                messageCode: .configurationPlanRejected,
                context: .init(failedStepID: step)
            ))
        }
        guard let mapped = pagePlan.step(for: step) else {
            return .failure(.init(
                retryable: false,
                messageCode: .configurationPlanRejected,
                context: .init(failedStepID: step)
            ))
        }
        if mapped.program.isEmpty {
            return .success
        }
        let transport = AgentProgramTransport(
            agent: self, store: store, operationID: package.operationID, stepID: step
        )
        return await executeDeviceProgram(mapped.program, step: step, transport: transport)
    }

    private func executeDeviceProgram(
        _ program: [AhaKeyDeviceProgramStep],
        step: AhaKeyRuntimeStepIdentifier,
        transport: AgentProgramTransport
    ) async -> AhaKeyConfigurationStepResult {
        do {
            try await AhaKeyDeviceProgramExecutor.execute(program, over: transport)
            return .success
        } catch AhaKeyDeviceProgramExecutionError.cancelled {
            emit("配置步骤 \(step.rawValue) 可重试失败：cancelled")
            return .failure(.init(
                retryable: true,
                messageCode: nil,
                context: .init(failedStepID: step)
            ))
        } catch let error as AhaKeyAgentCommandError {
            emit("配置步骤 \(step.rawValue) 失败：\(error)")
            return mapConfigurationCommandError(error, step: step)
        } catch let error as AhaKeyOLEDFrameEncoderCore.EncodingError {
            emit("配置步骤 \(step.rawValue) 编码失败：\(error)")
            return .failure(.init(
                retryable: false,
                messageCode: .configurationEncodingFailed,
                context: .init(failedStepID: step)
            ))
        } catch {
            emit("配置步骤 \(step.rawValue) 可重试失败：\(error)")
            return .failure(.init(
                retryable: true,
                messageCode: nil,
                context: .init(failedStepID: step)
            ))
        }
    }

    private func mapConfigurationCommandError(
        _ error: AhaKeyAgentCommandError,
        step: AhaKeyRuntimeStepIdentifier
    ) -> AhaKeyConfigurationStepResult {
        switch error {
        case .deviceRejected(let opcode, let status):
            return .failure(.init(
                retryable: false,
                messageCode: .configurationDeviceRejected,
                context: .init(failedStepID: step, opcode: opcode, deviceStatus: status)
            ))
        case .resourceMissing:
            return .failure(.init(
                retryable: false,
                messageCode: .configurationResourceMissing,
                context: .init(failedStepID: step)
            ))
        case .malformedFrame:
            return .failure(.init(
                retryable: false,
                messageCode: .configurationMalformedFrame,
                context: .init(failedStepID: step)
            ))
        case .disconnected:
            return .failure(.init(
                retryable: true,
                messageCode: .configurationDisconnected,
                context: .init(failedStepID: step)
            ))
        case .ackTimedOut:
            return .failure(.init(
                retryable: true,
                messageCode: .configurationCommandTimeout,
                context: .init(failedStepID: step)
            ))
        case .cancelled, .busy:
            return .failure(.init(
                retryable: true,
                messageCode: nil,
                context: .init(failedStepID: step)
            ))
        }
    }

    @MainActor
    fileprivate func programTransportIsDisconnected() -> Bool {
        !configurationWriteIsReady()
    }

    /// 受理、step、command、chunk 共用：current 仍要 current-ready；Standard 要本代际已密封且特征可用。
    @MainActor
    private func configurationWriteIsReady() -> Bool {
        let context = resolvedOLEDContext()
        guard context.allowsIngestAndApply else { return false }
        let charsReady = configurationCharacteristicsAreReady()
        switch context.profile {
        case .legacyStandard:
            return charsReady
        case .rhinoDualSet, .currentSessionCapable:
            let currentReady = executionTestHooks?.isReady ?? transportCore.isReady
            return currentReady && charsReady
        case .unsupported:
            return false
        }
    }

    /// 三特征就绪：显式注入优先；Standard 不得把 skipBLE/`isReady` 当成特征齐全。
    @MainActor
    private func configurationCharacteristicsAreReady() -> Bool {
        if let injected = executionTestHooks?.configurationCharacteristics {
            return injected.peripheral && injected.command && injected.data
        }
        switch resolvedOLEDContext().profile {
        case .legacyStandard:
            return peripheral != nil && commandChar != nil && dataChar != nil
        case .rhinoDualSet, .currentSessionCapable, .unsupported:
            if executionTestHooks?.skipConfigurationBLEWriteGates == true
                || executionTestHooks?.isReady == true {
                return true
            }
            return peripheral != nil && commandChar != nil && dataChar != nil
        }
    }

    @MainActor
    private func progressNowNanos() -> UInt64 {
        executionTestHooks?.progressMonotonicNanos?() ?? DispatchTime.now().uptimeNanoseconds
    }

    /// 配置命令：经 DeviceTransportCore 串行队列 + 五元 waiter 下发，等 cmd 回显 ACK。
    /// 纪律与 querySwitchState 相同：waiter 绑定当前代际，断连/迟到由核心裁决。
    /// R4：完整 BLE 命令路径仅 MainActor 访问 CoreBluetooth / waiter。
    @MainActor
    fileprivate func sendConfigurationCommand(_ frame: Data, expectingAck ack: UInt8) async throws {
        if executionTestHooks?.skipConfigurationBLEWriteGates == true {
            guard configurationWriteIsReady() else {
                throw AhaKeyAgentCommandError.disconnected
            }
            guard frame.count >= 5, frame[2] == ack else { throw AhaKeyAgentCommandError.malformedFrame }
            try throwIfConfigurationCommandRejected(
                opcode: ack,
                status: simulatedConfigurationCommandStatus(for: ack)
            )
            return
        }
        guard configurationWriteIsReady(), commandChar != nil, peripheral != nil else {
            throw AhaKeyAgentCommandError.disconnected
        }
        // frame = AA BB [cmd] [payload…] CC DD
        guard frame.count >= 5, frame[2] == ack else { throw AhaKeyAgentCommandError.malformedFrame }
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(status: UInt8, payload: Data), Error>) in
            operationCounter &+= 1
            let op = operationCounter
            guard let rid = transportCore.registerWaiter(operationID: op, now: Date(), timeout: 3) else {
                continuation.resume(throwing: AhaKeyAgentCommandError.disconnected)
                return
            }
            configWaiterContinuations[rid] = continuation
            configOperationWaiters[op] = rid
            let cmd = DeviceCommand(
                operationID: op,
                deviceID: transportCore.stableDeviceID ?? "",
                generations: transportCore.currentGenerations,
                opcode: ack,
                payload: Data(frame[3 ..< frame.count - 2])
            )
            if let head = transportCore.enqueue(cmd) {
                writeCommand(head)
            }
        }
        guard response.status == 0 else {
            try throwIfConfigurationCommandRejected(opcode: ack, status: response.status)
            return
        }
    }

    /// 命令/ACK 拒绝的唯一生产抛出点：带上真实 opcode 与 device status。
    private func throwIfConfigurationCommandRejected(opcode: UInt8, status: UInt8) throws {
        guard status != 0 else { return }
        emit("配置命令 0x\(String(format: "%02X", opcode)) 被设备拒绝 status=\(status)")
        throw AhaKeyAgentCommandError.deviceRejected(opcode: opcode, status: status)
    }

    private func simulatedConfigurationCommandStatus(for opcode: UInt8) -> UInt8 {
        guard let status = executionTestHooks?.failConfigurationCommandStatus, status != 0 else {
            return 0
        }
        if let expected = executionTestHooks?.failConfigurationCommandOpcode, expected != opcode {
            return 0
        }
        return status
    }

    /// 资源数据块直写：CAS 源 → RGB565 编码（AhaKeyOLEDFrameEncoderCore）→ 按编码流切片
    /// → AhaKeyPictureDataPacketizer 加 session 前缀 → data 特征 → 等 0x81（session 匹配）。
    /// R4：资源数据块直写仅 MainActor 访问 data 特征 / upload session / waiter。
    @MainActor
    fileprivate func writeConfigurationChunk(
        digest: AhaKeySHA256Digest, offset: Int, length: Int, sessionID: UInt16?,
        store: AhaKeyRuntimePersistentStore
    ) async throws {
        let skipBLE = executionTestHooks?.skipConfigurationBLEWriteGates == true
        guard configurationWriteIsReady() else {
            throw AhaKeyAgentCommandError.disconnected
        }
        if !skipBLE {
            guard dataChar != nil, peripheral != nil else {
                throw AhaKeyAgentCommandError.disconnected
            }
        }
        let stream = try await encodedStream(for: digest, store: store)
        guard offset >= 0, length > 0, offset + length <= stream.count else {
            throw AhaKeyAgentCommandError.resourceMissing
        }
        if let hook = executionTestHooks?.beforeConfigurationChunkWrite {
            await hook(configurationChunkAckCount)
        }
        if executionTestHooks?.failNextConfigurationChunk == true {
            executionTestHooks?.failNextConfigurationChunk = false
            throw executionTestHooks?.failConfigurationChunkWith ?? .disconnected
        }
        if let failAfter = executionTestHooks?.failConfigurationWriteAfterAckCount,
           configurationChunkAckCount >= failAfter {
            throw executionTestHooks?.failConfigurationChunkWith ?? .disconnected
        }
        if skipBLE {
            try await completeConfigurationChunkAck(sessionID: sessionID)
            configurationChunkAckCount += 1
            return
        }
        guard let dataChar, let peripheral else {
            throw AhaKeyAgentCommandError.disconnected
        }
        let chunk = Data(stream[offset ..< offset + length])

        let writeType: CBCharacteristicWriteType =
            dataChar.properties.contains(.write) ? .withResponse : .withoutResponse
        let negotiatedLength = max(1, peripheral.maximumWriteValueLength(for: writeType))
        let firmwareLimit = max(sessionID == nil ? 1 : 3, negotiatedCapabilities?.maxPacketSize ?? 180)
        let packets = AhaKeyPictureDataPacketizer.packets(
            for: chunk,
            maxPacketLength: min(negotiatedLength, firmwareLimit),
            sessionID: sessionID
        )

        activeUploadSessionID = sessionID

        // 0x81 waiter 必须在任何 packet 发出前建立（快速 ACK 不得丢失）；
        // 失败/超时时 activeUploadSessionID 保留给 abortConfigurationSession 发 0x9A，
        // 只有 0x81 成功（handlePictureWriteResult）或 0x9A 收尾后才清空。
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataWriteContinuation = continuation
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.dataWriteContinuation else { return }
                self.dataWriteContinuation = nil
                self.dataWriteTimeoutItem = nil
                pending.resume(throwing: AhaKeyAgentCommandError.ackTimedOut)
            }
            dataWriteTimeoutItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

            // waiter 就位后再发数据包（12ms 间隔，与 Studio 生产路径一致）
            Task { @MainActor [weak self] in
                guard let self else { return }
                for packet in packets {
                    guard self.configurationWriteIsReady(), self.dataWriteContinuation != nil else { return }
                    peripheral.writeValue(packet, for: dataChar, type: writeType)
                    try? await Task.sleep(nanoseconds: 12_000_000)
                }
            }
        }
    }

    @MainActor
    private func completeConfigurationChunkAck(sessionID: UInt16?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            dataWriteContinuation = continuation
            activeUploadSessionID = sessionID
            var payload = Data()
            if let sessionID {
                payload.append(UInt8(sessionID & 0xFF))
                payload.append(UInt8((sessionID >> 8) & 0xFF))
            }
            let status = executionTestHooks?.failConfigurationPictureWriteStatus ?? 0
            handlePictureWriteResult(status: status, payload: payload[payload.startIndex...])
        }
    }

    /// 0x81 路由：纯决策在 Shared（AhaKeyPictureWriteResultRouter），此处只做落地。
    private func handlePictureWriteResult(status: UInt8, payload: Data.SubSequence) {
        switch AhaKeyPictureWriteResultRouter.decide(
            status: status, payload: Array(payload), expectedSession: activeUploadSessionID
        ) {
        case .ignoreMissingSession:
            emit("← 忽略缺少 session 的图片写入确认")
            return
        case .ignoreStaleSession(let session):
            emit("← 忽略过期图片确认 session=\(session)，当前=\(activeUploadSessionID ?? 0)")
            return
        case .success, .deviceRejected:
            break
        }
        guard let continuation = dataWriteContinuation else { return }
        dataWriteContinuation = nil
        dataWriteTimeoutItem?.cancel()
        dataWriteTimeoutItem = nil
        if status == 0 {
            activeUploadSessionID = nil  // 0x81 成功：会话正常关闭
            continuation.resume()
        } else {
            // 失败保留 session，由 executor 收尾补 0x9A 后清空
            continuation.resume(throwing: AhaKeyAgentCommandError.deviceRejected(opcode: 0x81, status: status))
        }
    }

    /// 失败/取消收尾：先补 0x9A 回滚在途会话，再强败数据 waiter，最后清 session。
    @MainActor
    fileprivate func abortConfigurationSession() async {
        guard let sessionID = activeUploadSessionID else { return }
        if transportCore.isReady, let commandChar, let peripheral,
           let frame = AhaKeyWireFrameBuilder.commandFrame(for: .abortSession(sessionID: sessionID)) {
            let wt: CBCharacteristicWriteType =
                commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(frame, for: commandChar, type: wt)
            emit("→ 已回滚图片写入会话 \(sessionID)（0x9A）")
        }
        activeUploadSessionID = nil
        if let continuation = dataWriteContinuation {
            dataWriteContinuation = nil
            dataWriteTimeoutItem?.cancel()
            dataWriteTimeoutItem = nil
            continuation.resume(throwing: AhaKeyAgentCommandError.cancelled)
        }
    }

    /// CAS 源 → RGB565 编码流（按 digest 缓存；单恢复周期内重复 chunk 不重复编码）。
    private func encodedStream(
        for digest: AhaKeySHA256Digest, store: AhaKeyRuntimePersistentStore
    ) async throws -> Data {
        if let cached = encodedStreamCache[digest] { return cached }
        guard let url = try await store.resourceURL(for: digest) else {
            throw AhaKeyAgentCommandError.resourceMissing
        }
        let frames = try AhaKeyOLEDFrameEncoderCore.frames(
            fromImageAt: url,
            maxFrames: AhaKeyDeviceLayoutPolicy().framesPerSlot,
            maxSourceFileBytes: 20 * 1024 * 1024
        )
        let stream = AhaKeyOLEDFrameEncoderCore.encodedStream(frames: frames)
        encodedStreamCache[digest] = stream
        return stream
    }

    // MARK: - Runtime 生产投影 / 事件回放实现（WBS-5.7 R1）

    /// durable accept 后立即投影 accepted 并发布事件（执行进度/终态另行发布）。
    /// 幂等重放不得把已在跑的 operation 打回 accepted，也不得重置字节进度。
    /// 终态已在 apply 入口用抛错读裁决并投影；此处只拦内存中已过 accepted 的进行中 operation。
    private func noteOperationAccepted(_ package: AhaKeyConfigurationPackage) async {
        let skip = await MainActor.run { () -> Bool in
            if let existing = self.projectionOperations[package.operationID],
               existing.state != .accepted {
                return true
            }
            return false
        }
        if skip { return }
        let base = AhaKeyRuntimeOperationSummary(
            id: package.operationID, targetDeviceID: package.targetDeviceID, state: .accepted
        )
        let summary = await MainActor.run { self.overlayByteProgress(base) }
        await MainActor.run {
            self.publishOperationChanged(summary)
        }
    }

    /// 从 WAL 读最新状态并发布 operationChanged（进度/终态的唯一发布点）。
    private func publishOperationProgress(operationID: AhaKeyRuntimeOperationID) async {
        guard let store = try? await makeRuntimeStore(),
              let record = try? await store.transaction(operationID) else { return }
        await publishOperationProgress(from: record)
    }

    /// 用已经读到的 durable record 投影，避免二次 `try?` 把终态吞掉。
    private func publishOperationProgress(from record: AhaKeyRuntimePersistedTransaction) async {
        let summary = await MainActor.run { () -> AhaKeyRuntimeOperationSummary in
            if record.state.isTerminal {
                _ = self.byteProgressByOperation[record.operationID]?.publishTerminal(
                    nowNanos: self.progressNowNanos()
                )
            }
            return self.overlayByteProgress(Self.operationSummary(from: record))
        }
        await MainActor.run {
            self.publishOperationChanged(summary)
        }
    }

    private static func operationSummary(from record: AhaKeyRuntimePersistedTransaction) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: record.operationID,
            targetDeviceID: record.package.targetDeviceID,
            state: record.state,
            completedSteps: record.completedSteps,
            totalSteps: record.totalSteps,
            messageCode: record.messageCode,
            failureContext: record.failureContext
        )
    }

    @MainActor
    private func overlayByteProgress(_ summary: AhaKeyRuntimeOperationSummary) -> AhaKeyRuntimeOperationSummary {
        byteProgressByOperation[summary.id]?.overlay(summary) ?? summary
    }

    private func beginByteProgressIfNeeded(for package: AhaKeyConfigurationPackage) async {
        let total = await MainActor.run { self.resourceByteTotal(for: package) }
        await MainActor.run {
            guard self.byteProgressByOperation[package.operationID] == nil, total > 0 else { return }
            self.byteProgressByOperation[package.operationID] = AhaKeyByteProgressProjector(totalBytes: total)
        }
    }

    @MainActor
    private func resourceByteTotal(for package: AhaKeyConfigurationPackage) -> UInt64 {
        let context = resolvedOLEDContext()
        guard context.allowsIngestAndApply,
              let desired = try? AhaKeyDesiredConfiguration.decode(from: package.desiredConfiguration) else {
            return 0
        }
        let release = releaseProjection(for: context)
        let planning = AhaKeyConfigurationPlanner.plan(
            desired: desired, resources: package.resources,
            context: context, release: release
        )
        guard case .success(let plan) = planning else { return 0 }
        var total: UInt64 = 0
        for step in AhaKeyConfigurationTransactionEngine.stepIdentifiers(for: plan) {
            guard step.rawValue.hasPrefix("resource:"),
                  let program = AhaKeyConfigurationStepMapper.program(
                    for: step, desired: desired, plan: plan,
                    resources: package.resources, context: context,
                    release: release
                  ) else { continue }
            for item in program {
                if case .writeResourceChunk(_, _, let length) = item {
                    total += UInt64(length)
                }
            }
        }
        return total
    }

    @MainActor
    private func noteEnteredConfigurationStep(
        operationID: AhaKeyRuntimeOperationID,
        stepID: AhaKeyRuntimeStepIdentifier
    ) {
        guard stepID.rawValue.hasPrefix("resource:") else { return }
        guard var projector = byteProgressByOperation[operationID] else { return }
        let shouldPublish = projector.enterStep(stepID: stepID, nowNanos: progressNowNanos())
        byteProgressByOperation[operationID] = projector
        guard shouldPublish, let summary = projectionOperations[operationID] else { return }
        publishOperationChanged(overlayByteProgress(summary))
    }

    @MainActor
    fileprivate func noteConfirmedResourceChunk(
        operationID: AhaKeyRuntimeOperationID,
        stepID: AhaKeyRuntimeStepIdentifier,
        bytes: UInt64,
        nowNanos: UInt64? = nil
    ) {
        guard var projector = byteProgressByOperation[operationID] else { return }
        let shouldPublish = projector.confirmChunk(
            stepID: stepID, bytes: bytes, nowNanos: nowNanos ?? progressNowNanos()
        )
        byteProgressByOperation[operationID] = projector
        guard shouldPublish, var summary = projectionOperations[operationID] else { return }
        summary = overlayByteProgress(summary)
        publishOperationChanged(summary)
    }

    @MainActor
    private func publishOperationChanged(_ summary: AhaKeyRuntimeOperationSummary) {
        if lastPublishedOperationSummaries[summary.id] == summary {
            return
        }
        if summary.state == .running {
            let now = progressNowNanos()
            if let last = lastRunningPublishAtNanos[summary.id],
               now &- last < AhaKeyByteProgressProjector.minimumPublishIntervalNanoseconds {
                return
            }
            lastRunningPublishAtNanos[summary.id] = now
        }
        lastPublishedOperationSummaries[summary.id] = summary
        publishRuntimeEvent(.operationChanged(summary), context: .init(
            operationID: summary.id, deviceID: summary.targetDeviceID
        ))
    }

    /// 追加投影事件：单调 sequence、有界回放、唤醒 long-poll waiter。仅 main 队列调用。
    @MainActor
    private func publishRuntimeEvent(_ payload: AhaKeyRuntimeEventPayload, context: AhaKeyRuntimeEventContext = .init()) {
        projectionLatestSequence = AhaKeyRuntimeEventSequence(projectionLatestSequence.rawValue + 1)
        let event = AhaKeyRuntimeEvent(sequence: projectionLatestSequence, context: context, payload: payload)
        try? projectionEventBuffer.append(event)
        switch payload {
        case .operationChanged(let summary):
            projectionOperations[summary.id] = summary
            if summary.state.isTerminal {
                projectionTerminalOrder.removeAll { $0 == summary.id }
                projectionTerminalOrder.append(summary.id)
                while projectionTerminalOrder.count > 64 {
                    let evicted = projectionTerminalOrder.removeFirst()
                    projectionOperations.removeValue(forKey: evicted)
                    byteProgressByOperation.removeValue(forKey: evicted)
                    lastPublishedOperationSummaries.removeValue(forKey: evicted)
                    lastRunningPublishAtNanos.removeValue(forKey: evicted)
                }
            }
        case .diagnostic, .security:
            projectionDiagnosticEvents.append(event)
            if projectionDiagnosticEvents.count > 64 {
                projectionDiagnosticEvents.removeFirst(projectionDiagnosticEvents.count - 64)
            }
        default:
            break
        }
        let waiters = projectionEventWaiters
        projectionEventWaiters.removeAll()
        for (id, continuation) in waiters {
            longPollSessions.removeValue(forKey: id)
            continuation.resume(returning: nil)
        }
    }

    /// 设备投影有变化才发布 deviceChanged。可在任意队列调用（内部落到 main）。
    private func publishDeviceChangedIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            self?.publishDeviceChangedOnMain()
        }
    }

    @MainActor
    private func publishDeviceChangedOnMain() {
        let device = projectedDeviceSnapshot()
        guard device != lastPublishedDeviceSnapshot else { return }
        lastPublishedDeviceSnapshot = device
        guard let device else { return }
        publishRuntimeEvent(.deviceChanged(device), context: .init(
            deviceID: device.id,
            sessionGeneration: device.sessionGeneration,
            transportGeneration: device.transportGeneration
        ))
        let persistTask = Task { await self.persistAuthoritativeObject(from: device) }
        authoritativeObjectPersistTask = persistTask
    }

    /// 把 `deviceChanged` 快照上的 canonical object 持久化为 live CAS。
    private func persistAuthoritativeObject(from device: AhaKeyRuntimeDeviceSnapshot?) async {
        guard let device,
              let content = device.authoritativeObject,
              !content.isEmpty else { return }
        guard let store = try? await makeRuntimeStore() else { return }
        try? await store.persistProjectedAuthoritativeObject(content, for: device.id)
    }

    /// 当前 BLE 设备状态 → 投影设备快照（无已知设备返回 nil）。仅 main 队列调用。
    @MainActor
    private func projectedDeviceSnapshot() -> AhaKeyRuntimeDeviceSnapshot? {
        if let simulated = executionTestHooks?.simulatedDevice { return simulated }
        guard let deviceIDString = executionTestHooks?.stableDeviceID ?? transportCore.stableDeviceID,
              let deviceID = try? AhaKeyRuntimeDeviceID(deviceIDString) else { return nil }
        let protocolState: AhaKeyRuntimeDeviceProtocolState
        let connected: Bool
        switch transportCore.phase {
        case .ready:
            protocolState = .currentReady
            connected = true
        case .connecting, .discovering, .negotiating:
            protocolState = .probing
            connected = true
        case .idle, .awaitingLock, .scanning, .backoffReconnect:
            protocolState = .disconnected
            connected = peripheral != nil
        }
        var capabilities: Set<AhaKeyRuntimeDeviceCapability> = []
        if negotiatedCapabilities != nil { capabilities.insert(.configurationV4) }
        if resolvedOLEDContext().allowsIngestAndApply {
            capabilities.insert(AhaKeyOLEDWritePreflight.routingCapability)
        }
        let generations = transportCore.currentGenerations
        return AhaKeyRuntimeDeviceSnapshot(
            id: deviceID,
            displayName: peripheral?.name ?? coreSnapshot.deviceName ?? deviceIDString,
            protocolState: protocolState,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: connected,
            capabilities: capabilities,
            sessionGeneration: .init(generations.session),
            transportGeneration: .init(generations.transport),
            state: projectedDeviceState()
        )
    }

    /// 设备状态字段投影（诊断遥测如 RSSI 刻意不进投影）。仅 main 队列调用。
    @MainActor
    private func projectedDeviceState() -> AhaKeyRuntimeDeviceState {
        let lever: AhaKeyRuntimeLeverPosition?
        switch effectiveSwitchState {
        case .some(0): lever = .up
        case .some(1): lever = .down
        case .some: lever = .middle
        case .none: lever = nil
        }
        let fullStatus = coreSnapshot.hasReceivedFullStatus
        let firmwareVersion = coreSnapshot.firmwareMainVersion > 0
            ? "\(coreSnapshot.firmwareMainVersion).\(coreSnapshot.firmwareSubVersion)"
            : nil
        var taskSets: [AhaKeyRuntimeModeIndex: AhaKeyRuntimeTaskPictureSetIndex] = [:]
        for (mode, set) in coreSnapshot.activeTaskPictureSets where mode >= 0 && set >= 0 {
            taskSets[AhaKeyRuntimeModeIndex(UInt8(clamping: mode))] =
                AhaKeyRuntimeTaskPictureSetIndex(UInt8(clamping: set))
        }
        return AhaKeyRuntimeDeviceState(
            batteryLevel: fullStatus ? try? AhaKeyRuntimePercentage(coreSnapshot.batteryLevel) : nil,
            workMode: fullStatus ? AhaKeyRuntimeModeIndex(UInt8(clamping: coreSnapshot.workMode)) : nil,
            lightMode: fullStatus ? AhaKeyRuntimeLightMode(UInt8(clamping: coreSnapshot.lightMode)) : nil,
            leverPosition: lever,
            brightness: try? AhaKeyRuntimePercentage(coreSnapshot.brightness),
            firmwareVersion: firmwareVersion,
            activeTaskPictureSets: taskSets
        )
    }

    /// 权威投影：BLE 设备状态 + WAL operation 摘要 + policy + 单调事件序号。
    /// main 上的投影态（设备/policy/序号/缓存 operation）一次读取，WAL 侧异步合并。
    func projectedRuntimeSnapshot() async -> AhaKeyRuntimeSnapshot {
        struct MainPart {
            var devices: [AhaKeyRuntimeDeviceSnapshot]
            var activeDeviceID: AhaKeyRuntimeDeviceID?
            var policy: AhaKeyRuntimePolicy
            var latestEventSequence: AhaKeyRuntimeEventSequence
            var cachedOperations: [AhaKeyRuntimeOperationID: AhaKeyRuntimeOperationSummary]
            var byteProgress: [AhaKeyRuntimeOperationID: AhaKeyByteProgressProjector]
        }
        let main = await MainActor.run { () -> MainPart in
            let device = self.projectedDeviceSnapshot()
            return MainPart(
                devices: device.map { [$0] } ?? [],
                activeDeviceID: device?.id,
                policy: self.currentPolicy,
                latestEventSequence: self.projectionLatestSequence,
                cachedOperations: self.projectionOperations,
                byteProgress: self.byteProgressByOperation
            )
        }
        var operations = main.cachedOperations
        var revision = AhaKeyConfigurationRevision(0)
        if let store = try? await makeRuntimeStore() {
            // WAL 非终态事务并入投影。
            if let candidates = try? await store.recoveryCandidates() {
                for candidate in candidates {
                    operations[candidate.operationID] = Self.operationSummary(from: candidate)
                }
            }
            // 先刷新已知 operation 的 WAL 状态，再裁定有界终态窗口：
            // 否则缓存里的 running 会在补窗之后才变成终态，把 64 扩成 65。
            for id in operations.keys {
                if let record = try? await store.transaction(id) {
                    operations[id] = Self.operationSummary(from: record)
                }
            }
            // 单一有界窗口：内存终态优先（含淘汰后重放、刷新后新转入终态的项），
            // 刷新新终态按 WAL terminal_order DESC 排序，再补足到 64。不裁剪缓存。
            let limit = AhaKeyRuntimePersistentStore.snapshotProjectionTerminalLimit
            var bounded: [AhaKeyRuntimeOperationID: AhaKeyRuntimeOperationSummary] = [:]
            for (id, summary) in operations where !summary.state.isTerminal {
                bounded[id] = summary
            }
            var terminalCount = 0
            let memoryTerminalIDs = operations.keys.filter { operations[$0]?.state.isTerminal == true }
            // API 在窗口内 oldest-first（newest 在末尾）；反转后再按 terminal_order DESC 选窗。
            let walNewestFirst = Array(((try? await store.recentTerminalTransactions(
                limit: max(limit, memoryTerminalIDs.count)
            )) ?? []).reversed())
            var walRank: [AhaKeyRuntimeOperationID: Int] = [:]
            walRank.reserveCapacity(walNewestFirst.count)
            for (index, terminal) in walNewestFirst.enumerated() {
                walRank[terminal.operationID] = index
            }
            let orderedMemoryTerminals = memoryTerminalIDs.sorted { lhs, rhs in
                switch (walRank[lhs], walRank[rhs]) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.rawValue.uuidString < rhs.rawValue.uuidString
                }
            }
            for id in orderedMemoryTerminals {
                guard terminalCount < limit else { break }
                guard let summary = operations[id], summary.state.isTerminal else { continue }
                if bounded[id] == nil {
                    bounded[id] = summary
                    terminalCount += 1
                }
            }
            for terminal in walNewestFirst {
                guard terminalCount < limit else { break }
                if bounded[terminal.operationID] == nil {
                    bounded[terminal.operationID] = Self.operationSummary(from: terminal)
                    terminalCount += 1
                }
            }
            operations = bounded
            if let deviceID = main.activeDeviceID,
               let baseline = try? await store.syncBaseline(for: deviceID) {
                revision = baseline.revision
            }
        }
        for id in operations.keys {
            if let projector = main.byteProgress[id] {
                operations[id] = projector.overlay(operations[id]!)
            }
        }
        return AhaKeyRuntimeSnapshot(
            supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
            lifecycleState: .running,
            devices: main.devices,
            activeDeviceID: main.activeDeviceID,
            configurationRevision: revision,
            operations: operations.values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString },
            policy: main.policy,
            latestEventSequence: main.latestEventSequence
        )
    }

    /// events 请求：有事件/断档立即返回；空批 long-poll（R2-5：waiter 注册与二次 replay
    /// 复查收敛进同一 MainActor 临界区，消除 lost-wakeup 夹缝），新事件立即唤醒，超时返回空批。
    private func handleEventsRequest(after cursor: AhaKeyRuntimeEventSequence?) async -> AhaKeyRuntimeXPCResponse {
        // 快路径：已有事件/断档/错误立即返回；空批进入 long-poll。
        let fast = await replayVerdict(after: cursor)
        if case .success(.events(let events)) = fast, events.isEmpty {
            // 空批 → long-poll。
        } else {
            return eventReplayResponse(fast)
        }
        // 测试 seam：快路径空批之后由 long-poll 同一临界区登记 waiter 并复查。
        if let immediate = await longPollRuntimeEvents(after: cursor, timeout: runtimeEventsLongPollInterval) {
            // 临界区内二次复查命中（夹缝事件/断档/错误）：立即返回，不白等。
            return eventReplayResponse(immediate)
        }
        // 被新事件唤醒 / 超时 / 取消：最终复查（此次允许空批返回）。
        return eventReplayResponse(await replayVerdict(after: cursor))
    }

    /// replay 结果 → XPC 响应的统一映射。
    private func eventReplayResponse(_ verdict: AhaKeyRuntimeEventReplayVerdict) -> AhaKeyRuntimeXPCResponse {
        switch verdict {
        case .failure:
            return .failure(try! AhaKeyRuntimeEventCode("cursor-ahead-of-runtime"))
        case .success(.snapshotRequired(let latest)):
            return .eventReplay(.snapshotRequired(latest: latest))
        case .success(.events(let events)):
            return .eventReplay(.events(events))
        }
    }

    /// 回放检查（任意队列可调用；内部落到 main 读缓冲）。
    private func replayVerdict(after cursor: AhaKeyRuntimeEventSequence?) async -> AhaKeyRuntimeEventReplayVerdict {
        await MainActor.run { self.replayVerdictOnMain(after: cursor) }
    }

    @MainActor
    private func replayVerdictOnMain(after cursor: AhaKeyRuntimeEventSequence?) -> AhaKeyRuntimeEventReplayVerdict {
        do {
            return .success(try projectionEventBuffer.events(after: cursor))
        } catch let error as AhaKeyRuntimeEventReplayError {
            return .failure(error)
        } catch {
            return .failure(.cursorAheadOfRuntime)
        }
    }

    /// long-poll：before-register 屏障之后，waiter 登记与最终 replay 复查必须在
    /// 同一个 MainActor 同步临界区内完成，中间不得 await / 另起 Task。
    private func longPollRuntimeEvents(
        after cursor: AhaKeyRuntimeEventSequence?,
        timeout: TimeInterval
    ) async -> AhaKeyRuntimeEventReplayVerdict? {
        let id = UUID()
        await MainActor.run { self.longPollSessions[id] = .registering }
        if let hook = await MainActor.run(body: { self.executionTestHooks?.longPollBeforeRegisterHook }) {
            await hook()
        }

        let timeoutBox = LongPollTimeoutBox()
        let verdict = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AhaKeyRuntimeEventReplayVerdict?, Never>) in
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        continuation.resume(returning: nil)
                        return
                    }
                    switch self.longPollSessions[id] {
                    case .cancelled, .none:
                        self.longPollSessions.removeValue(forKey: id)
                        continuation.resume(returning: nil)
                        return
                    case .waiting:
                        continuation.resume(returning: nil)
                        return
                    case .registering:
                        break
                    }
                    // 同一主队列同步临界区：挂 waiter + 最终 replay 复查，中间无 await。
                    self.projectionEventWaiters[id] = continuation
                    self.longPollSessions[id] = .waiting(continuation)
                    if let gapHook = self.executionTestHooks?.eventsLongPollGapHook {
                        gapHook()
                    }
                    if self.projectionEventWaiters[id] == nil {
                        return
                    }
                    let recheck = self.replayVerdictOnMain(after: cursor)
                    if case .success(.events(let events)) = recheck, events.isEmpty {
                        let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                        timeoutBox.task = Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: nanoseconds)
                            self?.completeLongPoll(id, result: nil)
                        }
                    } else {
                        self.completeLongPoll(id, result: recheck)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.longPollSessions[id] {
                case .waiting:
                    self.completeLongPoll(id, result: nil)
                case .registering:
                    self.longPollSessions[id] = .cancelled
                case .cancelled, .none:
                    break
                }
            }
        }
        timeoutBox.task?.cancel()
        if let hook = await MainActor.run(body: { self.executionTestHooks?.longPollAfterCompleteHook }) {
            await hook()
        }
        return verdict
    }

    @MainActor
    private func completeLongPoll(_ id: UUID, result: AhaKeyRuntimeEventReplayVerdict?) {
        let continuation = projectionEventWaiters.removeValue(forKey: id)
        longPollSessions.removeValue(forKey: id)
        continuation?.resume(returning: result)
    }

    /// diagnostics 请求：返回留存的诊断/安全事件（after 游标过滤）。
    @MainActor
    private func diagnosticsResponse(after cursor: AhaKeyRuntimeEventSequence?) -> AhaKeyRuntimeXPCResponse {
        let events = projectionDiagnosticEvents.filter { cursor == nil || $0.sequence > cursor! }
        return .diagnosticEvents(events)
    }

    /// 测试 seam：直接注入原始 0x00 回包，走生产 `consumeDeviceStatus` 入口。
    @MainActor
    internal func injectRawStatusPacketForTesting(_ data: Data) {
        _ = consumeDeviceStatus(data)
    }

    @MainActor
    func longPollLeakCountsForTesting() -> (sessions: Int, waiters: Int) {
        (longPollSessions.count, projectionEventWaiters.count)
    }

    /// 测试 seam：设置模拟设备投影并立即发布 deviceChanged（等效 BLE 连接/断开驱动）。
    /// 配合 executionTestHooks.isReady/capabilities/stepExecutor 可免 BLE 驱动执行路径。
    func simulateDeviceForTesting(_ device: AhaKeyRuntimeDeviceSnapshot?) async {
        let pending = await MainActor.run { () -> Task<Void, Never>? in
            self.setSimulatedDeviceOnMainForTesting(device)
            return self.authoritativeObjectPersistTask
        }
        await pending?.value
    }

    /// 测试 seam：MainActor 上同步更换模拟设备投影并立即发布 deviceChanged。
    /// 供 eventsLongPollGapHook 在 lost-wakeup 交错测试中于临界区夹缝内注入事件（R2-5）。
    @MainActor
    func setSimulatedDeviceOnMainForTesting(_ device: AhaKeyRuntimeDeviceSnapshot?) {
        var hooks = self.executionTestHooks ?? AhaKeyAgentExecutionTestHooks()
        hooks.simulatedDevice = device
        self.executionTestHooks = hooks
        self.publishDeviceChangedOnMain()
    }

    /// 测试 seam：走生产 `handleJsonCommand`，不经 Unix socket。
    @MainActor
    func handleJsonCommandForTesting(cmd: String, obj: [String: Any]) {
        handleJsonCommand(cmd: cmd, obj: obj, clientFd: -1, session: nil)
    }

    @MainActor
    var hasPendingStateResetForTesting: Bool { pendingStateResetTask != nil }

    @MainActor
    var isConfigurationTransportWindowActiveForTesting: Bool {
        configurationTransportWindow.isActive
    }

    /// 测试 seam：生产 `withConfigurationTransportWindow` 配对（正常 / 抛错 / 取消）。
    func withConfigurationTransportWindowForTesting<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        try await withConfigurationTransportWindow(work)
    }

    /// 测试 seam：把真实 `transportCore` 推到 current-ready，使 `sendState` 走生产 enqueue。
    /// `occupyQueue` 先放入一条在途命令，下一次 enqueue 返回 nil（已入队但非 head）。
    @MainActor
    func primeTransportForCommandEnqueueForTesting(occupyQueue: Bool = false) {
        let now = Date()
        _ = transportCore.handle(.bluetoothPoweredOn, now: now)
        _ = transportCore.handle(.lockAcquired, now: now)
        _ = transportCore.handle(.discovered(uuid: "TEST-UUID", deviceID: "TEST-DEVICE"), now: now)
        _ = transportCore.handle(.connected(uuid: "TEST-UUID"), now: now)
        _ = transportCore.handle(.servicesReady(uuid: "TEST-UUID"), now: now)
        _ = transportCore.handle(.negotiationFinished(uuid: "TEST-UUID", mode: .current), now: now)
        guard occupyQueue, transportCore.isReady else { return }
        operationCounter &+= 1
        let dummy = DeviceCommand(
            operationID: operationCounter,
            deviceID: transportCore.stableDeviceID ?? "",
            generations: transportCore.currentGenerations,
            opcode: 0x00,
            payload: Data()
        )
        _ = transportCore.enqueue(dummy)
    }

    /// C-2 测试 seam：走生产 `noteConfirmedResourceChunk`（确认块后才推进）。
    @MainActor
    func noteConfirmedResourceChunkForTesting(
        operationID: AhaKeyRuntimeOperationID,
        stepID: AhaKeyRuntimeStepIdentifier,
        bytes: UInt64,
        nowNanos: UInt64
    ) {
        noteConfirmedResourceChunk(operationID: operationID, stepID: stepID, bytes: bytes, nowNanos: nowNanos)
    }

    @MainActor
    func beginByteProgressForTesting(operationID: AhaKeyRuntimeOperationID, totalBytes: UInt64) {
        guard byteProgressByOperation[operationID] == nil, totalBytes > 0 else { return }
        byteProgressByOperation[operationID] = AhaKeyByteProgressProjector(totalBytes: totalBytes)
    }

    @MainActor
    func byteProgressCacheCountForTesting() -> Int {
        byteProgressByOperation.count
    }

    @MainActor
    func configurationChunkAckCountForTesting() -> Int {
        configurationChunkAckCount
    }

    /// 测试 seam：释放本实例持有的 WAL 连接，模拟进程退出后再由新 Agent 打开同一 root。
    func closeRuntimeStoreForTesting() async {
        await runtimeStoreCache.clear()
    }

    /// 测试 seam：把 WAL 最新状态发布为 operationChanged，形成同进程投影缓存。
    func publishOperationProgressForTesting(_ operationID: AhaKeyRuntimeOperationID) async {
        await publishOperationProgress(operationID: operationID)
    }

    func negotiatedOLEDContextForTesting() -> AhaKeyOLEDCompatibilityContext? {
        negotiatedOLEDContext
    }

    func resolvedOLEDContextForTesting() -> AhaKeyOLEDCompatibilityContext {
        resolvedOLEDContext()
    }

    func oledConnectionGenerationForTesting() -> UInt64 {
        oledConnectionGeneration
    }

    private func oledProbePhaseNameForTesting() -> String {
        switch oledLegacyProbePhase {
        case .idle: return "idle"
        case .awaitingFirmwareVersion: return "awaitingFirmwareVersion"
        case .awaitingTaskPicture: return "awaitingTaskPicture"
        }
    }

    func oledNegotiationSnapshotForTesting() -> AhaKeyOLEDNegotiationSnapshotForTesting {
        AhaKeyOLEDNegotiationSnapshotForTesting(
            contextProfile: negotiatedOLEDContext?.profile,
            hasCapabilities: negotiatedCapabilities != nil,
            malformed: sawMalformedCapabilityFrame,
            awaitingCapability: awaitingCapabilityResponse,
            phase: oledProbePhaseNameForTesting(),
            firmwareMain: legacyProbeFirmwareMainVersion,
            routingProfile: resolvedOLEDContext().profile
        )
    }

    func finishOLEDNegotiationForTesting(_ state: AhaKeyReleaseNegotiationState) {
        finishOLEDNegotiation(state)
    }

    @discardableResult
    private func applyOLEDNotifyPeripheralIDForTesting(_ peripheralID: UUID) -> UUID {
        var hooks = executionTestHooks ?? AhaKeyAgentExecutionTestHooks()
        hooks.oledNotifyPeripheralID = peripheralID
        executionTestHooks = hooks
        return peripheralID
    }

    @discardableResult
    private func ensureTestOLEDPeripheralID() -> UUID {
        if let id = executionTestHooks?.oledNotifyPeripheralID { return id }
        return applyOLEDNotifyPeripheralIDForTesting(UUID())
    }

    func armOLEDAwaitingCapabilityResponseForTesting(peripheralID: UUID, callbackIdentity: AnyObject) {
        _ = applyOLEDNotifyPeripheralIDForTesting(peripheralID)
        bindOLEDNotifySource(
            OLEDNotifySource(generation: oledConnectionGeneration, peripheralID: peripheralID),
            to: callbackIdentity
        )
        awaitingCapabilityResponse = true
        oledLegacyProbePhase = .idle
        noteOLEDInFlight()
    }

    func armOLEDAwaitingTaskPictureForTesting(
        peripheralID: UUID,
        callbackIdentity: AnyObject,
        firmwareMainVersion: Int? = nil
    ) {
        _ = applyOLEDNotifyPeripheralIDForTesting(peripheralID)
        bindOLEDNotifySource(
            OLEDNotifySource(generation: oledConnectionGeneration, peripheralID: peripheralID),
            to: callbackIdentity
        )
        awaitingCapabilityResponse = false
        oledLegacyProbePhase = .awaitingTaskPicture
        if let firmwareMainVersion {
            legacyProbeFirmwareMainVersion = firmwareMainVersion
        }
        noteOLEDInFlight()
    }

    func handleLegacyFirmwareProbeFrameForTesting(_ data: Data) {
        let sourceID = ensureTestOLEDPeripheralID()
        let identity = NSObject()
        bindOLEDNotifySource(
            OLEDNotifySource(generation: oledConnectionGeneration, peripheralID: sourceID),
            to: identity
        )
        oledLegacyProbePhase = .awaitingFirmwareVersion
        noteOLEDInFlight()
        ingestOLEDNegotiationNotify(data, callbackIdentity: identity)
    }

    func handleLegacyTaskPictureProbeFrameForTesting(_ data: Data) {
        let sourceID = ensureTestOLEDPeripheralID()
        let identity = NSObject()
        bindOLEDNotifySource(
            OLEDNotifySource(generation: oledConnectionGeneration, peripheralID: sourceID),
            to: identity
        )
        oledLegacyProbePhase = .awaitingTaskPicture
        noteOLEDInFlight()
        ingestOLEDNegotiationNotify(data, callbackIdentity: identity)
    }

    func invalidateOLEDNotifyCallbackIdentityForTesting(_ object: AnyObject) {
        invalidateOLEDNotifyCallbackIdentity(object)
    }

    func ingestOLEDNegotiationNotifyForTesting(_ data: Data, callbackIdentity: AnyObject) {
        ingestOLEDNegotiationNotify(data, callbackIdentity: callbackIdentity)
    }

    func oledNotifyRetainedIdentityCountForTesting() -> Int {
        oledNotifyBoundIdentities.allObjects.count
    }

    /// 测试 seam：与 didDisconnect/didConnect 同一套 OLED 代际清场。
    func simulateOLEDConnectionResetForTesting() {
        resetOLEDNegotiationState(reason: "test-reset")
        publishDeviceChangedIfNeeded()
    }

    /// 测试 seam：模拟过期 timeout 回调；代际不匹配时必须零状态变化。
    func fireOLEDNegotiationTimeoutForTesting(generation: UInt64) {
        guard isCurrentOLEDGeneration(generation) else { return }
        if awaitingCapabilityResponse {
            negotiationTimedOut()
        } else {
            legacyOLEDProbeTimedOut()
        }
    }

    /// 测试 seam：无 callback 对象时与生产 `didUpdateValueFor` 一样直接拒绝，不得反推当前订阅。
    func handleOLEDNotifyFrameForTesting(_ data: Data, callbackIdentity: AnyObject? = nil) {
        guard let callbackIdentity else { return }
        ingestOLEDNegotiationNotify(data, callbackIdentity: callbackIdentity)
    }

    @MainActor
    func configurationWriteIsReadyForTesting() -> Bool {
        configurationWriteIsReady()
    }
}

/// events 回放判定结果（R2-5：long-poll 临界区复查/waiter 信号的载体）。
typealias AhaKeyRuntimeEventReplayVerdict = Result<AhaKeyRuntimeEventReplayResult, AhaKeyRuntimeEventReplayError>

/// Runtime Store 缓存（R2-2）：actor 隔离，多 XPC session 并发读写安全；
/// 同一目录复用单实例（多实例对同一 root 的 flock/SQLite 连接会相互竞争）。
private actor AhaKeyAgentRuntimeStoreCache {
    private var cached: (directory: URL, store: AhaKeyRuntimePersistentStore)?

    func store(for directory: URL) throws -> AhaKeyRuntimePersistentStore {
        if let cached, cached.directory == directory {
            return cached.store
        }
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: directory,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        cached = (directory, store)
        return store
    }

    func clear() {
        cached = nil
    }
}

/// 配置命令错误（agent 侧 seam）。
enum AhaKeyAgentCommandError: Error, Equatable {
    case disconnected
    case ackTimedOut
    case deviceRejected(opcode: UInt8, status: UInt8)
    case resourceMissing
    case malformedFrame
    case cancelled
    /// 已有配置事务在飞（恢复或受理单飞闸门）。
    case busy
}

/// 测试注入：把「Standard 已密封」与「peripheral/command/data 三特征就绪」分开。
struct AhaKeyConfigurationCharacteristicPresence: Equatable, Sendable {
    var peripheral: Bool
    var command: Bool
    var data: Bool

    static let allPresent = AhaKeyConfigurationCharacteristicPresence(
        peripheral: true, command: true, data: true
    )
}

/// 测试快照：同-phase 迟到 notify 必须对这些字段零变化。
struct AhaKeyOLEDNegotiationSnapshotForTesting: Equatable {
    var contextProfile: AhaKeyOLEDCompatibilityProfile?
    var hasCapabilities: Bool
    var malformed: Bool
    var awaitingCapability: Bool
    var phase: String
    var firmwareMain: Int?
    var routingProfile: AhaKeyOLEDCompatibilityProfile
}

/// 集成测试 seam（仅 @testable 使用；生产恒为 nil）：免 BLE 驱动投影与事务执行。
struct AhaKeyAgentExecutionTestHooks {
    /// 非 nil 时覆盖设备就绪判断（applyConfigurationPackage 门控）。
    var isReady: Bool?
    /// 非 nil 时覆盖协商能力（planner 输入）。
    var capabilities: AhaKeyFirmwareCapabilities?
    /// 非 nil 时覆盖密封 OLED 兼容 context；优先于 capabilities 推导。
    var oledContext: AhaKeyOLEDCompatibilityContext?
    /// 非 nil 时覆盖发布功能投影（OLED 事务测试打开图片面；生产恒 nil）。
    var release: AhaKeyReleaseFeatureProjection?
    /// 非 nil 时替代 BLE 步骤执行（可观察 WAL 取消态、注入延迟）。
    var stepExecutor: (@Sendable (AhaKeyRuntimeStepIdentifier) async -> AhaKeyConfigurationStepResult)?
    /// 非 nil 时重定向 Runtime Store 到临时目录（测试隔离生产 WAL）。
    var storeDirectory: URL?
    /// 非 nil 时作为投影中的设备快照（deviceChanged 事件源）。
    var simulatedDevice: AhaKeyRuntimeDeviceSnapshot?
    /// 非 nil 时覆盖 transportCore.stableDeviceID（测试 0x00 parser→reducer→event 路径）。
    var stableDeviceID: String?
    /// 非 nil 时在 long-poll 已挂 waiter 的同一 MainActor 同步临界区内调用，
    /// 随后立即 replay 复查（R2-5 / R5；生产恒 nil）。
    var eventsLongPollGapHook: (@MainActor @Sendable () -> Void)?
    /// R4：会话已标 registering、尚未写入 waiter 时的异步屏障。
    var longPollBeforeRegisterHook: (@Sendable () async -> Void)?
    /// R4：long-poll continuation 已结束后、函数返回前的异步屏障（迟到取消清场）。
    var longPollAfterCompleteHook: (@Sendable () async -> Void)?
    /// C-1R2：命令时序 / 事务窗口配对观察（生产恒 nil）。
    var commandTrace: (@Sendable (AhaKeyAgentCommandTraceEvent) -> Void)?
    /// C-1R4：跳过 lighting/外设写出门控，仍走命令构造与真实 `transportCore.enqueue`。
    var skipStateCommandBLEWriteGates: Bool = false
    /// C-2R1：跳过 CoreBluetooth 外设写出，仍走 `writeConfigurationChunk` 的 0x81 waiter/ACK。
    var skipConfigurationBLEWriteGates: Bool = false
    /// 非 nil 时覆盖 peripheral/command/data 三特征是否齐全；优先于 skipBLE/`isReady` 虚拟特征。
    var configurationCharacteristics: AhaKeyConfigurationCharacteristicPresence?
    /// 非 nil 时覆盖 OLED notify 的当前 peripheral 身份（生产恒 nil，走 CBPeripheral.identifier）。
    var oledNotifyPeripheralID: UUID?
    /// 已成功 ACK 的 chunk 数达到该值后，下一次 write 抛 `failConfigurationChunkWith`。
    var failConfigurationWriteAfterAckCount: Int?
    /// 下一次 writeConfigurationChunk 立刻失败（一次性）。
    var failNextConfigurationChunk: Bool = false
    var failConfigurationChunkWith: AhaKeyAgentCommandError = .disconnected
    /// 测试 seam：skipBLE 仍走 `handlePictureWriteResult`；非 nil/非 0 注入真实 0x81 拒绝。
    var failConfigurationPictureWriteStatus: UInt8?
    /// 测试 seam：配置命令走与生产相同的 status≠0 拒绝点。nil/0 表示成功。
    var failConfigurationCommandStatus: UInt8?
    /// 非 nil 时只拒绝该 opcode；nil 表示任意配置命令。
    var failConfigurationCommandOpcode: UInt8?
    /// 每个 chunk 在 ACK 前调用（已确认成功次数）。
    var beforeConfigurationChunkWrite: (@Sendable (Int) async -> Void)?
    /// 生产 executor 进入 WAL 步、切完 currentStepID 之后、执行程序之前。
    var afterEnteringConfigurationStep: (@Sendable (AhaKeyRuntimeStepIdentifier) async -> Void)?
    /// 可注入单调 tick（纳秒）；nil 时用 `DispatchTime` uptime。
    var progressMonotonicNanos: (@Sendable () -> UInt64)?
}

enum AhaKeyAgentCommandTraceEvent: Equatable, Sendable {
    case sendState(UInt8)
    case enqueuedState(UInt8)
    case installStateReset(UInt8)
    case querySwitchState
    case transportWindowBegin
    case transportWindowEnd
}

/// 程序执行 seam：仅通过 MainActor 隔离方法触达 CoreBluetooth / waiter / upload session。
/// `@unchecked Sendable` 只覆盖 agent 身份指针，不授权跨域读写 BLE 可变状态。
private struct AgentProgramTransport: @unchecked Sendable, AhaKeyDeviceProgramTransport {
    let agent: AhaKeyAgent
    let store: AhaKeyRuntimePersistentStore
    let operationID: AhaKeyRuntimeOperationID
    let stepID: AhaKeyRuntimeStepIdentifier

    func sendCommand(_ frame: Data, expectingAck ack: UInt8) async throws {
        try await agent.sendConfigurationCommand(frame, expectingAck: ack)
    }

    func writeChunk(digest: AhaKeySHA256Digest, offset: Int, length: Int, sessionID: UInt16?) async throws {
        try await agent.writeConfigurationChunk(
            digest: digest, offset: offset, length: length, sessionID: sessionID, store: store
        )
        await MainActor.run {
            self.agent.noteConfirmedResourceChunk(
                operationID: self.operationID,
                stepID: self.stepID,
                bytes: UInt64(length)
            )
        }
    }

    func isCancellationRequested() async -> Bool {
        if await agent.programTransportIsDisconnected() { return true }
        do {
            guard let record = try await store.transaction(operationID) else { return true }
            return record.state == .cancellationRequested
        } catch {
            return true
        }
    }

    func abortActiveSession() async {
        await agent.abortConfigurationSession()
    }
}
