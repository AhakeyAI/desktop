import XCTest
@testable import AhaKeyConfigShared

private final class FakeModule: RuntimeModule, @unchecked Sendable {
    let id: RuntimeModuleID
    private(set) var status: RuntimeModuleStatus = .idle
    var startCalls = 0
    var stopCalls = 0

    init(id: RuntimeModuleID) { self.id = id }
    func start() async throws { startCalls += 1; status = .running }
    func stop() async { stopCalls += 1; status = .idle }
}

/// 带重叠探测的慢模块：start/stop 各挂起 10ms 制造宽重入窗口，
/// 任何并发交错都会推高 maxInFlight（对未串行化实现稳定失败）。
private final class GuardedModule: RuntimeModule, @unchecked Sendable {
    let id: RuntimeModuleID
    private(set) var status: RuntimeModuleStatus = .idle
    var startCalls = 0
    var stopCalls = 0
    private var inFlight = 0
    private(set) var maxInFlight = 0

    init(id: RuntimeModuleID) { self.id = id }

    func start() async throws {
        startCalls += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try? await Task.sleep(nanoseconds: 10_000_000)
        status = .running
        inFlight -= 1
    }

    func stop() async {
        stopCalls += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try? await Task.sleep(nanoseconds: 10_000_000)
        status = .idle
        inFlight -= 1
    }
}

/// 首次 start 失败、之后恢复的模块（重启恢复测试用）。
private final class FlakyModule: RuntimeModule, @unchecked Sendable {
    let id: RuntimeModuleID
    private(set) var status: RuntimeModuleStatus = .idle
    var startCalls = 0
    var failNextStart = true

    init(id: RuntimeModuleID) { self.id = id }
    func start() async throws {
        startCalls += 1
        if failNextStart {
            failNextStart = false
            status = .failed(.startFailed(module: id, underlying: "boom"))
            throw RuntimeModuleError.startFailed(module: id, underlying: "boom")
        }
        status = .running
    }
    func stop() async { status = .idle }
}

final class RuntimeOrchestratorTests: XCTestCase {

    private func makeOrchestrator() async -> (RuntimeOrchestrator, [RuntimeModuleID: FakeModule]) {
        let orchestrator = RuntimeOrchestrator()
        let fakes: [RuntimeModuleID: FakeModule] = [
            .ahaType: FakeModule(id: .ahaType),
            .aiIntegration: FakeModule(id: .aiIntegration),
            .dynamicLighting: FakeModule(id: .dynamicLighting),
            .powerProtection: FakeModule(id: .powerProtection),
        ]
        for fake in fakes.values { await orchestrator.register(fake) }
        return (orchestrator, fakes)
    }

    func testPolicyDrivesModuleStartStop() async {
        let (orchestrator, fakes) = await makeOrchestrator()

        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        policy.aiHooks.enabledTools = [.cursor]

        let t1 = await orchestrator.applyPolicy(policy)
        XCTAssertEqual(t1?.started, [.powerProtection, .aiIntegration])
        XCTAssertEqual(fakes[.powerProtection]?.status, .running)
        XCTAssertEqual(fakes[.aiIntegration]?.status, .running)
        XCTAssertEqual(fakes[.dynamicLighting]?.startCalls, 0, "未启用模块不得启动")
        let shouldStayResident = await orchestrator.shouldStayResident
        XCTAssertTrue(shouldStayResident)

        // 策略收窄：只剩防休眠
        policy.aiHooks.enabledTools = []
        let t2 = await orchestrator.applyPolicy(policy)
        XCTAssertEqual(t2?.stopped, [.aiIntegration])
        XCTAssertEqual(fakes[.aiIntegration]?.status, .idle)
        XCTAssertEqual(fakes[.powerProtection]?.status, .running, "保留模块不受影响")
    }

    func testSamePolicyProducesNoTransition() async {
        let (orchestrator, fakes) = await makeOrchestrator()
        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true

        _ = await orchestrator.applyPolicy(policy)
        let again = await orchestrator.applyPolicy(policy)
        XCTAssertNil(again, "相同策略零发布（正常轮询语义）")
        XCTAssertEqual(fakes[.powerProtection]?.startCalls, 1, "不得重复启动")
    }

    func testAllOffStopsEverythingAndEndsResidency() async {
        let (orchestrator, fakes) = await makeOrchestrator()
        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        policy.devicePresentation.ledEnabled = true
        _ = await orchestrator.applyPolicy(policy)

        let off = await orchestrator.applyPolicy(AhaKeyRuntimePolicy())
        XCTAssertEqual(off?.stopped, [.powerProtection, .dynamicLighting])
        XCTAssertEqual(off?.residencyChanged, false)
        let shouldStayResident = await orchestrator.shouldStayResident
        XCTAssertFalse(shouldStayResident, "全关闭后不常驻")
        XCTAssertTrue(fakes.values.allSatisfy { $0.status == .idle || $0.startCalls == 0 })
    }

    func testIndependentModulesDoNotShareWorkers() async {
        // 组合启用：每个模块只被 start 一次，无重复 worker
        let (orchestrator, fakes) = await makeOrchestrator()
        var policy = AhaKeyRuntimePolicy()
        policy.ahaType.enabled = true
        policy.aiHooks.enabledTools = [.kimi, .claude]
        policy.devicePresentation.oledEnabled = true
        policy.powerProtectionEnabled = true

        _ = await orchestrator.applyPolicy(policy)
        for fake in fakes.values {
            XCTAssertEqual(fake.startCalls, 1, "\(fake.id) 应恰好启动一次")
            XCTAssertEqual(fake.status, .running)
        }
    }

    func testStopAllForProcessExit() async {
        let (orchestrator, fakes) = await makeOrchestrator()
        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        _ = await orchestrator.applyPolicy(policy)

        await orchestrator.stopAll()
        XCTAssertEqual(fakes[.powerProtection]?.status, .idle)
        let shouldStayResident = await orchestrator.shouldStayResident
        XCTAssertFalse(shouldStayResident)
    }

    // MARK: - 切片 4：生命周期 / 重启恢复 / 竞态 / CPU 空转

    /// 竞态（确定性）：并发相同策略必须恰好 start 一次；交错开关策略不得出现
    /// start/stop 重叠（GuardedModule 宽重入窗口，未串行化实现稳定失败）。
    func testConcurrentPolicyApplicationIsDeterministic() async {
        let orchestrator = RuntimeOrchestrator()
        let guarded = GuardedModule(id: .powerProtection)
        await orchestrator.register(guarded)

        var on = AhaKeyRuntimePolicy()
        on.powerProtectionEnabled = true
        let off = AhaKeyRuntimePolicy()

        // 20 个并发相同策略：恰好一次 start
        await withTaskGroup(of: RuntimeModuleTransition?.self) { group in
            for _ in 0 ..< 20 {
                group.addTask { await orchestrator.applyPolicy(on) }
            }
            for await _ in group {}
        }
        XCTAssertEqual(guarded.startCalls, 1, "并发相同策略必须只启动一次")

        // 60 次交错开/关：任意串行序都合法，但不允许启停重叠
        await withTaskGroup(of: RuntimeModuleTransition?.self) { group in
            for i in 0 ..< 60 {
                group.addTask { await orchestrator.applyPolicy(i.isMultiple(of: 2) ? on : off) }
            }
            for await _ in group {}
        }
        XCTAssertEqual(guarded.maxInFlight, 1, "启停不得重叠（FIFO 链必须串行整段工作）")

        // 模块状态必须与最终 plan 一致
        let resident = await orchestrator.shouldStayResident
        XCTAssertEqual(guarded.status, resident ? .running : .idle, "模块状态必须与最终 plan 一致")
        XCTAssertLessThanOrEqual(guarded.startCalls, guarded.stopCalls + 1, "不得有悬而未停的 start")

        // 再应用等价策略：零工作
        let finalPolicy = resident ? on : off
        let starts = guarded.startCalls, stops = guarded.stopCalls
        let t = await orchestrator.applyPolicy(finalPolicy)
        XCTAssertNil(t)
        XCTAssertEqual(guarded.startCalls, starts)
        XCTAssertEqual(guarded.stopCalls, stops)
    }

    /// 重启恢复：模块 start 失败 → .failed；策略收窄再放开后可恢复运行。
    func testFailedModuleRecoversAfterPolicyCycle() async {
        let orchestrator = RuntimeOrchestrator()
        let flaky = FlakyModule(id: .powerProtection)
        await orchestrator.register(flaky)

        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true

        // 第一次启动失败：错误隔离，模块标 .failed，编排器仍可继续服役
        _ = await orchestrator.applyPolicy(policy)
        if case .failed = flaky.status {} else {
            XCTFail("首次启动应失败并标记 .failed，实际 \(flaky.status)")
        }

        // 策略收窄（全关）→ 停止失败模块；再放开 → 重新启动成功
        _ = await orchestrator.applyPolicy(AhaKeyRuntimePolicy())
        XCTAssertEqual(flaky.status, .idle)
        let t = await orchestrator.applyPolicy(policy)
        XCTAssertEqual(t?.started, [.powerProtection], "恢复必须真实发生 transition（调用方可发布）")
        XCTAssertEqual(flaky.status, .running)
        XCTAssertEqual(flaky.startCalls, 2)
    }

    /// CPU 空转：长时间同策略轮询零工作——无 transition、无重复 start/stop。
    func testRepeatedSamePolicyPollingIsZeroWork() async {
        let (orchestrator, fakes) = await makeOrchestrator()
        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        policy.aiHooks.enabledTools = [.cursor]
        _ = await orchestrator.applyPolicy(policy)

        // 模拟周期轮询 1000 次同策略
        for _ in 0 ..< 1000 {
            let t = await orchestrator.applyPolicy(policy)
            XCTAssertNil(t, "同策略轮询必须零发布")
        }
        XCTAssertEqual(fakes[.powerProtection]?.startCalls, 1, "轮询不得重复启动模块")
        XCTAssertEqual(fakes[.aiIntegration]?.startCalls, 1)
        XCTAssertEqual(fakes[.powerProtection]?.stopCalls, 0)
    }

    /// 生命周期幂等：stopAll 可重复调用；未注册的模块 ID 在 transition 中被安全忽略。
    func testLifecycleIdempotency() async {
        let orchestrator = RuntimeOrchestrator()
        let fake = FakeModule(id: .powerProtection)
        await orchestrator.register(fake)

        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        policy.devicePresentation.ledEnabled = true // dynamicLighting 未注册
        _ = await orchestrator.applyPolicy(policy)
        XCTAssertEqual(fake.status, .running, "已注册模块正常启动")
        let resident = await orchestrator.shouldStayResident
        XCTAssertTrue(resident, "未注册模块不影响常驻推导")

        await orchestrator.stopAll()
        await orchestrator.stopAll() // 幂等
        XCTAssertEqual(fake.status, .idle)
        XCTAssertEqual(fake.stopCalls, 1, "幂等 stopAll 不得重复 stop")

        // stopAll 后策略可重新驱动启动
        _ = await orchestrator.applyPolicy(policy)
        XCTAssertEqual(fake.status, .running)
        XCTAssertEqual(fake.startCalls, 2)
    }
}
