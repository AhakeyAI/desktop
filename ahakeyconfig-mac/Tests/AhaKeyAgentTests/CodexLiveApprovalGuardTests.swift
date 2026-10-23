import Foundation
import XCTest
@testable import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

final class CodexLiveApprovalGuardTests: XCTestCase {
    private func run(mode: String?, reply: [String: Any]?, paused: Bool = false, state: UInt8 = 3, payloadBytes: Int = 0,
                     check: (_ requests: [[String: Any]], _ preparations: Int, _ output: [String: Any]) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        if paused { try Data([1]).write(to: directory.appendingPathComponent("codex.paused")) }
        let original = CodexHookHandler.dependencies
        defer { CodexHookHandler.dependencies = original }
        var body: [String: Any] = ["session_id": "fixture-session", "command": "private"]
        if let mode { body["permission_mode"] = mode }
        if payloadBytes > 0 { body["tool_input"] = ["content": String(repeating: "x", count: payloadBytes)] }
        let data = try JSONSerialization.data(withJSONObject: body)
        var requests: [[String: Any]] = [], output = "", preparations = 0
        CodexHookHandler.dependencies = .init(readStdin: { data }, parseContext: { HookSupport.parseStdinContext($0, label: $1) },
            sendRequest: { request, _ in requests.append(request); return reply },
            appendHookLog: { _, _, _, _, _, _, _ in }, emitPermissionStderr: { _, _, _, _ in },
            appendDiagnostic: { _, _, _, _, _, _, _, _, _, _, _ in }, writeStdout: { output = $0 },
            preparePolicy: { preparations += 1 }, approvalControlDirectory: directory)
        CodexHookHandler.handleState(stateValue: state)
        try check(requests, preparations, try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]))
    }
    private func verified(_ physical: Int) -> [String: Any] {
        ["approvalPolicyVersion": 1, "physicalSwitchState": physical, "switchState": physical, "approvalAutoVerified": physical == 0]
    }
    func testNativePreToolPreservesTaskStateWithoutExtraApprovalLookup() throws {
        try run(mode: "default", reply: nil) { requests, preparations, output in
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0]["cmd"] as? String, "state")
            XCTAssertEqual((requests[0]["task"] as? [String: String])?["session"], "fixture-session")
            XCTAssertNil(requests[0]["command"])
            XCTAssertEqual(preparations, 0)
            XCTAssertTrue(output.isEmpty)
        }
    }
    func testLargeNativeToolInputDoesNotBecomeAnUnknownBypass() throws {
        try run(mode: "default", reply: nil, payloadBytes: 131_072) { requests, preparations, output in
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0]["cmd"] as? String, "state")
            XCTAssertEqual(preparations, 0)
            XCTAssertTrue(output.isEmpty)
        }
    }
    func testFullAccessRemainsPassThroughWithVerifiedAuto() throws {
        try run(mode: "bypassPermissions", reply: verified(0)) { requests, preparations, output in
            XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(requests[0]["cmd"] as? String, "state")
            XCTAssertEqual(preparations, 0)
            XCTAssertTrue(output.isEmpty)
        }
    }
    func testManualOfflineMalformedAndPausedFullAccessUseOriginalPolicy() throws {
        let cases: [([String: Any]?, Bool)] = [(verified(1), false), (nil, false), (["switchState": 0], false), (verified(0), true)]
        for (reply, paused) in cases {
            try run(mode: "bypassPermissions", reply: reply, paused: paused) { requests, preparations, output in
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(requests[0]["cmd"] as? String, "state")
                XCTAssertEqual(preparations, 0)
                XCTAssertTrue(output.isEmpty)
            }
        }
    }
    func testUnknownModeUsesOriginalPolicy() throws {
        try run(mode: nil, reply: nil) { _, _, output in
            XCTAssertTrue(output.isEmpty)
        }
    }
    func testSessionStartDoesNotChangeTheUsersPolicy() throws {
        try run(mode: "bypassPermissions", reply: verified(0), state: 4) { requests, preparations, output in
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(preparations, 0)
            XCTAssertTrue(output.isEmpty)
        }
    }
}
