import AhaKeyConfigShared
import XCTest
@testable import AhaKeyConfig

final class StudioHookEntryInstallerTests: XCTestCase {
    func testFailedPreflightKeepsTheLastWorkingEntryAndUpgradeReusesThePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey hook test \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("ahakeyconfig-agent")
        let installation = CodexHookInstallation(directory: root)
        let destination = installation.entryURL
        let report = String(decoding: try JSONEncoder().encode(HookEntrySelfCheck.current), as: UTF8.self)

        func putScript(_ script: String) throws {
            try script.write(to: source, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: source.path)
        }
        let valid = """
        #!/bin/sh
        test "$1" = hook && test "$2" = --hook-self-check || exit 1
        printf '%s\n' '\(report)'
        """
        try putScript(valid)
        let first = try StudioHookEntryInstaller.prepare(source: source, destination: destination)
        XCTAssertEqual(try StudioHookEntryInstaller.prepare(source: source, destination: destination), first)
        try putScript("#!/bin/sh\nexit 0\n")
        XCTAssertThrowsError(try StudioHookEntryInstaller.prepare(source: source, destination: destination))
        XCTAssertEqual(CodexHookInstallation.EntryIdentity(at: destination), first)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), valid)

        let updated = valid + "\n# new build"
        try putScript(updated)
        let second = try StudioHookEntryInstaller.prepare(source: source, destination: destination)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(CodexHookInstallation.EntryIdentity(at: destination), second)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), updated)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path),
                       ["ahakey-hook"])
        XCTAssertNil(installation.status(configuration: nil))
    }
}
