import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexDesktopLeverStateTests: XCTestCase {
    private func withState(_ body: (CodexDesktopLeverState, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(CodexDesktopLeverState(directory: root), root)
    }
    private func settings(_ policy: String, _ profile: String) throws -> CodexDesktopSessionBridge.Settings {
        try .init(encoded: JSONSerialization.data(withJSONObject: ["approvalPolicy": policy, "permissions": profile]))
    }
    private var owner: CodexDesktopSessionBridge.Owner {
        .init(threadID: "01a11a8c-27dc-7670-9389-e912f24b2d65", clientID: "71efe1c2-e444-41ea-934d-9185e2c310aa")
    }

    func testFreshInstallHasNoSessionConsentAndCannotPrepareAnAutomaticGrant() throws {
        try withState { state, _ in
            XCTAssertFalse(try state.snapshot().managementEnabled)
            XCTAssertThrowsError(try state.prepare(owner: owner,
                baseline: settings("on-request", ":workspace"), intended: settings("never", ":danger-full-access")))
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testPendingGrantAndBaselineSurviveRestartAndConsentRevocation() throws {
        try withState { state, root in
            try state.setManagementEnabled(true)
            let baseline = try settings("on-request", ":workspace")
            let lease = try state.prepare(owner: owner, baseline: baseline, intended: settings("never", ":danger-full-access"))
            let restarted = CodexDesktopLeverState(directory: root)
            XCTAssertEqual(try restarted.snapshot().leases, [lease])
            XCTAssertFalse(try restarted.snapshot().leases[0].acknowledged)
            try restarted.setManagementEnabled(false)
            XCTAssertEqual(try restarted.snapshot().leases[0].baseline, baseline)
            XCTAssertTrue(try restarted.acknowledge(lease), "A late native acknowledgement must remain recoverable")
            XCTAssertTrue(try restarted.removeAfterVerifiedRestore(lease))
            XCTAssertTrue(try restarted.snapshot().leases.isEmpty)
        }
    }

    func testRapidSwitchRetainsOriginalBaselineAndStaleCompletionCannotClearNewLease() throws {
        try withState { state, _ in
            try state.setManagementEnabled(true)
            let baseline = try settings("on-request", ":workspace")
            let auto = try state.prepare(owner: owner, baseline: baseline, intended: settings("never", ":danger-full-access"))
            let manual = try state.prepare(owner: owner, baseline: auto.intended, intended: baseline)
            XCTAssertEqual(manual.baseline, baseline)
            XCTAssertTrue(manual.possibleOwnedSettings.contains(auto.intended), "A lost manual reply cannot make an earlier auto grant look like a user edit")
            XCTAssertFalse(try state.removeAfterExternalChange(manual, observed: auto.intended))
            XCTAssertFalse(try state.acknowledge(auto))
            XCTAssertFalse(try state.removeAfterVerifiedRestore(auto))
            XCTAssertEqual(try state.snapshot().leases, [manual])
        }
    }

    func testAnotherDesktopOwnerCannotReplaceTheOriginalRecoveryRecord() throws {
        try withState { state, _ in
            try state.setManagementEnabled(true)
            let baseline = try settings("on-request", ":workspace")
            let pending = try state.prepare(owner: owner, baseline: baseline, intended: settings("never", ":danger-full-access"))
            XCTAssertThrowsError(try state.prepare(owner: .init(threadID: owner.threadID, clientID: UUID().uuidString), baseline: baseline, intended: baseline))
            XCTAssertEqual(try state.snapshot().leases, [pending])
        }
    }

    func testCorruptOrSymlinkedStateIsNotReplacedWithAnEmptySuccess() throws {
        try withState { state, root in
            _ = try state.snapshot()
            let file = root.appendingPathComponent("codex-desktop-lever-v1.json")
            let bytes = Data("corrupt existing recovery journal".utf8)
            try bytes.write(to: file); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            XCTAssertThrowsError(try state.setManagementEnabled(true))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            try FileManager.default.removeItem(at: file)
            let target = root.appendingPathComponent("unrelated")
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertThrowsError(try state.setManagementEnabled(true))
            XCTAssertEqual(try Data(contentsOf: target), bytes)
        }
    }

    func testLegacyJournalStillRecoversItsLastSubmittedPermissionValue() throws {
        try withState { state, root in
            try state.setManagementEnabled(true)
            let lease = try state.prepare(owner: owner, baseline: settings("on-request", ":workspace"), intended: settings("never", ":danger-full-access"))
            let file = root.appendingPathComponent("codex-desktop-lever-v1.json")
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var leases = try XCTUnwrap(document["leases"] as? [[String: Any]])
            leases[0].removeValue(forKey: "possibleOwnedSettings"); document["leases"] = leases
            try JSONSerialization.data(withJSONObject: document).write(to: file)
            XCTAssertEqual(try state.snapshot().leases[0].possibleOwnedSettings, [lease.intended])
        }
    }

    func testRevokeCannotClaimSuccessBeforeNativeRecoveryCompletes() throws {
        try withState { state, root in
            try state.setManagementEnabled(true)
            let lease = try state.prepare(owner: owner, baseline: settings("on-request", ":workspace"), intended: settings("never", ":danger-full-access"))
            let config = root.appendingPathComponent("isolated-codex.toml")
            XCTAssertFalse(ApprovalAutomationControl.revoke(.codex, directory: root, codexURL: config))
            XCTAssertFalse(ApprovalAutomationControl.isEnabled(.codex, directory: root))
            _ = try state.removeAfterVerifiedRestore(lease)
            XCTAssertTrue(ApprovalAutomationControl.revoke(.codex, directory: root, codexURL: config))
        }
    }
}
