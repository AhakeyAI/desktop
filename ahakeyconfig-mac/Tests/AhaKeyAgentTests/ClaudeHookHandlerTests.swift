import XCTest
@testable import AhaKeyConfigAgent
import AhaKeyConfigShared

final class ClaudeHookHandlerTests: XCTestCase {
    private var controlDirectory: URL!
    override func setUpWithError() throws {
        controlDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-hook-control-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: controlDirectory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: controlDirectory)
    }

    func testFreshPhysicalLeverControlsBothHooks() {
        for switchState in 0...1 {
            let status = AgentDeviceStatus(
                battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
                workMode: 0, lightMode: 16, switchState: switchState
            )
            let reply = AhaKeyAgent.permissionReply(status)
            let output = ClaudeHookHandler.preToolUseOutput(reply: reply, controlDirectory: controlDirectory)
            let hook = output?["hookSpecificOutput"] as? [String: Any]
            XCTAssertEqual(hook?["permissionDecision"] as? String, switchState == 0 ? "allow" : nil)
            XCTAssertEqual(permissionBehavior(reply), switchState == 0 ? "allow" : nil)
        }
    }

    func testUnverifiedOrUnknownStateDefersBothHooks() {
        let failedVerification: [String: Any] = [
            "approvalPolicyVersion": 1, "physicalSwitchState": 0,
            "switchState": 0, "approvalAutoVerified": false,
        ]
        for reply: [String: Any]? in [nil, ["switchState": 0], ["switchState": 1], failedVerification] {
            XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply, controlDirectory: controlDirectory))
            XCTAssertNil(permissionBehavior(reply))
            XCTAssertTrue(ClaudeHookHandler.permissionRequestOutput(reply: reply, controlDirectory: controlDirectory).isEmpty)
        }
    }

    func testFixturePauseStillOverridesVerifiedAutomaticLever() throws {
        try Data([1]).write(to: controlDirectory.appendingPathComponent("all.paused"))
        let reply: [String: Any] = ["approvalPolicyVersion": 1, "physicalSwitchState": 0,
                                    "switchState": 0, "approvalAutoVerified": true]
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply, controlDirectory: controlDirectory))
        XCTAssertNil(permissionBehavior(reply))
        XCTAssertTrue(ClaudeHookHandler.permissionRequestOutput(reply: reply, controlDirectory: controlDirectory).isEmpty)
    }

    func testManualPermissionRequestLeavesNativePromptUnchanged() throws {
        let status = AgentDeviceStatus(battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
            workMode: 0, lightMode: 16, switchState: 1)
        let output = ClaudeHookHandler.permissionRequestOutput(reply: AhaKeyAgent.permissionReply(status), controlDirectory: controlDirectory)
        XCTAssertTrue(output.isEmpty, "PermissionRequest accepts allow/deny, not an ask decision")
        let encoded = try JSONSerialization.data(withJSONObject: output)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encoded) as? [String: String], [:])
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
                XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply, controlDirectory: controlDirectory), "\(field)=\(value)")
                XCTAssertNil(permissionBehavior(reply), "\(field)=\(value)")
            }
        }
        let numericVerified = try decode(
            #"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":1}"#
        )
        XCTAssertNil(permissionBehavior(numericVerified))
        let boolVersion = try decode(
            #"{"approvalPolicyVersion":true,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#
        )
        XCTAssertNil(permissionBehavior(boolVersion))
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
        let output = ClaudeHookHandler.permissionRequestOutput(reply: reply, controlDirectory: controlDirectory)
        let hook = output["hookSpecificOutput"] as? [String: Any]
        return (hook?["decision"] as? [String: Any])?["behavior"] as? String
    }
}
