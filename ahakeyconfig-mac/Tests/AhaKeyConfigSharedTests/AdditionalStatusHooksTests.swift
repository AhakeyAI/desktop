import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class AdditionalStatusHooksTests: XCTestCase {
    func testClinePreflightsAllFilesBeforeInstallingAndKeepsExistingScripts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = try ClineStatusHooks(home: home, entryPath: "/tmp/Studio's Helper/ahakey-hook")
        let files = adapter.configurationURLs
        let custom = try XCTUnwrap(files.last)
        try FileManager.default.createDirectory(at: custom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("custom".utf8).write(to: custom)
        XCTAssertThrowsError(try adapter.update(install: true))
        XCTAssertFalse(adapter.isConfigured())
        XCTAssertEqual(try Data(contentsOf: custom), Data("custom".utf8))
        try FileManager.default.removeItem(at: custom)
        try adapter.update(install: true)
        XCTAssertTrue(adapter.isConfigured())
        XCTAssertTrue(files.allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) })
        try adapter.update(install: true)
        try adapter.update(install: false)
        XCTAssertFalse(adapter.isConfigured())
    }

    func testClineChecksIdentityAndIgnoresPromptText() throws {
        let payload = Data(#"{"hookName":"TaskComplete","taskId":"task-27","taskComplete":{"task":"ignore"}}"#.utf8)
        let result = try XCTUnwrap(ClineStatusHooks.Event.complete.stateRequest(from: payload))
        XCTAssertEqual(result["cmd"] as? String, "state")
        XCTAssertEqual(result["value"] as? Int, 5)
        XCTAssertEqual(result["task"] as? [String: String],
                       ["client": "cline", "session": "task-27", "event": "ClineTaskComplete"])
        XCTAssertNil(ClineStatusHooks.Event.start.stateRequest(from: payload))
        XCTAssertNotNil(ClineStatusHooks.Event.start.stateRequest(from: Data(#"{"hookName":"agent_start","taskId":"task-27"}"#.utf8)))
        XCTAssertNil(ClineStatusHooks.Event.start.stateRequest(from: Data(#"{"hookName":"agent_start","taskId":"task-27","parent_agent_id":"a"}"#.utf8)))
        XCTAssertNil(ClineStatusHooks.Event.start.stateRequest(from: Data(#"{"hookName":"TaskStart"}"#.utf8)))
    }

    func testPiUsesFinalSettlementAndLeavesOtherExtensionsIntact() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = try PiStatusHooks(home: home, agentDirectory: home.appendingPathComponent("custom").path,
                                        entryPath: "/tmp/ahakey-hook")
        try adapter.update(install: true)
        let source = try String(contentsOf: adapter.configurationURL, encoding: .utf8)
        XCTAssertTrue(source.contains(#"pi.on("agent_settled""#))
        XCTAssertFalse(source.contains(#"pi.on("agent_end""#))
        let other = adapter.configurationURL.deletingLastPathComponent().appendingPathComponent("unmanaged.ts")
        try Data("existing".utf8).write(to: other)
        try adapter.update(install: false)
        XCTAssertEqual(try Data(contentsOf: other), Data("existing".utf8))
    }

    func testOpenClawInstallsOnlyItsPluginAndKeepsGatewayConfiguration() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("openclaw")
        let adapter = try OpenClawStatusHooks(home: home, stateDirectory: root.path, entryPath: "/tmp/ahakey-hook")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("openclaw.json")
        let original = Data(#"{"plugins":{"deny":["ahakey-studio-status"]}}"#.utf8)
        try original.write(to: config)
        try adapter.update(install: true)
        try adapter.update(install: true)
        XCTAssertTrue(adapter.isConfigured())
        let script = try XCTUnwrap(adapter.configurationURLs.last)
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.contains(#"payload: "metadata""#))
        XCTAssertTrue(text.contains("executionSettled === true"))
        XCTAssertFalse(text.contains("allowConversationAccess"))
        try adapter.update(install: false)
        XCTAssertFalse(adapter.isConfigured())
        XCTAssertEqual(try Data(contentsOf: config), original)
    }

    func testNewStatusRequestsContainOnlyMetadata() throws {
        let input = Data(#"{"status":"done","session_id":"session-46","prompt":"private"}"#.utf8)
        for tool in [PassiveStatusHook.pi, .openClaw] {
            let result = try XCTUnwrap(tool.stateRequest(from: input))
            XCTAssertEqual(result.count, 3)
            XCTAssertEqual(result["value"] as? Int, 5)
            XCTAssertNil(tool.stateRequest(from: Data(#"{"status":"done","session_id":""}"#.utf8)))
        }
    }
}
