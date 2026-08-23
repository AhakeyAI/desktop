import XCTest
@testable import AhaKeyConfigShared

final class CursorHookDecisionReducerTests: XCTestCase {
    func testAutomaticDecisionExplicitlyAllowsTheTool() {
        let result = CursorHookDecisionReducer.reduce(.automatic)

        XCTAssertEqual(result.decision, .allow)
        XCTAssertEqual(result.standardOutput, #"{"permission":"allow"}"#)
    }

    func testManualDecisionDefersWithEmptyStandardOutput() {
        let result = CursorHookDecisionReducer.reduce(.manual)

        XCTAssertEqual(result.decision, .deferToNative)
        XCTAssertNil(result.standardOutput)
    }

    func testRuntimeUnavailableFailsOpenWithEmptyStandardOutput() {
        let result = CursorHookDecisionReducer.reduce(.unavailable)

        XCTAssertEqual(result.decision, .unavailable)
        XCTAssertNil(result.standardOutput)
    }

    func testMissingRuntimeReplyIsUnavailableAndNeverDenies() {
        let result = CursorHookDecisionReducer.reduce(nil)

        XCTAssertEqual(result.decision, .unavailable)
        XCTAssertNil(result.standardOutput)
    }
}
