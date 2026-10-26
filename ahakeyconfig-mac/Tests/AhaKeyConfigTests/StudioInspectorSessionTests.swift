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

    func testPreparationFinishesBeforeIOAndCannotReleaseANewerOwner() async throws {
        let device = Device()
        var prepared = false
        var access = device.access()
        access.prepare = { prepared = true }
        let session = StudioInspectorSession(access: access)
        _ = try await session.withConnection { _ in XCTAssertTrue(prepared); return 1 }
        XCTAssertEqual(device.releases, 1)
        access.prepare = { device.revision += 1 }
        let changed = StudioInspectorSession(access: access)
        do {
            _ = try await changed.withConnection { _ in XCTFail("Changed owner during preparation"); return 1 }
            XCTFail("Expected ownership change")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .ownershipChanged) }
        XCTAssertEqual(device.releases, 1)
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

    func testEditingVisitPinsDeviceWithoutHoldingConnectionAndRejectsAnotherKeyboard() async throws {
        let device = Device()
        let actual = StudioInspectorSession(access: device.access())
        XCTAssertTrue(actual.beginEditing(deviceID: device.deviceID))
        XCTAssertFalse(actual.beginEditing(deviceID: "keyboard-B"))
        XCTAssertEqual(actual.editingDeviceID, "keyboard-A")
        XCTAssertFalse(actual.isBusy)
        XCTAssertEqual(device.begins, 0)
        _ = try await actual.withConnection { _ in 1 }
        device.deviceID = "keyboard-B"
        // A fresh capability read outside the Inspector may see B. Even an
        // explicit B expectation must not override this visit's captured A.
        do {
            _ = try await actual.withConnection(expectedDeviceID: "keyboard-B") { _ in XCTFail("Wrong keyboard"); return 1 }
            XCTFail("Expected device change")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .deviceChanged) }
        XCTAssertEqual(actual.editingDeviceID, "keyboard-A")
        XCTAssertEqual(device.releases, 2)
        actual.endEditing()
        XCTAssertTrue(actual.beginEditing(deviceID: "keyboard-B"))
        _ = try await actual.withConnection { context in XCTAssertEqual(context.deviceID, "keyboard-B") }
    }

    func testInitiallyUnknownEditingTargetIsBoundOnlyByFirstInspectorConnection() async throws {
        let device = Device()
        let actual = StudioInspectorSession(access: device.access())
        XCTAssertTrue(actual.beginEditing(deviceID: nil))
        XCTAssertNil(actual.editingDeviceID)
        _ = try await actual.withConnection { _ in XCTAssertEqual(actual.editingDeviceID, "keyboard-A") }
        device.deviceID = "keyboard-B"
        do {
            _ = try await actual.withConnection { _ in XCTFail("Must retain first binding"); return 1 }
            XCTFail("Expected device change")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .deviceChanged) }
        XCTAssertEqual(actual.editingDeviceID, "keyboard-A")
        XCTAssertEqual(device.releases, 2)
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
    func testCancelledQueuedTaskNeverAcquiresConnection() async {
        let device = Device(); let session = StudioInspectorSession(access: device.access())
        // The task inherits MainActor and cannot begin before this synchronous
        // turn cancels it (the Inspector replacing a queued operation).
        let task = Task { try await session.withConnection { _ in XCTFail("Stale queued operation"); return 1 } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(device.begins, 0); XCTAssertEqual(device.releases, 0)
        XCTAssertFalse(session.isBusy)
    }

}
