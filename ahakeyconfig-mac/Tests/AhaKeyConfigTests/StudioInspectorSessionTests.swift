import XCTest
@testable import AhaKeyConfig

@MainActor
final class StudioInspectorSessionTests: XCTestCase {
    private final class Device {
        var revision: UInt64 = 1
        var generation: UInt64 = 10
        var deviceID = "keyboard-A"
        var ready = true
        var begins = 0
        var releases = 0
        var pauses = 0
        var onPause: (() async throws -> Void)?
        func access() -> StudioInspectorSession.Access {
            .init(begin: { self.begins += 1; return self.revision },
                  isCurrent: { $0 == self.revision }, isReady: { self.ready },
                  generation: { self.generation }, deviceID: { self.deviceID },
                  release: { _ in self.releases += 1 }, pause: {
                      self.pauses += 1
                      if let action = self.onPause { try await action() }
                      else { self.ready = true }
                  })
        }
    }

    func testReadOnlyOperationAcquiresAndReturnsLeaseOnce() async throws {
        let device = Device(), targetMode = 3, targetKey = 2
        let session = StudioInspectorSession(access: device.access())
        let result = try await session.withConnection(expectedDeviceID: "keyboard-A") { context in
            XCTAssertTrue(session.isBusy)
            XCTAssertEqual(context.generation, 10)
            return [targetMode, targetKey]
        }
        XCTAssertEqual(result, [3, 2])
        XCTAssertEqual(device.begins, 1); XCTAssertEqual(device.releases, 1)
        XCTAssertEqual(device.pauses, 0); XCTAssertFalse(session.isBusy)
    }

    func testTimeoutDoesNotStartOperationAndReturnsLease() async {
        let device = Device(); device.ready = false
        let session = StudioInspectorSession(access: device.access(), timeout: .zero)
        do {
            _ = try await session.withConnection { _ in XCTFail("No ready connection"); return 1 }
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .connectionTimeout) }
        XCTAssertEqual(device.releases, 1); XCTAssertFalse(session.isBusy)
    }

    func testReadinessWaitIsBoundedAndChecksOwnershipBeforeStartingIO() async {
        let device = Device(); device.ready = false
        device.onPause = { device.ready = true; device.revision += 1 }
        let session = StudioInspectorSession(access: device.access())
        do {
            _ = try await session.withConnection { _ in XCTFail("Stale owner"); return 1 }
            XCTFail("Expected ownership failure")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .ownershipChanged) }
        XCTAssertEqual(device.pauses, 1); XCTAssertEqual(device.releases, 0)
    }

    func testOwnershipChangedDuringIOCannotPublishSuccessOrReleaseNewOwner() async {
        let device = Device()
        // Retain the actual adapter owner for this session.
        let actual = StudioInspectorSession(access: device.access())
        do {
            _ = try await actual.withConnection { _ in device.revision += 2; return 1 }
            XCTFail("Expected ownership failure")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .ownershipChanged) }
        XCTAssertEqual(device.releases, 0); XCTAssertFalse(actual.isBusy)
    }

    func testReconnectOrDifferentDeviceRejectsOldResult() async {
        for changeDevice in [false, true] {
            let device = Device(); let session = StudioInspectorSession(access: device.access())
            do {
                _ = try await session.withConnection { _ in
                    if changeDevice { device.deviceID = "keyboard-B" }
                    else { device.generation += 1 }
                    return 1
                }
                XCTFail("Expected invalidated result")
            } catch {
                XCTAssertEqual(error as? StudioInspectorSession.Failure, changeDevice ? .deviceChanged : .sessionChanged)
            }
            XCTAssertEqual(device.releases, 1)
        }
    }

    func testDeviceMismatchBeforeIORejectsDraftFromAnotherKeyboard() async {
        let device = Device(); let session = StudioInspectorSession(access: device.access())
        do {
            _ = try await session.withConnection(expectedDeviceID: "keyboard-B") { _ in XCTFail("Wrong device"); return 1 }
            XCTFail("Expected device failure")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .deviceChanged) }
        XCTAssertEqual(device.releases, 1)
    }

    func testThrowingOperationReturnsLeaseWithoutClaimingRollback() async {
        struct WriteFailed: Error {}
        let device = Device(); let session = StudioInspectorSession(access: device.access())
        do {
            _ = try await session.withConnection { _ -> Int in throw WriteFailed() }
            XCTFail("Expected error")
        } catch { XCTAssertTrue(error is WriteFailed) }
        XCTAssertEqual(device.releases, 1); XCTAssertFalse(session.isBusy)
    }

    func testCancellationDuringWaitReturnsLeaseAndNeverStartsIO() async {
        let device = Device(); device.ready = false
        let entered = expectation(description: "Waiting")
        device.onPause = { entered.fulfill(); try await Task.sleep(for: .seconds(60)) }
        let session = StudioInspectorSession(access: device.access())
        let task = Task { try await session.withConnection { _ in XCTFail("Cancelled"); return 1 } }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(device.releases, 1); XCTAssertFalse(session.isBusy)
    }

    func testConcurrentOperationCannotStealActiveLease() async throws {
        let device = Device(); let session = StudioInspectorSession(access: device.access())
        let entered = expectation(description: "Reading")
        var resume: CheckedContinuation<Void, Never>?
        let task = Task {
            try await session.withConnection { _ in
                entered.fulfill()
                await withCheckedContinuation { resume = $0 }
                return 1
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        do { _ = try await session.withConnection { _ in 2 }; XCTFail("Expected busy") }
        catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .busy) }
        XCTAssertEqual(device.begins, 1); XCTAssertEqual(device.releases, 0)
        resume?.resume(); let result = try await task.value; XCTAssertEqual(result, 1)
        XCTAssertEqual(device.releases, 1)
    }
}
