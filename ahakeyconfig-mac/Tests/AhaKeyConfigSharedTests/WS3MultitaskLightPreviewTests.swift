import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class WS3MultitaskLightPreviewTests: XCTestCase {
    func testPreviewRestoresPreviouslyEnabledMultiMode() async throws {
        var commands: [WS3PresentationCommand] = []
        try await WS3MultitaskLightPreview.run(restoreMode: .multi, activate: { $0() },
            send: { commands.append($0) }, sleep: { _ in }, cleanupFailed: { XCTFail() })
        XCTAssertEqual(commands.last, .setMode(.multi), "Preview must not disable an already enabled multitask mode")
    }

    func testThreeSessionPreviewIsBoundedAndClearsBeforeReturning() async throws {
        var activated = false, commands: [WS3PresentationCommand] = [], duration: Duration = .zero
        try await WS3MultitaskLightPreview.run(activate: { $0(); activated = true }, send: {
            XCTAssertTrue(activated); commands.append($0)
        }, sleep: { duration += $0 }, cleanupFailed: { XCTFail("cleanup") })
        XCTAssertEqual(duration, .seconds(10))
        XCTAssertEqual(commands.count, 6)
        for command in commands.prefix(4) {
            guard case .multi(let snapshot) = command else { return XCTFail("runtime snapshots only") }
            XCTAssertEqual(snapshot.slots.compactMap { $0 }.count, 3)
            XCTAssertNil(snapshot.slots[3])
        }
        XCTAssertEqual(commands.suffix(2), [.multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!), .setMode(.single)])
    }

    func testCancelStillClearsUnderUncancelledCleanupTask() async {
        var commands: [WS3PresentationCommand] = []
        var sleeping = false
        let task = Task {
            try await WS3MultitaskLightPreview.run(restoreMode: .multi, activate: { $0() }, send: {
                try Task.checkCancellation(); commands.append($0)
            }, sleep: { _ in
                sleeping = true
                try await Task.sleep(for: .seconds(100))
            }, cleanupFailed: { XCTFail("cleanup") })
        }
        while !sleeping { await Task.yield() }
        task.cancel()
        do { try await task.value; XCTFail("must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(commands.count, 3)
        XCTAssertEqual(commands.last, .setMode(.multi))
    }

    func testAmbiguousActivationFailureAttemptsCleanupAndSurfacesFailure() async {
        var commands: [WS3PresentationCommand] = []
        do {
            try await WS3MultitaskLightPreview.run(activate: { $0(); throw WS3PresentationError.timedOut },
                send: { commands.append($0) }, sleep: { _ in XCTFail() }, cleanupFailed: { XCTFail() })
            XCTFail("must fail")
        } catch { XCTAssertEqual(error as? WS3PresentationError, .timedOut) }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.last, .setMode(.single))
    }

    func testConnectionChangeStopsCleanupAndInvalidatesInsteadOfWritingNewDevice() async {
        var sends = 0, invalidated = 0
        do {
            try await WS3MultitaskLightPreview.run(activate: { $0() }, send: { _ in
                sends += 1
                throw WS3PresentationError.connectionChanged
            }, sleep: { _ in XCTFail() }, cleanupFailed: { invalidated += 1 })
            XCTFail("must fail")
        } catch { XCTAssertEqual(error as? WS3PresentationError, .connectionChanged) }
        XCTAssertEqual(sends, 2) // first snapshot + one failed cleanup validation; no retry
        XCTAssertEqual(invalidated, 1)
    }
    func testUnsupportedDeviceReceivesNoPreviewOrCleanupWrites() async {
        do {
            try await WS3MultitaskLightPreview.run(activate: { _ in throw WS3PresentationError.unsupported },
                send: { _ in XCTFail("unverified device must not receive any writes") },
                cleanupFailed: { XCTFail() })
            XCTFail("must fail")
        } catch { XCTAssertEqual(error as? WS3PresentationError, .unsupported) }
    }

}
