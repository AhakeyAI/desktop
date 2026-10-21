import XCTest
@testable import AhaKeyConfigShared

final class WS3DisplaySettingFeedbackTests: XCTestCase {
    func testHandoffBeforeStartSendsNothingAndAddsNoUncertainty() {
        var feedback = WS3DisplaySettingFeedback()
        let old = feedback.begin(generation: 1, save: .brightness(50))
        XCTAssertFalse(feedback.start(old, currentGeneration: 2))
        XCTAssertTrue(feedback.unconfirmed.isEmpty)
        XCTAssertFalse(feedback.succeed(old, currentGeneration: 2))
    }

    func testLateOldSuccessCannotClearInterruptedSaveOrFinishNewAttempt() {
        var feedback = WS3DisplaySettingFeedback()
        let old = feedback.begin(generation: 1, save: .brightness(50))
        XCTAssertTrue(feedback.start(old, currentGeneration: 1))
        let fresh = feedback.begin(generation: 2, save: .singleLight(mode: 3, state: 0, effect: 0))
        XCTAssertEqual(feedback.unconfirmed[.brightness], .brightness(50))
        XCTAssertTrue(feedback.start(fresh, currentGeneration: 2))
        XCTAssertFalse(feedback.succeed(old, currentGeneration: 2))
        XCTAssertFalse(feedback.fail(old, currentGeneration: 2, mayHaveApplied: true))
        // A delayed view onChange must not cancel the fresh task.
        XCTAssertFalse(feedback.connectionChanged(to: 2))
        XCTAssertTrue(feedback.succeed(fresh, currentGeneration: 2))
        XCTAssertEqual(feedback.unconfirmed[.brightness], .brightness(50))
    }

    func testReadAndOtherTargetSaveCannotEraseUnconfirmedTarget() {
        var feedback = WS3DisplaySettingFeedback()
        let target = WS3DisplaySetting.singleLight(mode: 0, state: 8, effect: 0)
        let save = feedback.begin(generation: 1, save: target)
        XCTAssertTrue(feedback.start(save, currentGeneration: 1))
        XCTAssertTrue(feedback.fail(save, currentGeneration: 1, mayHaveApplied: true))
        let read = feedback.begin(generation: 1)
        XCTAssertTrue(feedback.start(read, currentGeneration: 1))
        XCTAssertTrue(feedback.succeed(read, currentGeneration: 1))
        let other = feedback.begin(generation: 1, save: .singleLight(mode: 1, state: 8, effect: 0))
        XCTAssertTrue(feedback.start(other, currentGeneration: 1))
        XCTAssertTrue(feedback.succeed(other, currentGeneration: 1))
        XCTAssertEqual(feedback.unconfirmed[target.feedbackKey], target)
        let retry = feedback.begin(generation: 1, save: target)
        XCTAssertTrue(feedback.start(retry, currentGeneration: 1))
        XCTAssertTrue(feedback.succeed(retry, currentGeneration: 1))
        XCTAssertTrue(feedback.unconfirmed.isEmpty)
    }

    func testLocalPrewriteFailureAddsNoNewUncertaintyAndDoesNotErasePriorFailure() {
        var feedback = WS3DisplaySettingFeedback()
        for mayHaveApplied in [false, true, false] {
            let save = feedback.begin(generation: 1, save: .brightness(50))
            XCTAssertTrue(feedback.start(save, currentGeneration: 1))
            XCTAssertTrue(feedback.fail(save, currentGeneration: 1, mayHaveApplied: mayHaveApplied))
            if mayHaveApplied { XCTAssertEqual(feedback.unconfirmed[.brightness], .brightness(50)) }
        }
        XCTAssertEqual(feedback.unconfirmed[.brightness], .brightness(50))
    }

    func testLeavingViewRevokesStartedSaveAndRejectsLateCallbacks() {
        var feedback = WS3DisplaySettingFeedback()
        let save = feedback.begin(generation: 1, save: .brightness(50))
        XCTAssertTrue(feedback.start(save, currentGeneration: 1))
        feedback.invalidate()
        XCTAssertFalse(feedback.succeed(save, currentGeneration: 1))
        XCTAssertFalse(feedback.fail(save, currentGeneration: 1, mayHaveApplied: false))
        XCTAssertEqual(feedback.unconfirmed[.brightness], .brightness(50))
    }

    func testQueuedAttemptCannotStartAfterBeingSuperseded() {
        var feedback = WS3DisplaySettingFeedback()
        let old = feedback.begin(generation: 1, save: .brightness(50))
        let fresh = feedback.begin(generation: 1)
        XCTAssertFalse(feedback.start(old, currentGeneration: 1))
        XCTAssertTrue(feedback.start(fresh, currentGeneration: 1))
        XCTAssertTrue(feedback.succeed(fresh, currentGeneration: 1))
        XCTAssertTrue(feedback.unconfirmed.isEmpty)
    }
}
