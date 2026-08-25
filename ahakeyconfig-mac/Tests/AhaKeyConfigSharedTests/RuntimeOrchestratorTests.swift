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
}
