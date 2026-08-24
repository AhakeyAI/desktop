import XCTest
@testable import AhaKeyConfigShared

final class RuntimeOrchestratorCoreTests: XCTestCase {

    // MARK: - 策略 → 模块集合

    func testAllEnhancementsOffYieldsEmptyPlanAndNoResidency() {
        let plan = RuntimeOrchestratorCore.plan(for: AhaKeyRuntimePolicy())
        XCTAssertTrue(plan.desiredModules.isEmpty)
        XCTAssertFalse(plan.shouldStayResident, "全部增强关闭时不得无条件常驻")
    }

    func testEachPolicyToggleMapsToItsModule() {
        var policy = AhaKeyRuntimePolicy()

        policy.ahaType.enabled = true
        XCTAssertEqual(RuntimeOrchestratorCore.plan(for: policy).desiredModules, [.ahaType])

        policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.cursor]
        XCTAssertEqual(RuntimeOrchestratorCore.plan(for: policy).desiredModules, [.aiIntegration])

        policy = AhaKeyRuntimePolicy()
        policy.devicePresentation.ledEnabled = true
        XCTAssertEqual(RuntimeOrchestratorCore.plan(for: policy).desiredModules, [.dynamicLighting])

        policy = AhaKeyRuntimePolicy()
        policy.devicePresentation.oledEnabled = true
        XCTAssertEqual(RuntimeOrchestratorCore.plan(for: policy).desiredModules, [.dynamicLighting])

        policy = AhaKeyRuntimePolicy()
        policy.powerProtectionEnabled = true
        XCTAssertEqual(RuntimeOrchestratorCore.plan(for: policy).desiredModules, [.powerProtection])
    }

    func testCombinedPolicyYieldsUnionAndResidency() {
        var policy = AhaKeyRuntimePolicy()
        policy.ahaType.enabled = true
        policy.powerProtectionEnabled = true
        let plan = RuntimeOrchestratorCore.plan(for: policy)
        XCTAssertEqual(plan.desiredModules, [.ahaType, .powerProtection])
        XCTAssertTrue(plan.shouldStayResident)
    }

    // MARK: - 变更才发布

    func testTransitionIsNilWhenPlanUnchanged() {
        var policy = AhaKeyRuntimePolicy()
        policy.aiHooks.enabledTools = [.claude]
        let plan = RuntimeOrchestratorCore.plan(for: policy)
        XCTAssertNil(RuntimeOrchestratorCore.transition(from: plan, to: plan),
                     "正常轮询零发布：plan 无事实变化时不得产生事件")
    }

    func testTransitionReportsStartedAndStoppedModules() {
        let empty = RuntimeModulePlan(desiredModules: [])
        let active = RuntimeModulePlan(desiredModules: [.aiIntegration, .dynamicLighting])

        let startup = RuntimeOrchestratorCore.transition(from: empty, to: active)
        XCTAssertEqual(startup?.started, [.aiIntegration, .dynamicLighting])
        XCTAssertEqual(startup?.stopped, [])
        XCTAssertEqual(startup?.residencyChanged, true)

        let shutdown = RuntimeOrchestratorCore.transition(from: active, to: empty)
        XCTAssertEqual(shutdown?.started, [])
        XCTAssertEqual(shutdown?.stopped, [.aiIntegration, .dynamicLighting])
        XCTAssertEqual(shutdown?.residencyChanged, false)
    }

    func testModuleSwapWithoutResidencyChange() {
        let a = RuntimeModulePlan(desiredModules: [.ahaType])
        let b = RuntimeModulePlan(desiredModules: [.powerProtection])
        let transition = RuntimeOrchestratorCore.transition(from: a, to: b)
        XCTAssertEqual(transition?.started, [.powerProtection])
        XCTAssertEqual(transition?.stopped, [.ahaType])
        XCTAssertNil(transition?.residencyChanged, "常驻性未变化时不得发布常驻事件")
    }
}
