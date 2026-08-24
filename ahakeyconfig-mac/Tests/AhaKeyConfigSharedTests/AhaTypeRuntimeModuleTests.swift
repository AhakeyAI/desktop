import XCTest
@testable import AhaKeyConfigShared

final class AhaTypeRuntimeModuleTests: XCTestCase {

    func testPolicyMappingProducesAhaTypeModule() {
        // seam 锚点：策略开启 AhaType → 编排计划包含 .ahaType（切片 1 核心语义复验）
        var policy = AhaKeyRuntimePolicy()
        XCTAssertFalse(RuntimeOrchestratorCore.plan(for: policy).desiredModules.contains(.ahaType))
        policy.ahaType.enabled = true
        XCTAssertTrue(RuntimeOrchestratorCore.plan(for: policy).desiredModules.contains(.ahaType))
    }

    func testLifecycleViaRegistry() async throws {
        final class Tracker: @unchecked Sendable { var starts = 0; var stops = 0 }
        let tracker = Tracker()
        let module = AhaTypeRuntimeModule(
            onStart: { tracker.starts += 1 },
            onStop: { tracker.stops += 1 }
        )
        let registry = RuntimeModuleRegistry()
        await registry.register(module)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [.ahaType], stopped: [], residencyChanged: true
        ))
        var status = await registry.status(of: .ahaType)
        XCTAssertEqual(status, .running)
        XCTAssertEqual(tracker.starts, 1)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [], stopped: [.ahaType], residencyChanged: false
        ))
        status = await registry.status(of: .ahaType)
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(tracker.stops, 1)
    }

    func testFailureIsolationAppliesToAhaType() async {
        // 与其他模块一致的错误隔离语义：本模块 start 失败不影响其他模块
        let registry = RuntimeModuleRegistry()
        await registry.register(AhaTypeRuntimeModule())
        await registry.applyTransition(RuntimeModuleTransition(
            started: [.ahaType, .powerProtection], stopped: [], residencyChanged: true
        ))
        let status = await registry.status(of: .ahaType)
        XCTAssertEqual(status, .running)
    }
}
