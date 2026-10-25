import XCTest
@testable import AhaKeyConfigAgent
import AhaKeyConfigShared

final class KimiHookHandlerTests: XCTestCase {
    func testNativeHookPublishesRealSessionStateWithoutApprovalQueryOrPolicyWrites() throws {
        var sent: [[String: Any]] = []
        KimiHookHandler.handlePreToolPermission(stdin: Data(#"{"session_id":"native-fixture","hook_event_name":"PreToolUse"}"#.utf8),
            layout: .nativeV2, approvalObservations: true, send: { request, timeout in
                sent.append(request)
                XCTAssertEqual(timeout, 2)
                return ["approvalAutoVerified": true, "switchState": 0]
            })
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["cmd"] as? String, "state")
        XCTAssertEqual(sent[0]["value"] as? Int, 3, "PreToolUse precedes permission checks; read-only tools must not be labeled as waiting")
        let task = try XCTUnwrap(sent[0]["task"] as? [String: String])
        XCTAssertEqual(WS3TaskMetadata(dictionary: task)?.reference,
            WS3TaskMetadata(client: .kimi, session: "native-fixture", event: "KimiPreToolUse")?.reference)
    }
    func testMissingNativeSessionDoesNotInventTaskIdentity() {
        KimiHookHandler.handlePreToolPermission(stdin: Data("{}".utf8), layout: .nativeV2, send: { request, _ in
            XCTAssertEqual(request["cmd"] as? String, "state")
            XCTAssertNil(request["task"])
            return nil
        })
    }
    func testAlreadyRunningNativeTUIKeepsItsOldObservationContractUntilReload() {
        KimiHookHandler.handlePreToolPermission(stdin: Data(#"{"session_id":"old-native"}"#.utf8),
            layout: .nativeV2, approvalObservations: false, send: { request, _ in
                XCTAssertEqual(request["cmd"] as? String, "state")
                XCTAssertEqual(request["value"] as? Int, 1)
                return nil
            })
    }
    func testNativePermissionObservationTransitionsWithoutApprovalDecisions() throws {
        let input = Data(#"{"session_id":"native-fixture","tool_input":{"command":"private"}}"#.utf8)
        var registry = WS3TaskRegistry()
        for (event, expected) in [("KimiPermissionRequest", WS3TaskState.waiting), ("KimiPermissionResult", .running)] {
            let request = try XCTUnwrap(HookClient.stateRequest(event: event, stdin: input))
            XCTAssertEqual(request["cmd"] as? String, "state")
            XCTAssertNil(request["permissionDecision"])
            XCTAssertNil(request["tool_input"])
            let metadata = try XCTUnwrap(WS3TaskMetadata(dictionary: XCTUnwrap(request["task"] as? [String: String])))
            registry.observe(metadata, state: UInt8(try XCTUnwrap(request["value"] as? Int)), at: 1)
            XCTAssertEqual(registry.overview(connected: true, at: 1).tasks.first?.state, expected)
        }
    }
}
