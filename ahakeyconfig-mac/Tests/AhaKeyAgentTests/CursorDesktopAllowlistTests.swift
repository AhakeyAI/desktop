import XCTest
@testable import AhaKeyConfigAgent

final class CursorDesktopAllowlistTests: XCTestCase {
    func testManualDialUsesNativeCursorPromptInsteadOfBlockingTool() {
        XCTAssertEqual(CursorHookHandler.permissionForEvent("preToolUse", isAuto: false), "allow")
        XCTAssertEqual(CursorHookHandler.permissionForEvent("beforeShellExecution", isAuto: false), "ask")
        XCTAssertEqual(CursorHookHandler.permissionForEvent("beforeMCPExecution", isAuto: false), "ask")
        XCTAssertEqual(CursorHookHandler.permissionForEvent("beforeShellExecution", isAuto: true), "allow")
    }

    func testAutoDialCoversArbitraryCommandsAndManualRestoresSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("permissions.json")
        let original = #"{"terminalAllowlist":["git"],"otherSetting":true}"#
        try original.write(to: url, atomically: true, encoding: .utf8)

        CursorPermissionsJsonLeverSync.apply(switchStateAuto: true, permissionsURL: url)
        let auto = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(auto["terminalAllowlist"] as? [String], ["git", "*"])
        XCTAssertEqual(auto["otherSetting"] as? Bool, true)

        CursorPermissionsJsonLeverSync.apply(switchStateAuto: false, permissionsURL: url)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
        XCTAssertEqual(restored, try XCTUnwrap(JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary))
    }
}
