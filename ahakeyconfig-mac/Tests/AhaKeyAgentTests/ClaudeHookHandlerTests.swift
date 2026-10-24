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

    /// AHK-053：布尔、小数、字符串、越界值都不能被当成拨杆 0 而自动批准。
    func testMalformedSwitchStateTypesDeferBothHooks() throws {
        let malformed = [#"false"#, #"0.5"#, #"-0.9"#, #""0""#, #"0.0"#, #"2"#, #"-1"#]
        for value in malformed {
            for field in ["switchState", "physicalSwitchState"] {
                let reply = try decode(
                    #"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#,
                    replacing: field, with: value
                )
                XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply), "\(field)=\(value)")
                XCTAssertEqual(permissionBehavior(reply), "ask", "\(field)=\(value)")
            }
        }
        let numericVerified = try decode(
            #"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":1}"#
        )
        XCTAssertEqual(permissionBehavior(numericVerified), "ask")
        let boolVersion = try decode(
            #"{"approvalPolicyVersion":true,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#
        )
        XCTAssertEqual(permissionBehavior(boolVersion), "ask")
    }

    func testSwitchStateValueAcceptsOnlyJSONIntegerZeroOrOne() throws {
        let cases: [(String, Int?)] = [
            ("0", 0), ("1", 1), ("false", nil), ("true", nil), ("0.5", nil), ("1.0", nil),
            (#""0""#, nil), ("2", nil), ("-1", nil), ("null", nil),
        ]
        for (raw, expected) in cases {
            let reply = try decode(#"{"switchState":\#(raw)}"#)
            XCTAssertEqual(HookSupport.switchStateValue(reply["switchState"]), expected, raw)
        }
        XCTAssertEqual(HookSupport.switchStateValue(0), 0)
        XCTAssertNil(HookSupport.switchStateValue(false))
        XCTAssertNil(HookSupport.switchStateValue(0.5))
    }

    private func decode(_ json: String, replacing field: String? = nil, with value: String = "") throws -> [String: Any] {
        var json = json
        if let field {
            json = json.replacingOccurrences(of: "\"\(field)\":0", with: "\"\(field)\":\(value)")
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func permissionBehavior(_ reply: [String: Any]?) -> String? {
        let output = ClaudeHookHandler.permissionRequestOutput(reply: reply)
        let hook = output["hookSpecificOutput"] as? [String: Any]
        return (hook?["decision"] as? [String: Any])?["behavior"] as? String
    }
}
