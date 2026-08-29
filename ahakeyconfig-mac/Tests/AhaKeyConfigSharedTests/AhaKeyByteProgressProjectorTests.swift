import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyByteProgressProjectorTests: XCTestCase {
    private let start: UInt64 = 1_000_000_000

    func testConfirmedChunksAdvanceMonotonicallyFromZero() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 1000)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 100, nowNanos: start))
        XCTAssertEqual(projector.completedBytes, 100)
        XCTAssertFalse(projector.confirmChunk(stepID: step, bytes: 100, nowNanos: start + 50_000_000))
        XCTAssertEqual(projector.completedBytes, 200)
        XCTAssertTrue(projector.confirmChunk(
            stepID: step, bytes: 50, nowNanos: start + AhaKeyByteProgressProjector.minimumPublishIntervalNanoseconds
        ))
        XCTAssertEqual(projector.completedBytes, 250)
        XCTAssertEqual(projector.currentStepID, step)
    }

    func testThreeResourcesKeepPackageCompletedMonotonic() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 300)
        let a = try AhaKeyRuntimeStepIdentifier("resource:a")
        let b = try AhaKeyRuntimeStepIdentifier("resource:b")
        let c = try AhaKeyRuntimeStepIdentifier("resource:c")
        XCTAssertTrue(projector.confirmChunk(stepID: a, bytes: 100, nowNanos: start))
        XCTAssertTrue(projector.confirmChunk(stepID: b, bytes: 100, nowNanos: start + 300_000_000))
        XCTAssertTrue(projector.confirmChunk(stepID: c, bytes: 100, nowNanos: start + 600_000_000))
        XCTAssertEqual(projector.completedBytes, 300)
        XCTAssertEqual(projector.currentStepID, c)
    }

    func testFailureDoesNotAdvancePastLastConfirmedChunk() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 500)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 120, nowNanos: start))
        XCTAssertFalse(projector.publishTerminal(nowNanos: start + 1_000_000_000))
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
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 0, nowNanos: start))
        XCTAssertFalse(projector.confirmChunk(stepID: step, bytes: 0, nowNanos: start + 1_000_000_000))
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

    func testEnterStepSwitchesCurrentStepWithoutAdvancingBytes() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 200)
        let a = try AhaKeyRuntimeStepIdentifier("resource:a")
        let b = try AhaKeyRuntimeStepIdentifier("resource:b")
        XCTAssertTrue(projector.confirmChunk(stepID: a, bytes: 100, nowNanos: start))
        XCTAssertEqual(projector.completedBytes, 100)
        XCTAssertFalse(projector.enterStep(stepID: b, nowNanos: start + 10_000_000), "切换 event 服从 ≤4Hz")
        XCTAssertEqual(projector.completedBytes, 100)
        XCTAssertEqual(projector.currentStepID, b)
        XCTAssertTrue(projector.enterStep(stepID: b, nowNanos: start + 300_000_000) == false)
    }

    func testClockRollbackDoesNotSuppressSubsequentPublish() throws {
        var projector = AhaKeyByteProgressProjector(totalBytes: 400)
        let step = try AhaKeyRuntimeStepIdentifier("resource:a")
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 50, nowNanos: 10_000_000_000))
        // 墙钟回拨：单调 tick 若被错误传入更小值，不得把后续真实变化长期压制。
        XCTAssertTrue(projector.confirmChunk(stepID: step, bytes: 50, nowNanos: 1_000_000_000))
        XCTAssertEqual(projector.completedBytes, 100)
    }
}
