import XCTest
@testable import AhaKeyConfigAgent

/// AHK-053：Codex PermissionRequest 只在回包 switchState 为 JSON 整数 0 时自动批准。
final class CodexHookHandlerTests: XCTestCase {
    override func tearDown() {
        CodexHookHandler.dependencies = .production
        super.tearDown()
    }

    func testOnlyIntegerZeroWithVerifiedProofAutoApprovesWithoutRewritingPolicy() throws {
        let control = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: control) }
        let cases: [(String, String?, [Bool])] = [
            ("0", "allow", []), ("1", nil, []),
            ("false", nil, []), ("0.5", nil, []), ("-0.9", nil, []), (#""0""#, nil, []), ("2", nil, []),
        ]
        for (raw, expectedBehavior, expectedPolicy) in cases {
            let reply = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(#"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":\#(raw),"approvalAutoVerified":true}"#.utf8)) as? [String: Any]
            )
            var stdout: [String] = []
            var policy: [Bool] = []
            CodexHookHandler.dependencies = .init(
                readStdin: { Data("{}".utf8) },
                parseContext: { _, _ in [:] },
                sendRequest: { _, _ in reply },
                appendHookLog: { _, _, _, _, _, _, _ in },
                emitPermissionStderr: { _, _, _, _ in },
                appendDiagnostic: { _, _, _, _, _, _, _, _, _, _, _ in },
                writeStdout: { stdout.append($0) },
                preparePolicy: { policy.append(true) },
                approvalControlDirectory: control
            )
            CodexHookHandler.handlePermissionRequest()

            let out = try XCTUnwrap(stdout.last.flatMap { $0.data(using: .utf8) })
            let hook = try XCTUnwrap(
                (JSONSerialization.jsonObject(with: out) as? [String: Any])?["hookSpecificOutput"] as? [String: Any]
            )
            XCTAssertEqual((hook["decision"] as? [String: Any])?["behavior"] as? String, expectedBehavior, raw)
            XCTAssertEqual(policy, expectedPolicy, raw)
        }
    }
}
