import XCTest
@testable import AhaKeyConfigShared

final class CursorApprovalPolicySyncTests: XCTestCase {
    func testRevocationKeepsUserEditsAndPreexistingTokensAndBlocksLateAuto() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let cursor = base.appendingPathComponent("cursor"), control = base.appendingPathComponent("control")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let cli = cursor.appendingPathComponent("cli-config.json"), desktop = cursor.appendingPathComponent("permissions.json")
        try Data(#"{"permissions":{"allow":["Shell(cd)"],"deny":["secret"]},"approvalMode":"manual"}"#.utf8).write(to: cli)
        XCTAssertTrue(CursorApprovalPolicySync.apply(auto: true, kind: .cli, directory: cursor, controlDirectory: control))
        XCTAssertTrue(CursorApprovalPolicySync.apply(auto: true, kind: .desktop, directory: cursor, controlDirectory: control))
        var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cli)) as? [String: Any])
        changed["newUserSetting"] = 42
        try JSONSerialization.data(withJSONObject: changed).write(to: cli)
        XCTAssertTrue(ApprovalAutomationControl.revoke(.cursor, directory: control,
            codexURL: base.appendingPathComponent("missing"), kimiURL: base.appendingPathComponent("missing2"), cursorDirectory: cursor))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cli)) as? [String: Any])
        XCTAssertEqual(result["approvalMode"] as? String, "manual")
        XCTAssertEqual(result["newUserSetting"] as? Int, 42)
        XCTAssertEqual((result["permissions"] as? [String: Any])?["allow"] as? [String], ["Shell(cd)"])
        let permissions = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: desktop)) as? [String: Any])
        XCTAssertEqual(permissions["terminalAllowlist"] as? [String], [])
        XCTAssertFalse(CursorApprovalPolicySync.apply(auto: true, kind: .desktop, directory: cursor, controlDirectory: control))
    }
    func testLegacyBackupRemovesOnlyInjectedWildcardAndPreservesLaterUserChanges() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("permissions.json")
        try Data(#"{"terminalAllowlist":["git"]}"#.utf8).write(to: url.appendingPathExtension("ahakey.lever0.bak"))
        try Data(#"{"terminalAllowlist":["git","*","ls"],"newSetting":true}"#.utf8).write(to: url)
        XCTAssertTrue(CursorApprovalPolicySync.releaseAll(directory: dir))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(result["terminalAllowlist"] as? [String], ["git", "ls"])
        XCTAssertEqual(result["newSetting"] as? Bool, true)
    }
    func testNewCliFileKeepsVersionSchemaFromMain() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(CursorApprovalPolicySync.apply(auto: true, kind: .cli, directory: dir, controlDirectory: dir.appendingPathComponent("control")))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("cli-config.json"))) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
    }
    func testMalformedUserConfigIsNeverReplaced() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cli-config.json"), bad = Data("{bad".utf8)
        try bad.write(to: url)
        XCTAssertFalse(CursorApprovalPolicySync.apply(auto: true, kind: .cli, directory: dir, controlDirectory: dir.appendingPathComponent("control")))
        XCTAssertEqual(try Data(contentsOf: url), bad)
    }
}
