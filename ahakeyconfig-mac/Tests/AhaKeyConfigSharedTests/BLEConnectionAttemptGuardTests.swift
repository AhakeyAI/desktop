import XCTest
@testable import AhaKeyConfigShared

final class BLEConnectionAttemptGuardTests: XCTestCase {
    func testNewDeviceTimeoutRequiresCancellationAndUserRetry() throws {
        var guardState = BLEConnectionAttemptGuard()
        let id = UUID()
        let attempt = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: false))
        XCTAssertNil(guardState.begin(target: id, retryAutomatically: false))
        XCTAssertTrue(guardState.timeOut(attempt))
        XCTAssertTrue(guardState.requiresManualRetry)
        XCTAssertFalse(guardState.connected(target: id), "late connect must be cancelled")
        XCTAssertFalse(guardState.resumeByUser(), "wait for native cancellation completion")
        XCTAssertFalse(guardState.ended(target: UUID()))
        XCTAssertTrue(guardState.ended(target: id))
        XCTAssertNil(guardState.begin(target: id, retryAutomatically: false))
        XCTAssertTrue(guardState.resumeByUser())
        let next = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: false))
        XCTAssertFalse(guardState.timeOut(attempt), "old timer cannot cancel a new attempt")
        XCTAssertTrue(guardState.timeOut(next))
    }
    func testRememberedDeviceCanRetryOnlyAfterCancellationCompletes() throws {
        var guardState = BLEConnectionAttemptGuard()
        let id = UUID()
        let attempt = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: true))
        XCTAssertTrue(guardState.timeOut(attempt))
        XCTAssertFalse(guardState.requiresManualRetry)
        XCTAssertNil(guardState.begin(target: id, retryAutomatically: true))
        XCTAssertFalse(guardState.connected(target: id))
        XCTAssertTrue(guardState.ended(target: id))
        XCTAssertNotNil(guardState.begin(target: id, retryAutomatically: true))
    }
    func testSuccessfulConnectionMakesOldDeadlineHarmless() throws {
        var guardState = BLEConnectionAttemptGuard()
        let id = UUID()
        let attempt = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: false))
        XCTAssertFalse(guardState.connected(target: UUID()))
        XCTAssertTrue(guardState.connected(target: id))
        XCTAssertFalse(guardState.timeOut(attempt))
        XCTAssertFalse(guardState.resumeByUser())
        XCTAssertTrue(guardState.ended(target: id))
        XCTAssertTrue(guardState.mayBegin)
    }
    func testResetRevokesOldTimersAndLateCallbacks() throws {
        var guardState = BLEConnectionAttemptGuard()
        let id = UUID()
        let attempt = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: false))
        guardState.reset()
        XCTAssertFalse(guardState.timeOut(attempt))
        XCTAssertFalse(guardState.connected(target: id))
        XCTAssertFalse(guardState.ended(target: id))
        XCTAssertTrue(guardState.mayBegin)
    }
    func testEarlyFailurePausesOnlyPreviouslyUnconnectedDevice() throws {
        for remembered in [false, true] {
            var guardState = BLEConnectionAttemptGuard()
            let id = UUID()
            let attempt = try XCTUnwrap(guardState.begin(target: id, retryAutomatically: remembered))
            XCTAssertTrue(guardState.ended(target: id))
            XCTAssertEqual(guardState.requiresManualRetry, !remembered)
            XCTAssertFalse(guardState.timeOut(attempt))
        }
    }
}
