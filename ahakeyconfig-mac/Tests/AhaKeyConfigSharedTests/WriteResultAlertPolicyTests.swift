import XCTest
@testable import AhaKeyConfigShared

final class WriteResultAlertPolicyTests: XCTestCase {
    func testCompleteEditingExitsAfterPartialWriteResult() {
        XCTAssertTrue(
            WriteResultAlertPolicy.shouldExitEditing(for: .completeEditing)
        )
    }

    func testCompleteEditingExitsAfterFailedWriteResult() {
        XCTAssertTrue(
            WriteResultAlertPolicy.shouldExitEditing(for: .completeEditing)
        )
    }

    func testContinueEditingKeepsInspectorOpen() {
        XCTAssertFalse(
            WriteResultAlertPolicy.shouldExitEditing(for: .continueEditing)
        )
    }
}
