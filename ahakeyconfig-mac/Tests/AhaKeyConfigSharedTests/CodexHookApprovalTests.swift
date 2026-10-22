import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexHookApprovalTests: XCTestCase {
    func testOnlyExplicitNativeModeSkipsAdditionalVerification() {
        XCTAssertFalse(CodexHookApproval.requiresPreToolVerification(permissionMode: "default"))
        for mode in ["bypassPermissions", "future", "", nil] as [String?] {
            XCTAssertTrue(CodexHookApproval.requiresPreToolVerification(permissionMode: mode))
        }
    }
    func testUnverifiedBypassIsDeniedRatherThanUnsupportedAsk() throws {
        XCTAssertNil(CodexHookApproval.bypassPreToolOutput(verifiedAuto: true))
        let output = try XCTUnwrap(CodexHookApproval.bypassPreToolOutput(verifiedAuto: false))
        let hook = try XCTUnwrap(output["hookSpecificOutput"] as? [String: String])
        XCTAssertEqual(hook["hookEventName"], "PreToolUse")
        XCTAssertEqual(hook["permissionDecision"], "deny")
        XCTAssertTrue(hook["permissionDecisionReason"]?.contains("native approvals") == true)
    }
    func testNativePermissionRequestsOnlyGrantVerifiedAuto() throws {
        for verified in [false, true] {
            let hook = try XCTUnwrap(CodexHookApproval.permissionRequestOutput(verifiedAuto: verified)["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(hook["hookEventName"] as? String, "PermissionRequest")
            XCTAssertEqual((hook["decision"] as? [String: String])?["behavior"], verified ? "allow" : nil)
        }
    }
    func testOwnedBypassMigratesBeforeNextSessionButUserPolicySurvives() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.toml")
        try "approval_policy = \"on-request\" # retain\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexConfigLeverSync.apply(switchStateAuto: true, configURL: url), .replaced)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("ahakey-auto-lease").path))
        XCTAssertEqual(CodexConfigLeverSync.migrateLegacyPolicy(configURL: url), .replaced)
        XCTAssertEqual(try String(contentsOf: url), "approval_policy = \"on-request\" # retain\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("ahakey-auto-lease").path))
        try "approval_policy = \"never\" # user's own\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexConfigLeverSync.migrateLegacyPolicy(configURL: url), .noLegacyPolicy)
        XCTAssertEqual(try String(contentsOf: url), "approval_policy = \"never\" # user's own\n")
    }
    func testMissingConfigDropsOldLeaseBeforeUserRecreatesPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.toml")
        try "approval_policy = \"on-request\"\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexConfigLeverSync.apply(switchStateAuto: true, configURL: url), .replaced)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(CodexConfigLeverSync.migrateLegacyPolicy(configURL: url), .missingConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("ahakey-auto-lease").path))
        try "approval_policy = \"never\"\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexConfigLeverSync.migrateLegacyPolicy(configURL: url), .noLegacyPolicy)
    }
    func testCorruptLeaseDoesNotClaimUserPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.toml")
        let original = "approval_policy = \"never\"\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        try Data([2]).write(to: url.appendingPathExtension("ahakey-auto-lease"))
        guard case .unsupportedSyntax = CodexConfigLeverSync.migrateLegacyPolicy(configURL: url) else {
            return XCTFail("Invalid lease was treated as ownership")
        }
        XCTAssertEqual(try String(contentsOf: url), original)
    }

}
