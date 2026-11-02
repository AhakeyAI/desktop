import XCTest
@testable import AhaKeyConfigAgent

final class OpenCodeHookHandlerTests: XCTestCase {
    /// 拨杆在自动档且经过校验 → 只在 evaluate 里放行。
    func testVerifiedAutoLeverAllows() throws {
        let reply = try decode(#"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#)
        XCTAssertEqual(HookSupport.verifiedSwitchState(reply), 0)
        XCTAssertEqual(decision(reply), "allow")
    }

    /// 手动档 → 交回 opencode 自己问人。
    func testManualLeverDefersToTrUI() throws {
        let reply = try decode(#"{"approvalPolicyVersion":1,"physicalSwitchState":1,"switchState":1,"approvalAutoVerified":true}"#)
        XCTAssertEqual(HookSupport.verifiedSwitchState(reply), 1)
        XCTAssertEqual(decision(reply), "ask")
    }

    /// fail-safe：连不上 agent / 回包不完整 / 未验证自动档，一律 ask。
    func testUnknownOrUnverifiedStateIsFailSafe() throws {
        let unverifiedAuto = try decode(#"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":false}"#)
        let missingPolicy = try decode(#"{"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#)
        let mismatched = try decode(#"{"approvalPolicyVersion":1,"physicalSwitchState":1,"switchState":0,"approvalAutoVerified":true}"#)
        let cachedOnly = try decode(#"{"switchState":0}"#)
        for reply: [String: Any]? in [nil, cachedOnly, unverifiedAuto, missingPolicy, mismatched] {
            XCTAssertNil(HookSupport.verifiedSwitchState(reply))
            XCTAssertEqual(decision(reply), "ask")
        }
    }

    /// 布尔 / 小数 / 字符串 / 越界值都不能被当成拨杆 0 而自动批准。
    func testMalformedTypesNeverAllow() throws {
        let malformed = [#"false"#, #"0.5"#, #"-0.9"#, #""0""#, #"2"#, #"-1"#]
        for value in malformed {
            let reply = try decode(
                #"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#,
                replacing: "switchState", with: value
            )
            XCTAssertEqual(decision(reply), "ask", value)
        }
    }

    /// 回包必须永远带决策字段，且 fail-safe 时标记出来（plugin 靠这个判断能否放行）。
    func testDecisionPayloadAlwaysCarriesDecision() {
        let allow = OpenCodeHookHandler.decisionPayload(decision: .allow, switchState: 0, toolContext: [:])
        XCTAssertEqual(allow["decision"] as? String, "allow")
        XCTAssertEqual(allow["switchState"] as? Int, 0)

        let failSafe = OpenCodeHookHandler.decisionPayload(decision: .ask, switchState: nil, toolContext: ["tool_name": "Bash"])
        XCTAssertEqual(failSafe["decision"] as? String, "ask")
        XCTAssertTrue(failSafe["failSafe"] as? Bool ?? false)
        XCTAssertEqual(failSafe["action"] as? String, "Bash")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(failSafe))
    }

    private func decision(_ reply: [String: Any]?) -> String? {
        let switchState = HookSupport.verifiedSwitchState(reply)
        return (switchState == 0 ? OpenCodeHookHandler.Decision.allow : .ask).rawValue
    }

    private func decode(_ json: String, replacing field: String? = nil, with value: String = "") throws -> [String: Any] {
        var json = json
        if let field {
            json = json.replacingOccurrences(of: "\"\(field)\":0", with: "\"\(field)\":\(value)")
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}
