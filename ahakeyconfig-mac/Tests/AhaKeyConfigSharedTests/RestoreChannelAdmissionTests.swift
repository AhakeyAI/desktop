import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class RestoreChannelAdmissionTests: XCTestCase {
    enum ProbeFailure: Error { case changed }

    func testConnectionBootstrapTurnDrainsBeforeRestoreAdmission() async throws {
        let turns = CommandTurnQueue()
        let bootstrap = try await turns.acquire()
        var pauses = 0
        try await RestoreChannelAdmission.waitUntilIdle(isIdle: { !turns.isOccupied }, checkSession: {}, pause: {
            pauses += 1
            XCTAssertTrue(turns.isCurrent(bootstrap), "Waiting must not steal or reset the in-flight read")
            turns.release(bootstrap)
        })
        XCTAssertEqual(pauses, 1)
        XCTAssertFalse(turns.isOccupied)
    }

    func testIdleChannelDoesNotPause() async throws {
        try await RestoreChannelAdmission.waitUntilIdle(isIdle: { true }, checkSession: {}, pause: {
            XCTFail("Already idle")
        })
    }

    func testBlockedChannelTimesOutWithoutClearingItsOwner() async throws {
        let turns = CommandTurnQueue()
        let owner = try await turns.acquire()
        defer { turns.release(owner) }
        do {
            try await RestoreChannelAdmission.waitUntilIdle(timeout: .zero,
                isIdle: { !turns.isOccupied }, checkSession: {}, pause: { XCTFail("Deadline expired") })
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is RestoreChannelAdmission.Failure) }
        XCTAssertTrue(turns.isCurrent(owner))
    }

    func testSessionChangeAfterDrainCannotAdmitRestore() async throws {
        var changed = false
        var idle = false
        do {
            try await RestoreChannelAdmission.waitUntilIdle(isIdle: { idle }, checkSession: {
                if changed { throw ProbeFailure.changed }
            }, pause: { idle = true; changed = true })
            XCTFail("Old generation or newly occupied configuration must be rejected")
        } catch { XCTAssertTrue(error is ProbeFailure) }
    }

    func testCancellationDoesNotConsumeOrClearCommandTurn() async throws {
        let turns = CommandTurnQueue()
        let owner = try await turns.acquire()
        defer { turns.release(owner) }
        let task = Task { @MainActor in
            try await RestoreChannelAdmission.waitUntilIdle(isIdle: { !turns.isOccupied }, checkSession: {}, pause: {
                throw CancellationError()
            })
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(turns.isCurrent(owner))
    }
}
