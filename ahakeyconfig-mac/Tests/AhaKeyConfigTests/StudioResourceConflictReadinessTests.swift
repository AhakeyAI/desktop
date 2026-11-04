import XCTest
@testable import AhaKeyConfig

final class StudioResourceConflictReadinessTests: XCTestCase {
    func testConflictWaitsForEnclosingSubmissionToReenableEditor() {
        XCTAssertFalse(StudioResourceConflictReadiness.mayPresent(hasConflict: true, editorEnabled: false, operationBusy: false))
        XCTAssertFalse(StudioResourceConflictReadiness.mayPresent(hasConflict: true, editorEnabled: true, operationBusy: true))
        XCTAssertTrue(StudioResourceConflictReadiness.mayPresent(hasConflict: true, editorEnabled: true, operationBusy: false))
        XCTAssertFalse(StudioResourceConflictReadiness.mayPresent(hasConflict: false, editorEnabled: true, operationBusy: false))
    }
}
