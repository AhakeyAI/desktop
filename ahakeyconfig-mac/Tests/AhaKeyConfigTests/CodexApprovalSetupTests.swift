import XCTest
@testable import AhaKeyConfig

@MainActor
final class CodexApprovalSetupTests: XCTestCase {
    func testDefaultConfigConsentCannotBecomeFullAccessManagementConsent() {
        let suite = "CodexDesktopConsentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("requestedApproval", forKey: "codexApprovalSetupChoice")
        defaults.set("managedSessions", forKey: "codexDesktopLeverChoiceV1")
        XCTAssertEqual(CodexApprovalSetupModel.persistedChoice(defaults: defaults, managementEnabled: false), .undecided,
            "The new state file is the authority, not an old or stale preference")
        XCTAssertEqual(CodexApprovalSetupModel.persistedChoice(defaults: defaults, managementEnabled: true), .managedSessions)
    }

    func testFailedRevocationDoesNotClaimThatSessionManagementStopped() {
        var choice = CodexApprovalSetupModel.Choice.managedSessions
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { true }, revoke: { false })
        XCTAssertTrue(model.offer(force: true))
        guard case .failed = model.resolve(manageSessions: false) else { return XCTFail("Failed revocation was presented as success") }
        XCTAssertEqual(choice, .managedSessions)
    }
    func testOfferAndDeclineNeverWritePolicyAndDoNotRepeatOnEveryAutoTransition() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        var writes = 0
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { writes += 1; return true })
        XCTAssertTrue(model.offer())
        XCTAssertFalse(model.offer())
        XCTAssertEqual(writes, 0)
        _ = model.resolve(manageSessions: false)
        XCTAssertEqual(choice, .keepCurrent)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(model.offer())
        XCTAssertTrue(model.offer(force: true), "User can reopen setup after declining")
        _ = model.resolve(manageSessions: false)
        XCTAssertEqual(writes, 0)
    }

    func testOnlyAnExplicitAcceptWritesAndDoubleSubmissionCannotWriteAgain() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        var writes = 0
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { writes += 1; return true })
        _ = model.resolve(manageSessions: true)
        XCTAssertEqual(writes, 0, "No active offer means no consent")
        XCTAssertTrue(model.offer())
        _ = model.resolve(manageSessions: true)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(choice, .managedSessions)
        _ = model.resolve(manageSessions: true)
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(model.offer())
    }

    func testFailedWriteDoesNotRecordSuccessAndCanBeRetried() {
        var choice = CodexApprovalSetupModel.Choice.undecided
        let model = CodexApprovalSetupModel(readChoice: { choice }, saveChoice: { choice = $0 }, configure: { false })
        XCTAssertTrue(model.offer())
        guard case .failed = model.resolve(manageSessions: true) else { return XCTFail("Failed writer reported success") }
        XCTAssertEqual(choice, .undecided)
        XCTAssertTrue(model.offer())
    }
}
