import XCTest
@testable import AhaKeyConfigAgent

final class ClaudeHookHandlerTests: XCTestCase {
    func testPreToolUseAllowsOnlyWhenPhysicalLeverIsAuto() {
        let output = ClaudeHookHandler.preToolUseOutput(reply: ["switchState": 0])
        let hook = output?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(hook?["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(hook?["permissionDecision"] as? String, "allow")

        let verified: [String: Any] = [
            "approvalPolicyVersion": 1,
            "physicalSwitchState": 0,
            "switchState": 0,
            "approvalAutoVerified": true,
        ]
        XCTAssertNotNil(ClaudeHookHandler.preToolUseOutput(reply: verified))
        var unverified = verified
        unverified["approvalAutoVerified"] = false
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: unverified))
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: ["switchState": 1]))
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: nil))
    }
}
