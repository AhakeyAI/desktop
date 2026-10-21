import XCTest
@testable import AhaKeyConfigShared

final class WS3UploadFeedbackTests: XCTestCase {
    func testInterruptedUploadNoticeSurvivesReconnectAndLateCompletion() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
        XCTAssertEqual(feedback.entryID, 18)
        XCTAssertFalse(feedback.confirm(old, currentGeneration: 8))
        XCTAssertFalse(feedback.fail(old, currentGeneration: 8))
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
    }

    func testErrorThenReconnectPreservesNoticeWhileSuccessIsRevoked() {
        var failed = WS3UploadFeedback()
        let a = failed.begin(entry: 18, generation: 7)
        XCTAssertTrue(failed.fail(a, currentGeneration: 7))
        failed.connectionChanged(to: 8)
        XCTAssertEqual(failed.phase, .unconfirmed)
        var success = WS3UploadFeedback()
        let b = success.begin(entry: 18, generation: 7)
        XCTAssertTrue(success.confirm(b, currentGeneration: 7))
        success.connectionChanged(to: 8)
        XCTAssertEqual(success.phase, .idle)
    }

    func testOldAttemptCannotChangeNewAttemptOrItsConfirmedResult() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        feedback.connectionChanged(to: 8)
        let new = feedback.begin(entry: 17, generation: 8)
        XCTAssertFalse(feedback.confirm(old, currentGeneration: 8))
        XCTAssertFalse(feedback.fail(old, currentGeneration: 8))
        XCTAssertEqual(feedback.phase, .sending)
        XCTAssertEqual(feedback.entryID, 17)
        XCTAssertTrue(feedback.confirm(new, currentGeneration: 8))
        XCTAssertFalse(feedback.fail(old, currentGeneration: 8))
        XCTAssertEqual(feedback.phase, .confirmed)
    }

    func testOnlyConfirmedRestoreOfAffectedEntryClearsNotice() {
        var feedback = WS3UploadFeedback()
        let ticket = feedback.begin(entry: 18, generation: 7)
        feedback.fail(ticket, currentGeneration: 7)
        feedback.restoredDefault(entry: 8)
        XCTAssertEqual(feedback.phase, .unconfirmed)
        feedback.restoredDefault(entry: 18)
        XCTAssertEqual(feedback.phase, .idle)
        XCTAssertNil(feedback.entryID)
    }
    func testAnotherSlotSuccessDoesNotEraseUnresolvedUploadNotice() {
        var feedback = WS3UploadFeedback()
        let first = feedback.begin(entry: 18, generation: 7)
        feedback.fail(first, currentGeneration: 7)
        let second = feedback.begin(entry: 17, generation: 7)
        feedback.confirm(second, currentGeneration: 7)
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
        feedback.fail(first, currentGeneration: 7)
        let second = feedback.begin(entry: 17, generation: 7)
        feedback.fail(second, currentGeneration: 7)
        let retry = feedback.begin(entry: 18, generation: 7)
        XCTAssertTrue(feedback.confirm(retry, currentGeneration: 7))
        XCTAssertEqual(feedback.unconfirmedEntries, [17])
    }

    func testDelayedUIConnectionCallbackCannotInvalidateNewGenerationAttempt() {
        var feedback = WS3UploadFeedback()
        let old = feedback.begin(entry: 18, generation: 7)
        let current = feedback.begin(entry: 17, generation: 8)
        feedback.connectionChanged(to: 8)
        XCTAssertEqual(feedback.phase, .sending)
        XCTAssertFalse(feedback.confirm(old, currentGeneration: 8))
        XCTAssertTrue(feedback.confirm(current, currentGeneration: 8))
        XCTAssertEqual(feedback.unconfirmedEntries, [18])
    }

    func testCompletionBeforeUIConnectionCallbackStillPreservesUnconfirmedEntry() {
        for failure in [false, true] {
            var feedback = WS3UploadFeedback()
            let old = feedback.begin(entry: 18, generation: 7)
            // The Manager has changed generation; SwiftUI onChange has not run.
            let accepted = failure ? feedback.fail(old, currentGeneration: 8) :
                feedback.confirm(old, currentGeneration: 8)
            XCTAssertFalse(accepted)
            XCTAssertEqual(feedback.phase, .unconfirmed)
            XCTAssertEqual(feedback.unconfirmedEntries, [18])
            feedback.connectionChanged(to: 8)
            XCTAssertEqual(feedback.unconfirmedEntries, [18])
        }
    }

}
