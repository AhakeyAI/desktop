import Foundation
import XCTest
@testable import AhaKeyConfigAgent
import AhaKeyConfigShared

final class CodexTaskMetadataTests: XCTestCase {
    // #201/#202: real tool payloads can exceed the old 64 KiB task-metadata limit.
    func testLargeRealHooksReachIndependentTaskSlotsIncludingWaitingAndDone() throws {
        let old = CodexHookHandler.dependencies
        defer { CodexHookHandler.dependencies = old }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = ProcessInfo.processInfo.systemUptime
        let lease = try WS3LiveTaskJournal.begin(directory: directory, now: clock)
        defer { WS3LiveTaskJournal.end(lease, directory: directory); try? FileManager.default.removeItem(at: directory) }
        var session = "session-a", registry = WS3TaskRegistry(), requests: [[String: Any]] = []
        CodexHookHandler.dependencies = .init(
            readStdin: { try! JSONSerialization.data(withJSONObject: ["session_id": session,
                "tool_input": ["command": String(repeating: "private", count: 20_000)]]) },
            parseContext: { _, _ in [:] }, sendRequest: { request, _ in
                requests.append(request)
                XCTAssertTrue(WS3LiveTaskJournal.publish(request: request, directory: directory, now: clock))
                return nil
            }, appendHookLog: { _, _, _, _, _, _, _ in }, emitPermissionStderr: { _, _, _, _ in },
            appendDiagnostic: { _, _, _, _, _, _, _, _, _, _, _ in },
            writeStdout: { _ in }, preparePolicy: {})
        func consume() throws {
            let request = try XCTUnwrap(requests.last)
            let task = try XCTUnwrap(request["task"] as? [String: String])
            XCTAssertEqual(task["session"], session)
            XCTAssertNil(request["tool_input"])
            let batch = try XCTUnwrap(WS3LiveTaskJournal.read(lease, directory: directory))
            let event = try XCTUnwrap(batch.events.last)
            XCTAssertTrue(registry.observe(event, at: clock))
        }
        CodexHookHandler.handleState(stateValue: 3); try consume()
        session = "session-b"
        CodexHookHandler.handleState(stateValue: 7); try consume()
        session = "session-a"
        CodexHookHandler.handlePermissionRequest(); try consume()
        XCTAssertEqual(registry.snapshot(at: clock).slots.map { $0?.state }, [.waiting, .running, nil, nil])
        CodexHookHandler.handleState(stateValue: 2); try consume()
        CodexHookHandler.handleState(stateValue: 5); try consume()
        XCTAssertEqual(registry.snapshot(at: clock).slots.map { $0?.state }, [.done, .running, nil, nil])
    }

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
            writeStdout: { output.append($0) }, preparePolicy: {},
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
