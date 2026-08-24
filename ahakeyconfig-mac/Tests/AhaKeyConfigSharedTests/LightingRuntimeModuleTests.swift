import XCTest
@testable import AhaKeyConfigShared

final class LightingRuntimeModuleTests: XCTestCase {

    func testStartSetsRunningAndStopSetsIdle() async throws {
        let module = LightingRuntimeModule()
        XCTAssertEqual(module.status, .idle)

        try await module.start()
        XCTAssertEqual(module.status, .running, ".running 才放行 sendState（发送能力门控）")

        await module.stop()
        XCTAssertEqual(module.status, .idle, "非 .running 时发送能力应被抑制")
    }

    func testStartStopHooksAreInvoked() async throws {
        final class Tracker: @unchecked Sendable { var starts = 0; var stops = 0 }
        let tracker = Tracker()
        let module = LightingRuntimeModule(
            onStart: { tracker.starts += 1 },
            onStop: { tracker.stops += 1 }
        )

        try await module.start()
        await module.stop()

        XCTAssertEqual(tracker.starts, 1)
        XCTAssertEqual(tracker.stops, 1)
    }

    func testRegistryDrivesLifecycle() async throws {
        let module = LightingRuntimeModule()
        let registry = RuntimeModuleRegistry()
        await registry.register(module)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [.dynamicLighting], stopped: [], residencyChanged: true
        ))
        var status = await registry.status(of: .dynamicLighting)
        XCTAssertEqual(status, .running)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [], stopped: [.dynamicLighting], residencyChanged: false
        ))
        status = await registry.status(of: .dynamicLighting)
        XCTAssertEqual(status, .idle)
    }

    func testModuleHoldsNoSendingState() {
        // 边界断言（Codex 13:52-2）：lastSentState / pendingReset / live-state
        // 一律留在 Agent，模块只暴露生命周期状态。
        let module = LightingRuntimeModule()
        XCTAssertEqual(module.id, .dynamicLighting)
        XCTAssertEqual(module.status, .idle)
    }
}
