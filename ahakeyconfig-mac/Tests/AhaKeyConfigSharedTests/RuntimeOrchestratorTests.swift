import XCTest
@testable import AhaKeyConfigShared

// MARK: - Test Fixtures

private final class TestModule: RuntimeModule, @unchecked Sendable {
    let id: RuntimeModuleID
    private(set) var status: RuntimeModuleStatus = .idle
    var shouldFailStart = false
    var startCallCount = 0

    init(id: RuntimeModuleID) {
        self.id = id
    }

    func start() async throws {
        startCallCount += 1
        if shouldFailStart {
            throw RuntimeModuleError.startFailed(module: id, underlying: "injected-start-failure")
        }
        status = .running
    }

    func stop() async {
        status = .idle
    }
}

// MARK: - Tests

final class RuntimeOrchestratorTests: XCTestCase {
    private var registry: RuntimeModuleRegistry!
    private var orchestrator: RuntimeOrchestrator!

    override func setUp() async throws {
        registry = RuntimeModuleRegistry()
        orchestrator = RuntimeOrchestrator(registry: registry)
    }

    override func tearDown() async throws {
        await registry?.stopAll()
    }

    // MARK: - 初始状态

    func testInitialPolicyAllOffYieldsNoResidency() async {
        let o = RuntimeOrchestrator(registry: registry, initialPolicy: AhaKeyRuntimePolicy())
        let shouldStayResident = await o.shouldStayResident
        XCTAssertFalse(shouldStayResident)
        let snap = await o.snapshot()
        XCTAssertTrue(snap.isEmpty || snap.values.allSatisfy { $0 == .idle })
    }

    // MARK: - 策略更新 → 模块启停

    func testUpdatePolicyStartsModules() async {
        let module = TestModule(id: .aiIntegration)
        await registry.register(module)

        var policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.cursor]

        let transition = await orchestrator.updatePolicy(policy)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.started, [.aiIntegration])
        let shouldStayResident = await orchestrator.shouldStayResident
        XCTAssertTrue(shouldStayResident)
    }

    func testUpdatePolicyStopsModules() async {
        let aiModule = TestModule(id: .aiIntegration)
        let ppModule = TestModule(id: .powerProtection)
        await registry.register(aiModule)
        await registry.register(ppModule)

        var initial = AhaKeyRuntimePolicy()
        initial.aiHooks.enabledTools = [.cursor]
        initial.powerProtectionEnabled = true
        await orchestrator.updatePolicy(initial)

        var next = AhaKeyRuntimePolicy()
        next.aiHooks.enabledTools = [.cursor] // keep ai

        let transition = await orchestrator.updatePolicy(next)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.stopped, [.powerProtection])
    }

    func testNoTransitionWhenPolicyUnchanged() async {
        let module = TestModule(id: .ahaType)
        await registry.register(module)

        var policy = AhaKeyRuntimePolicy()
        policy.ahaType.enabled = true

        let t1 = await orchestrator.updatePolicy(policy)
        XCTAssertNotNil(t1)

        let t2 = await orchestrator.updatePolicy(policy)
        XCTAssertNil(t2)
    }

    func testShouldExitWhenAllEnhancementsOff() async {
        let module = TestModule(id: .aiIntegration)
        await registry.register(module)

        var policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.kimi]
        await orchestrator.updatePolicy(policy)
        let shouldStayResident1 = await orchestrator.shouldStayResident
        XCTAssertTrue(shouldStayResident1)

        let transition = await orchestrator.updatePolicy(AhaKeyRuntimePolicy())
        XCTAssertNotNil(transition)
        let shouldStayResident2 = await orchestrator.shouldStayResident
        XCTAssertFalse(shouldStayResident2)
    }

    // MARK: - 组合启停与重复 worker 防护

    func testCombinedPolicyStartsMultipleModules() async {
        let ahaModule = TestModule(id: .ahaType)
        let aiModule = TestModule(id: .aiIntegration)
        let ppModule = TestModule(id: .powerProtection)
        await registry.register(ahaModule)
        await registry.register(aiModule)
        await registry.register(ppModule)

        var policy = AhaKeyRuntimePolicy()
        policy.ahaType.enabled = true
        policy.aiHooks.enabledTools = [.claude]
        policy.powerProtectionEnabled = true

        let transition = await orchestrator.updatePolicy(policy)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.started, [.ahaType, .aiIntegration, .powerProtection])
        let shouldStayResident = await orchestrator.shouldStayResident
        XCTAssertTrue(shouldStayResident)
    }

    func testRepeatedUpdateDoesNotDuplicateStart() async {
        let module = TestModule(id: .dynamicLighting)
        await registry.register(module)

        var policy = AhaKeyRuntimePolicy()
        policy.devicePresentation.ledEnabled = true

        let t1 = await orchestrator.updatePolicy(policy)
        XCTAssertNotNil(t1)
        XCTAssertEqual(t1?.started, [.dynamicLighting])

        let t2 = await orchestrator.updatePolicy(policy)
        XCTAssertNil(t2)
    }

    // MARK: - Snapshot

    func testSnapshotReflectsRunningModules() async {
        let module = TestModule(id: .powerProtection)
        await registry.register(module)

        var policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        await orchestrator.updatePolicy(policy)

        let snap = await orchestrator.snapshot()
        XCTAssertEqual(snap[.powerProtection], .running)
    }
}
