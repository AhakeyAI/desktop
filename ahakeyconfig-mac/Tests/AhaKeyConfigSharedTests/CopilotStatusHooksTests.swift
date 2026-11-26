import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CopilotStatusHooksTests: XCTestCase {
    func testLifecycleOwnsOnlyTheDedicatedFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let entry = home.appendingPathComponent("AhaKey Config/bin/ahakey-hook").path
        let adapter = try CopilotStatusHooks(home: home, entryPath: entry)
        XCTAssertEqual(adapter.configurationURL.path, home.path + "/.copilot/hooks/ahakey-studio.json")
        XCTAssertEqual(try adapter.status(), .absent)
        try adapter.uninstall()

        let neighbor = adapter.configurationURL.deletingLastPathComponent().appendingPathComponent("personal.json")
        try FileManager.default.createDirectory(at: neighbor.deletingLastPathComponent(), withIntermediateDirectories: true)
        let personal = Data("personal config".utf8)
        try personal.write(to: neighbor)
        try adapter.install()
        XCTAssertEqual(try adapter.status(), .configured)
        let installed = try Data(contentsOf: adapter.configurationURL)
        try adapter.install()
        XCTAssertEqual(try Data(contentsOf: adapter.configurationURL), installed)
        XCTAssertEqual(try Data(contentsOf: neighbor), personal)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: installed) as? [String: Any])
        let events = try XCTUnwrap(document["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(document["version"] as? Int, 1)
        XCTAssertEqual(Set(events.keys), ["UserPromptSubmit", "Stop", "SessionEnd"])
        for event in CopilotStatusHooks.Event.allCases {
            let hook = try XCTUnwrap(events[event.rawValue]?.first)
            XCTAssertEqual(hook["exec"] as? String, entry)
            XCTAssertEqual(hook["args"] as? [String], ["hook", event.hookArgument])
            XCTAssertNil(hook["bash"])
            XCTAssertNil(hook["command"])
        }

        try adapter.uninstall()
        XCTAssertEqual(try adapter.status(), .absent)
        XCTAssertEqual(try Data(contentsOf: neighbor), personal)
    }

    func testNonOwnedFileAndSymlinkAreNeverReplacedOrDeleted() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("Custom Copilot").path
        let adapter = try CopilotStatusHooks(home: home, copilotHome: custom, entryPath: "/AhaKey/ahakey-hook")
        XCTAssertEqual(adapter.configurationURL.path, custom + "/hooks/ahakey-studio.json")
        try FileManager.default.createDirectory(at: adapter.configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let foreign = Data(#"{"version":1,"hooks":{}}"#.utf8)
        try foreign.write(to: adapter.configurationURL)
        XCTAssertEqual(try adapter.status(), .conflict)
        XCTAssertThrowsError(try adapter.install()) { XCTAssertEqual($0 as? CopilotStatusHooks.Failure, .conflictingFile) }
        XCTAssertThrowsError(try adapter.uninstall())
        XCTAssertEqual(try Data(contentsOf: adapter.configurationURL), foreign)
        try FileManager.default.removeItem(at: adapter.configurationURL)
        let target = home.appendingPathComponent("personal.json")
        try foreign.write(to: target)
        try FileManager.default.createSymbolicLink(at: adapter.configurationURL, withDestinationURL: target)
        XCTAssertEqual(try adapter.status(), .conflict)
        XCTAssertThrowsError(try adapter.install())
        XCTAssertThrowsError(try adapter.uninstall())
        XCTAssertEqual(try Data(contentsOf: target), foreign)
    }

    func testLifecycleAcceptsOnlyMatchingEventsAndForwardsOnlyStateAndIdentity() {
        for (event, state) in [
            (CopilotStatusHooks.Event.promptSubmitted, 7),
            (.turnFinished, 5),
            (.sessionEnded, 8),
        ] {
            let payload = Data("""
                {"hook_event_name":"\(event.rawValue)","session_id":"copilot-42","prompt":"private","cwd":"/tmp"}
                """.utf8)
            let request = event.stateRequest(from: payload)
            XCTAssertEqual(CopilotStatusHooks.Event(hookArgument: event.hookArgument), event)
            XCTAssertEqual(request?["cmd"] as? String, "state")
            XCTAssertEqual(request?["value"] as? Int, state)
            XCTAssertEqual(request?["task"] as? [String: String], [
                "client": "copilot", "session": "copilot-42", "event": event.hookArgument,
            ])
            XCTAssertEqual(request?.count, 3)
            XCTAssertNil(event.stateRequest(from: Data(#"{"hook_event_name":"SessionStart","session_id":"copilot-42"}"#.utf8)))
            XCTAssertNil(event.stateRequest(from: Data("{\"hook_event_name\":\"\(event.rawValue)\"}".utf8)))
        }
        XCTAssertNil(CopilotStatusHooks.Event(hookArgument: "CopilotPermissionRequest"))
    }
}
