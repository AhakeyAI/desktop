import Foundation
import XCTest
@testable import AhaKeyConfigAgent

final class CodexTaskMetadataTests: XCTestCase {
    func testActualHookHandlersAttachSessionWithoutChangingPermissionOrResetRequests() {
        let old = CodexHookHandler.dependencies
        defer { CodexHookHandler.dependencies = old }
        var requests: [[String: Any]] = []
        var output: [String] = []
        CodexHookHandler.dependencies = .init(
            readStdin: { Data(#"{"session_id":"full-session","command":"private"}"#.utf8) },
            parseContext: { _, _ in [:] },
            sendRequest: { request, _ in
                requests.append(request)
                return ["approvalPolicyVersion": 1, "approvalAutoVerified": false, "switchState": 1]
            },
            appendHookLog: { _, _, _, _, _, _, _ in },
            emitPermissionStderr: { _, _, _, _ in },
            appendDiagnostic: { _, _, _, _, _, _, _, _, _, _, _ in },
            writeStdout: { output.append($0) }, policySink: { _ in },
            approvalControlDirectory: URL(fileURLWithPath: "/tmp/aha-task-control-\(UUID().uuidString)"))
        CodexHookHandler.handleState(stateValue: 2)
        CodexHookHandler.handlePermissionRequest()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0]["cmd"] as? String, "state_with_reset")
        XCTAssertEqual(requests[0]["resetValue"] as? Int, 5)
        XCTAssertEqual(requests[0]["delayMs"] as? Int, 12000)
        XCTAssertEqual(requests[1]["cmd"] as? String, "permission")
        XCTAssertEqual(requests[1]["value"] as? Int, 1)
        for request in requests {
            XCTAssertEqual((request["task"] as? [String: String])?["session"], "full-session")
            XCTAssertNil(request["command"])
        }
        XCTAssertEqual(output.first, "{}")
        XCTAssertFalse(output.last?.contains("allow") ?? true)
    }
}
