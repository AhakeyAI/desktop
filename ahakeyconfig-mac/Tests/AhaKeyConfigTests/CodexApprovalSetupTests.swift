import XCTest
@testable import AhaKeyConfig

@MainActor
final class CodexApprovalSetupTests: XCTestCase {
    func testOfferAndDeclineNeverWritePolicyAndDoNotRepeatOnEveryAutoTransition() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        var writes = 0
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { writes += 1; return true })
        XCTAssertTrue(model.offer())
        XCTAssertFalse(model.offer())
        XCTAssertEqual(writes, 0)
        _ = model.resolve(useRequestedApproval: false)
        XCTAssertEqual(choice, .keepCurrent)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(model.offer())
        XCTAssertTrue(model.offer(force: true), "User can reopen setup after declining")
        _ = model.resolve(useRequestedApproval: false)
        XCTAssertEqual(writes, 0)
    }

    func testOnlyAnExplicitAcceptWritesAndDoubleSubmissionCannotWriteAgain() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        var writes = 0
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { writes += 1; return true })
        _ = model.resolve(useRequestedApproval: true)
        XCTAssertEqual(writes, 0, "No active offer means no consent")
        XCTAssertTrue(model.offer())
        _ = model.resolve(useRequestedApproval: true)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(choice, .requestedApproval)
        _ = model.resolve(useRequestedApproval: true)
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(model.offer())
    }

    func testFailedWriteDoesNotRecordSuccessAndCanBeRetried() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { false })
        XCTAssertTrue(model.offer())
        guard case .failed = model.resolve(useRequestedApproval: true) else { return XCTFail("Failed writer reported success") }
        XCTAssertEqual(choice, .undecided)
        XCTAssertTrue(model.offer())
    }
}
