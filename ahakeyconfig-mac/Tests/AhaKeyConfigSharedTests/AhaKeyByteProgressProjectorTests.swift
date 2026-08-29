import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyByteProgressProjectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testConfirmedChunksAdvanceMonotonicallyFromZero() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 1000)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 100, now: start))
        XCTAssertEqual(projector.completedBytes, 100)
        XCTAssertFalse(projector.confirmChunk(stepID: step, bytes: 100, now: start.addingTimeInterval(0.05)))
        XCTAssertEqual(projector.completedBytes, 200)
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 50, now: start.addingTimeInterval(0.25)))
        XCTAssertEqual(projector.completedBytes, 250)
        XCTAssertEqual(projector.currentStepID, step)
    }

    func testThreeResourcesKeepPackageCompletedMonotonic() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 300)
        let a = try AhaKeyRuntimeStepIdentifier("resource:a")
        let b = try AhaKeyRuntimeStepIdentifier("resource:b")
        let c = try AhaKeyRuntimeStepIdentifier("resource:c")
        XCTAssertTrue(projector.confirmChunk(stepID: a, bytes: 100, now: start))
        XCTAssertTrue(projector.confirmChunk(stepID: b, bytes: 100, now: start.addingTimeInterval(0.3)))
        XCTAssertTrue(projector.confirmChunk(stepID: c, bytes: 100, now: start.addingTimeInterval(0.6)))
        XCTAssertEqual(projector.completedBytes, 300)
        XCTAssertEqual(projector.currentStepID, c)
    }

    func testFailureDoesNotAdvancePastLastConfirmedChunk() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 500)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 120, now: start))
        XCTAssertFalse(projector.publishTerminal(now: start.addingTimeInterval(1)))
        XCTAssertEqual(projector.completedBytes, 120)
        XCTAssertEqual(projector.overlay(AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .failedWithoutWrites
        )).completedBytes, 120)
    }

    func testIdenticalProgressDoesNotPublish() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 200)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 0, now: start))
        XCTAssertFalse(projector.confirmChunk(stepID: step, bytes: 0, now: start.addingTimeInterval(1)))
    }

    func testOverlayLeavesSummaryUntouchedWhenTotalIsZero() throws {
        let projector = AhaKeyByteProgressProjector(totalBytes: 0)
        let summary = AhaKeyRuntimeOperationSummary(
            id: AhaKeyRuntimeOperationID(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            state: .running,
            completedSteps: 0,
            totalSteps: 7
        )
        XCTAssertEqual(projector.overlay(summary), summary)
    }
}
