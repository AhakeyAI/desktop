import Foundation
import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

final class CursorStateRoutingTests: XCTestCase {
    func testInstalledPromptAndReadHooksReachTaskStateWithoutApproval() throws {
        for (event, value) in [("beforeSubmitPrompt", 7), ("beforeReadFile", 3)] {
            let stdin = Data(#"{"conversation_id":"cursor-session","session_id":"fallback","prompt":"private","content":"secret","file_path":"private-path"}"#.utf8)
            let request = try XCTUnwrap(HookClient.stateRequest(event: event, stdin: stdin))
            XCTAssertEqual(request["cmd"] as? String, "state")
            XCTAssertEqual(request["value"] as? Int, value)
            let metadata = try XCTUnwrap(request["task"] as? [String: String])
            XCTAssertEqual(metadata, ["client": "cursor", "session": "cursor-session", "event": event])
            XCTAssertEqual(Set(request.keys), ["cmd", "value", "task"])
            var registry = WS3TaskRegistry()
            XCTAssertTrue(registry.observe(try XCTUnwrap(WS3TaskMetadata(dictionary: metadata)), state: UInt8(value), at: 0))
            XCTAssertEqual(registry.overview(connected: true, at: 0).tasks.first?.state, .running)
        }
    }
    func testMissingRealIdentityNeverInventsTaskOrApproval() throws {
        for event in ["beforeSubmitPrompt", "beforeReadFile"] {
            let request = try XCTUnwrap(HookClient.stateRequest(event: event, stdin: Data(#"{"file_path":"not-a-session"}"#.utf8)))
            XCTAssertEqual(request["cmd"] as? String, "state")
            XCTAssertNil(request["task"])
            XCTAssertNil(request["permission"])
        }
    }
    func testSpecializedPermissionAndUnknownRoutesAreNotSharedStates() {
        for event in ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "PermissionRequest", "unknown"] {
            XCTAssertNil(HookClient.stateRequest(event: event, stdin: Data()))
        }
    }

}
