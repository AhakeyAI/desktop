import XCTest
@testable import AhaKeyConfigAgent

final class ClaudeHookHandlerTests: XCTestCase {
    private let verifiedAuto: [String: Any] = [
        "approvalPolicyVersion": 1,
        "physicalSwitchState": 0,
        "switchState": 0,
        "approvalAutoVerified": true,
    ]

    func testBothHooksAllowFreshVerifiedPhysicalAuto() throws {
        let output = try XCTUnwrap(ClaudeHookHandler.preToolUseOutput(reply: verifiedAuto))
        let hook = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(hook["permissionDecision"] as? String, "allow")
        XCTAssertEqual(permissionBehavior(verifiedAuto), "allow")
    }

    func testBothHooksDeferForLegacyCacheOrMissingReply() {
        assertDefers(nil)
        assertDefers(["switchState": 0, "lightMode": 16])
        assertDefers(["switchState": 1])
    }

    func testBothHooksDeferForMissingOrFailedVerification() {
        for field in verifiedAuto.keys {
            var incomplete = verifiedAuto
            incomplete.removeValue(forKey: field)
            assertDefers(incomplete)
        }
        for (field, value) in [
            ("approvalPolicyVersion", 2 as Any),
            ("physicalSwitchState", 1 as Any),
            ("switchState", 1 as Any),
            ("approvalAutoVerified", false as Any),
        ] {
            var invalid = verifiedAuto
            invalid[field] = value
            assertDefers(invalid)
        }
    }

    private func permissionBehavior(_ reply: [String: Any]?) -> String? {
        let output = ClaudeHookHandler.permissionRequestOutput(reply: reply)
        let hook = output["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(hook?["hookEventName"] as? String, "PermissionRequest")
        return (hook?["decision"] as? [String: Any])?["behavior"] as? String
    }

    private func assertDefers(_ reply: [String: Any]?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply), file: file, line: line)
        XCTAssertEqual(permissionBehavior(reply), "ask", file: file, line: line)
    }
}
