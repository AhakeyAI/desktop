import XCTest
@testable import AhaKeyConfigShared

final class WS3UploadFeedbackTests: XCTestCase {
    func testInterruptedUploadNoticeSurvivesReconnectAndLateCompletion() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
        XCTAssertEqual(feedback.entryID, 18)
        XCTAssertFalse(feedback.confirm(old))
        XCTAssertFalse(feedback.fail(old))
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
    }

    func testErrorThenReconnectPreservesNoticeWhileSuccessIsRevoked() {
        var failed = WS3UploadFeedback()
        let a = failed.begin(entry: 18, generation: 7)
        XCTAssertTrue(failed.fail(a))
        failed.connectionChanged(to: 8)
        XCTAssertEqual(failed.phase, .unconfirmed)
        var success = WS3UploadFeedback()
        let b = success.begin(entry: 18, generation: 7)
        XCTAssertTrue(success.confirm(b))
        success.connectionChanged(to: 8)
        XCTAssertEqual(success.phase, .idle)
    }

    func testOldAttemptCannotChangeNewAttemptOrItsConfirmedResult() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        feedback.connectionChanged(to: 8)
        let new = feedback.begin(entry: 17, generation: 8)
        XCTAssertFalse(feedback.confirm(old))
        XCTAssertFalse(feedback.fail(old))
        XCTAssertEqual(feedback.phase, .sending)
        XCTAssertEqual(feedback.entryID, 17)
        XCTAssertTrue(feedback.confirm(new))
        XCTAssertFalse(feedback.fail(old))
        XCTAssertEqual(feedback.phase, .confirmed)
    }

    func testOnlyConfirmedRestoreOfAffectedEntryClearsNotice() {
        var feedback = WS3UploadFeedback()
        let ticket = feedback.begin(entry: 18, generation: 7)
        feedback.fail(ticket)
        feedback.restoredDefault(entry: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
        feedback.restoredDefault(entry: 18)
        XCTAssertEqual(feedback.phase, .idle)
        XCTAssertNil(feedback.entryID)
    }
    func testAnotherSlotSuccessDoesNotEraseUnresolvedUploadNotice() {
        var feedback = WS3UploadFeedback()
        let first = feedback.begin(entry: 18, generation: 7)
        feedback.fail(first)
        let second = feedback.begin(entry: 17, generation: 7)
        feedback.confirm(second)
        XCTAssertEqual(feedback.unconfirmedEntries, [18])
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.unconfirmedEntries, [18])
        feedback.restoredDefault(entry: 8)
        XCTAssertEqual(feedback.unconfirmedEntries, [18])
        feedback.restoredDefault(entry: 18)
        XCTAssertTrue(feedback.unconfirmedEntries.isEmpty)
    }

    func testSuccessfulRetryClearsOnlyItsOwnNotice() {
        var feedback = WS3UploadFeedback()
        let first = feedback.begin(entry: 18, generation: 7)
        feedback.fail(first)
        let second = feedback.begin(entry: 17, generation: 7)
        feedback.fail(second)
        let retry = feedback.begin(entry: 18, generation: 7)
        XCTAssertTrue(feedback.confirm(retry))
        XCTAssertEqual(feedback.unconfirmedEntries, [17])
    }

    func testDelayedUIConnectionCallbackCannotInvalidateNewGenerationAttempt() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        let current = feedback.begin(entry: 17, generation: 8)
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .sending)
        XCTAssertFalse(feedback.confirm(old))
        XCTAssertTrue(feedback.confirm(current))
        XCTAssertEqual(feedback.unconfirmedEntries, [18])
    }

}
