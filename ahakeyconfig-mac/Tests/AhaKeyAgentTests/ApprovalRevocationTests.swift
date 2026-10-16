import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

final class ApprovalRevocationTests: XCTestCase {
    func testPausedClientCannotUseOtherwiseValidAutoProof() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reply: [String: Any] = ["switchState": 0, "physicalSwitchState": 0, "approvalAutoVerified": true, "approvalPolicyVersion": 1]
        XCTAssertEqual(HookSupport.approvalSwitchState(reply, client: .cursor, controlDirectory: directory), 0)
        XCTAssertTrue(ApprovalAutomationControl.revoke(.cursor, directory: directory,
            codexURL: directory.appendingPathComponent("missing-codex"), kimiURL: directory.appendingPathComponent("missing-kimi"), cursorDirectory: directory.appendingPathComponent("cursor")))
        XCTAssertEqual(HookSupport.approvalSwitchState(reply, client: .cursor, controlDirectory: directory), 1)
        XCTAssertEqual(HookSupport.approvalSwitchState(reply, client: .claude, controlDirectory: directory), 0)
    }
}
