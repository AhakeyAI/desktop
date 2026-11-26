import XCTest
@testable import AhaKeyConfigShared

final class AntigravityStatusHooksTests: XCTestCase {
    func testInstallationAndUninstallationKeepOtherNamedHooks() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = try AntigravityStatusHooks(home: home, entryPath: "/tmp/Studio's Agent/ahakey-hook")
        let file = adapter.configurationURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"company-hook":{"enabled":false,"Stop":[]}}"#.utf8)
        try original.write(to: file)
        try adapter.update(install: true)
        XCTAssertTrue(adapter.isConfigured())
        let once = try Data(contentsOf: file)
        try adapter.update(install: true)
        XCTAssertEqual(try Data(contentsOf: file), once)
        try adapter.update(install: false)
        XCTAssertFalse(adapter.isConfigured())
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(restored.keys.sorted(), ["company-hook"])
    }

    func testAnExistingSameNameDefinitionIsPreserved() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = try AntigravityStatusHooks(home: home, entryPath: "/tmp/ahakey-hook")
        let file = adapter.configurationURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let conflict = Data(#"{"ahakey-studio-status":{"Stop":[]}}"#.utf8)
        try conflict.write(to: file)
        XCTAssertThrowsError(try adapter.update(install: true))
        XCTAssertThrowsError(try adapter.update(install: false))
        XCTAssertEqual(try Data(contentsOf: file), conflict)
    }

    func testHookUsesOnlyTheDocumentedConversationIdentityAndIdleState() throws {
        let start = AntigravityStatusHooks.Event.preInvocation
        let stop = AntigravityStatusHooks.Event.stop
        let conversation = UUID()
        func payload(_ fields: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: fields.merging([
                "conversationId": conversation.uuidString, "lastUserInput": "ignored"
            ]) { current, _ in current })
        }
        let started = try XCTUnwrap(start.stateRequest(from: payload(["invocationNum": 0])))
        XCTAssertEqual(started["cmd"] as? String, "state")
        XCTAssertEqual(started["task"] as? [String: String], [
            "client": "antigravity", "session": conversation.uuidString, "event": "AntigravityPreInvocation"
        ])
        XCTAssertEqual(started["value"] as? Int, 7)
        XCTAssertEqual(try stop.stateRequest(from: payload(["executionNum": 1, "fullyIdle": false]))?["value"] as? Int, 7)
        XCTAssertEqual(try stop.stateRequest(from: payload(["executionNum": 1, "fullyIdle": true]))?["value"] as? Int, 5)
        XCTAssertNil(try stop.stateRequest(from: payload(["executionNum": 1])))
        XCTAssertEqual(stop.response, #"{"decision":"stop"}"#)
    }
}
