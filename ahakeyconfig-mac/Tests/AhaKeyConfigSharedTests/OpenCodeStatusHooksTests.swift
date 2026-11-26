import XCTest
@testable import AhaKeyConfigShared

final class OpenCodeStatusHooksTests: XCTestCase {
    func testKeepsOtherPluginsAndRefusesAnExistingSameNameFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appendingPathComponent("config directory")
        let adapter = try OpenCodeStatusHooks(home: home, configHome: config.path, entryPath: "/a b/ahakey-hook")
        let plugin = adapter.configurationURL
        XCTAssertEqual(plugin.path, config.appendingPathComponent("opencode/plugins/ahakey-studio.js").path)
        try adapter.update(install: true)
        XCTAssertTrue(adapter.isConfigured())
        let expected = try Data(contentsOf: plugin)
        let other = plugin.deletingLastPathComponent().appendingPathComponent("my-plugin.js")
        try Data("user".utf8).write(to: other)
        try adapter.update(install: true)
        XCTAssertEqual(try Data(contentsOf: plugin), expected)
        try adapter.update(install: false)
        XCTAssertFalse(adapter.isConfigured())
        XCTAssertEqual(try Data(contentsOf: other), Data("user".utf8))
        try Data("other owner".utf8).write(to: plugin)
        XCTAssertThrowsError(try adapter.update(install: true))
        XCTAssertThrowsError(try adapter.update(install: false))
        XCTAssertEqual(try Data(contentsOf: plugin), Data("other owner".utf8))
    }

    func testTracksOnlyKnownStatusesAndAValidSession() throws {
        for (status, expected) in [("busy", 7), ("retry", 7), ("idle", 5), ("deleted", 8)] {
            let data = try JSONSerialization.data(withJSONObject: ["status": status, "session_id": "ses_1", "prompt": "ignored"])
            let request = try XCTUnwrap(OpenCodeStatusHooks.stateRequest(from: data))
            XCTAssertEqual(request["cmd"] as? String, "state")
            XCTAssertEqual(request["value"] as? Int, expected)
            XCTAssertEqual(request["task"] as? [String: String],
                           ["client": "openCode", "session": "ses_1", "event": "OpenCodeStatus"])
            XCTAssertEqual(request.count, 3)
        }
        XCTAssertNil(OpenCodeStatusHooks.stateRequest(from: Data(#"{"status":"other","session_id":"ses_1"}"#.utf8)))
        XCTAssertNil(OpenCodeStatusHooks.stateRequest(from: Data(#"{"status":"busy","session_id":""}"#.utf8)))
    }
}
