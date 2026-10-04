import Foundation
import XCTest
@testable import AhaKeyConfigAgent

final class CursorLegacyPermissionsCleanupTests: XCTestCase {
    func testRemovesOnlyTheExactAhaKeyGeneratedFile() throws {
        let directory = try temporaryCursorDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let permissions = directory.appendingPathComponent("permissions.json")
        let marker = directory.appendingPathComponent(".ahakey_had_no_permissions_json")
        try Data(#"{"terminalAllowlist":["cd","git"]}"#.utf8).write(to: permissions)
        try Data().write(to: marker)

        XCTAssertTrue(CursorPermissionsJsonLeverSync.removeLegacyGeneratedPermissionsIfSafe(
            in: directory, managedPrefixes: ["cd", "git"]
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: permissions.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent("permissions.json.ahakey.legacy-allowlist.bak").path))
    }

    func testPreservesPermissionsWhenUserAddedAnEntry() throws {
        let directory = try temporaryCursorDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let permissions = directory.appendingPathComponent("permissions.json")
        let marker = directory.appendingPathComponent(".ahakey_had_no_permissions_json")
        let original = Data(#"{"terminalAllowlist":["cd","git","custom"]}"#.utf8)
        try original.write(to: permissions)
        try Data().write(to: marker)

        XCTAssertFalse(CursorPermissionsJsonLeverSync.removeLegacyGeneratedPermissionsIfSafe(
            in: directory, managedPrefixes: ["cd", "git"]
        ))
        XCTAssertEqual(try Data(contentsOf: permissions), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    private func temporaryCursorDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-legacy-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
