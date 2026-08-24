import XCTest
@testable import AhaKeyConfigShared

private final class CallTracker: @unchecked Sendable {
    var startCalled = false
    var stopCalled = false
}

final class PowerProtectionRuntimeModuleTests: XCTestCase {

    func testStartInvokesOnStartAndSetsRunning() async throws {
        let tracker = CallTracker()
        let module = PowerProtectionRuntimeModule(
            onStart: { tracker.startCalled = true },
            onStop: { }
        )

        try await module.start()

        XCTAssertTrue(tracker.startCalled)
        XCTAssertEqual(module.status, .running)
    }

    func testStopInvokesOnStopAndSetsIdle() async {
        let tracker = CallTracker()
        let module = PowerProtectionRuntimeModule(
            onStart: { },
            onStop: { tracker.stopCalled = true }
        )

        await module.stop()

        XCTAssertTrue(tracker.stopCalled)
        XCTAssertEqual(module.status, .idle)
    }

    func testRegistryIntegration() async throws {
        let tracker = CallTracker()
        let module = PowerProtectionRuntimeModule(
            onStart: { tracker.startCalled = true },
            onStop: { tracker.stopCalled = true }
        )
        let registry = RuntimeModuleRegistry()
        await registry.register(module)

        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [.powerProtection], stopped: [], residencyChanged: true
        ))
        XCTAssertTrue(tracker.startCalled)
        let statusAfterStart = await registry.status(of: .powerProtection)
        XCTAssertEqual(statusAfterStart, .running)

        _ = await registry.applyTransition(RuntimeModuleTransition(
            started: [], stopped: [.powerProtection], residencyChanged: false
        ))
        XCTAssertTrue(tracker.stopCalled)
        let statusAfterStop = await registry.status(of: .powerProtection)
        XCTAssertEqual(statusAfterStop, .idle)
    }
}
