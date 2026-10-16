import XCTest
@testable import AhaKeyConfigAgent

final class ClaudeHookHandlerTests: XCTestCase {
    func testFreshPhysicalLeverControlsBothHooks() {
        for switchState in 0...1 {
            let status = AgentDeviceStatus(
                battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
                workMode: 0, lightMode: 16, switchState: switchState
            )
            let reply = AhaKeyAgent.permissionReply(status)
            let output = ClaudeHookHandler.preToolUseOutput(reply: reply)
            let hook = output?["hookSpecificOutput"] as? [String: Any]
            XCTAssertEqual(hook?["permissionDecision"] as? String, switchState == 0 ? "allow" : nil)
            XCTAssertEqual(permissionBehavior(reply), switchState == 0 ? "allow" : "ask")
        }
    }

    func testUnverifiedOrUnknownStateDefersBothHooks() {
        let failedVerification: [String: Any] = [
            "approvalPolicyVersion": 1, "physicalSwitchState": 0,
            "switchState": 0, "approvalAutoVerified": false,
        ]
        for reply: [String: Any]? in [nil, ["switchState": 0], ["switchState": 1], failedVerification] {
            XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply))
            XCTAssertEqual(permissionBehavior(reply), "ask")
        }
    }

    private func permissionBehavior(_ reply: [String: Any]?) -> String? {
        let output = ClaudeHookHandler.permissionRequestOutput(reply: reply)
        let hook = output["hookSpecificOutput"] as? [String: Any]
        return (hook?["decision"] as? [String: Any])?["behavior"] as? String
    }
}
