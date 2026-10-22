import XCTest
@testable import AhaKeyConfigAgent
import AhaKeyConfigShared

final class KimiHookHandlerTests: XCTestCase {
    func testNativeHookPublishesRealSessionStateWithoutApprovalQueryOrPolicyWrites() throws {
        var sent: [[String: Any]] = []
        KimiHookHandler.handlePreToolPermission(stdin: Data(#"{"session_id":"native-fixture","hook_event_name":"PreToolUse"}"#.utf8),
            layout: .nativeV2, send: { request, timeout in
                sent.append(request)
                XCTAssertEqual(timeout, 2)
                return ["approvalAutoVerified": true, "switchState": 0]
            })
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["cmd"] as? String, "state")
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
}
