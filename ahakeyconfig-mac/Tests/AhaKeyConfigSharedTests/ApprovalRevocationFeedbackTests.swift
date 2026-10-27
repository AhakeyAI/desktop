import Foundation
import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class ApprovalRevocationFeedbackTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let state: CodexDesktopLeverState
        let lease: CodexDesktopLeverState.Lease
        var config: URL { root.appendingPathComponent("isolated-codex.toml") }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            state = CodexDesktopLeverState(directory: root)
            try state.setManagementEnabled(true)
            let owner = CodexDesktopSessionBridge.Owner(threadID: UUID().uuidString, clientID: UUID().uuidString)
            let baseline = try CodexDesktopSessionBridge.Settings(encoded: JSONSerialization.data(withJSONObject:
                ["approvalPolicy": "on-request", "permissions": ":workspace"]))
            let desired = try CodexDesktopSessionBridge.Settings(encoded: JSONSerialization.data(withJSONObject:
                ["approvalPolicy": "never", "permissions": ":danger-full-access"]))
            lease = try state.prepare(owner: owner, baseline: baseline, intended: desired)
        }
        func begin() -> ApprovalAutomationControl.RevocationOutcome {
            ApprovalAutomationControl.beginRevocation(.codex, directory: root, codexURL: config)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    func testPendingNativeCleanupIsRecoveringRatherThanFailed() throws {
        let f = try Fixture(); defer { f.remove() }
        XCTAssertEqual(f.begin(), .recovering)
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.root))
        XCTAssertFalse(ApprovalAutomationControl.revoke(.codex, directory: f.root, codexURL: f.config),
                       "The legacy Boolean must still not claim completed recovery")
    }

    func testRecoveryThatFinishesAfterPauseDoesNotProduceFailureFeedback() async throws {
        let f = try Fixture(); defer { f.remove() }
        var pauses = 0
        let result = await ApprovalRevocationFeedback.wait(f.begin(), directory: f.root,
            isCurrent: { true }, pause: {
                pauses += 1
                XCTAssertTrue(try f.state.removeAfterVerifiedRestore(f.lease))
            })
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(pauses, 1)
        XCTAssertTrue(try f.state.snapshot().leases.isEmpty)
        XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: f.root))
    }

    func testGenuineConfigFailureCannotBeHiddenByPendingNativeRecovery() async throws {
        let f = try Fixture(); defer { f.remove() }
        try FileManager.default.createDirectory(at: f.config, withIntermediateDirectories: false)
        try Data([1]).write(to: f.config.appendingPathExtension("ahakey-auto-lease"))
        let initial = f.begin()
        XCTAssertEqual(initial, .failed)
        let result = await ApprovalRevocationFeedback.wait(initial, directory: f.root,
            isCurrent: { true }, pause: { XCTFail("A real cleanup error must not be deferred"); throw CancellationError() })
        XCTAssertEqual(result, .notConfirmed)
    }

    func testUnfinishedRecoveryTimesOutAndKeepsItsJournal() async throws {
        let f = try Fixture(); defer { f.remove() }
        let result = await ApprovalRevocationFeedback.wait(f.begin(), directory: f.root, timeout: .zero,
            isCurrent: { true }, pause: { XCTFail("Zero timeout must not wait"); throw CancellationError() })
        XCTAssertEqual(result, .notConfirmed)
        XCTAssertEqual(try f.state.snapshot().leases.count, 1)
    }

    func testSupersededHandoffCannotShowAnOldWarning() async throws {
        let f = try Fixture(); defer { f.remove() }
        let result = await ApprovalRevocationFeedback.wait(f.begin(), directory: f.root,
            isCurrent: { false }, pause: { XCTFail("A newer owner must not wait on the old operation"); throw CancellationError() })
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(try f.state.snapshot().leases.count, 1)
    }

    func testCancellationOfWaitDoesNotBecomeARevocationFailure() async throws {
        let f = try Fixture(); defer { f.remove() }
        let result = await ApprovalRevocationFeedback.wait(f.begin(), directory: f.root,
            isCurrent: { true }, pause: { throw CancellationError() })
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(try f.state.snapshot().leases.count, 1)
    }
    func testOwnerChangedDuringWaitSuppressesStaleFeedback() async throws {
        let f = try Fixture(); defer { f.remove() }
        var current = true
        var pauses = 0
        let result = await ApprovalRevocationFeedback.wait(f.begin(), directory: f.root,
            isCurrent: { current }, pause: { current = false; pauses += 1 })
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(pauses, 1)
        XCTAssertEqual(try f.state.snapshot().leases.count, 1)
    }

    func testGlobalRecoveryWaitsForBothNativeClients() async throws {
        let f = try Fixture(); defer { f.remove() }
        let kimi = KimiDesktopLeverState(directory: f.root)
        let target = try KimiDesktopLeverState.Target(home: "/tmp/kimi-fixture", sessionID: "session")
        try kimi.authorize(target, title: "Fixture")
        let lease = try kimi.prepare(target, baseline: .yolo, intended: .auto)
        var pauses = 0
        let initial = ApprovalAutomationControl.beginRevocation(directory: f.root, codexURL: f.config,
            kimiURL: f.root.appendingPathComponent("kimi.toml"), cursorDirectory: f.root.appendingPathComponent("cursor"))
        XCTAssertEqual(initial, .recovering)
        let result = await ApprovalRevocationFeedback.wait(initial, directory: f.root, isCurrent: { true }, pause: {
            pauses += 1
            if pauses == 1 { XCTAssertTrue(try f.state.removeAfterVerifiedRestore(f.lease)) }
            else { XCTAssertTrue(try kimi.removeAfterVerifiedRestore(lease)) }
        })
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(pauses, 2)
    }
    func testClientSpecificKimiRecoveryDoesNotWaitOnActiveCodexLeases() async throws {
        let f = try Fixture(); defer { f.remove() }
        let kimi = KimiDesktopLeverState(directory: f.root)
        let target = try KimiDesktopLeverState.Target(home: "/tmp/kimi-fixture", sessionID: "session")
        try kimi.authorize(target, title: "Fixture")
        let lease = try kimi.prepare(target, baseline: .yolo, intended: .auto)
        let initial = ApprovalAutomationControl.beginRevocation(.kimi, directory: f.root,
            kimiURL: f.root.appendingPathComponent("kimi.toml"))
        XCTAssertEqual(initial, .recovering)
        let result = await ApprovalRevocationFeedback.wait(initial, directory: f.root, client: .kimi,
            isCurrent: { true }, pause: { XCTAssertTrue(try kimi.removeAfterVerifiedRestore(lease)) })
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(try f.state.snapshot().leases.count, 1)
    }

}
