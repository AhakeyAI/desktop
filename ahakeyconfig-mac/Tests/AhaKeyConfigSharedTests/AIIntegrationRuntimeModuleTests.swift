import XCTest
@testable import AhaKeyConfigShared

private final class CallTracker: @unchecked Sendable {
    var startCalls = 0
    var stopCalls = 0
}

final class AIIntegrationRuntimeModuleTests: XCTestCase {

    func testStartInvokesOnStartAndSetsRunning() async throws {
        let tracker = CallTracker()
        let module = AIIntegrationRuntimeModule(
            onStart: { tracker.startCalls += 1 },
            onStop: { }
        )

        try await module.start()

        XCTAssertEqual(tracker.startCalls, 1)
        XCTAssertEqual(module.status, .running)
    }

    func testStopInvokesOnStopAndSetsIdle() async {
        let tracker = CallTracker()
        let module = AIIntegrationRuntimeModule(
            onStart: { },
            onStop: { tracker.stopCalls += 1 }
        )
        try? await module.start()

        await module.stop()

        XCTAssertEqual(tracker.stopCalls, 1)
        XCTAssertEqual(module.status, .idle)
    }

    func testRegistryDrivesModuleThroughTransitionWithIsolation() async {
        let tracker = CallTracker()
        let module = AIIntegrationRuntimeModule(
            onStart: { tracker.startCalls += 1 },
            onStop: { tracker.stopCalls += 1 }
        )
        let registry = RuntimeModuleRegistry()
        await registry.register(module)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [.aiIntegration], stopped: [], residencyChanged: true
        ))
        var status = await registry.status(of: .aiIntegration)
        XCTAssertEqual(status, .running)
        XCTAssertEqual(tracker.startCalls, 1)

        await registry.applyTransition(RuntimeModuleTransition(
            started: [], stopped: [.aiIntegration], residencyChanged: false
        ))
        status = await registry.status(of: .aiIntegration)
        XCTAssertEqual(status, .idle)
        XCTAssertEqual(tracker.stopCalls, 1)
    }
}
