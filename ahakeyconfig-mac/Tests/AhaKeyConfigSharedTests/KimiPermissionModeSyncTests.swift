import XCTest
@testable import AhaKeyConfigShared

/// AHK-049：拨杆必须写到 Kimi Code CLI 实际读取的 `~/.kimi-code/config.toml` 的
/// `default_permission_mode`，而不是旧版 kimi-cli 的 `~/.kimi/config.toml` `default_yolo`。
/// 全部在临时目录 fixture 上运行，不触碰用户真实 home。
final class KimiPermissionModeSyncTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahk049-kimi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func writeFixture(_ text: String, permissions: Int = 0o600) throws -> URL {
        let url = root.appendingPathComponent("config.toml")
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        return url
    }

    private func text(of url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    // MARK: - 配置位置

    func testActiveConfigPrefersKimiCodeOverMigratedLegacyConfig() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".kimi"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".kimi/config.toml"))
        XCTAssertTrue(KimiConfigLocation.isLegacy(KimiConfigLocation.activeConfigURL(environment: [:], home: root), home: root))

        try fm.createDirectory(at: root.appendingPathComponent(".kimi-code"), withIntermediateDirectories: true)
        XCTAssertEqual(
            KimiConfigLocation.activeConfigURL(environment: [:], home: root).path,
            root.appendingPathComponent(".kimi-code/config.toml").path
        )
    }

    func testActiveConfigDefaultsToKimiCodeAndHonorsKimiCodeHome() throws {
        XCTAssertEqual(
            KimiConfigLocation.activeConfigURL(environment: [:], home: root).path,
            root.appendingPathComponent(".kimi-code/config.toml").path
        )
        let custom = root.appendingPathComponent("custom-home")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        XCTAssertEqual(
            KimiConfigLocation.activeConfigURL(environment: ["KIMI_CODE_HOME": custom.path], home: root).path,
            custom.appendingPathComponent("config.toml").path
        )
    }

    func testExplicitUninitializedHomeDoesNotFallBackToLegacyConfig() throws {
        let legacyDirectory = root.appendingPathComponent(".kimi")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try Data("default_yolo = true".utf8).write(to: legacyDirectory.appendingPathComponent("config.toml"))
        let custom = root.appendingPathComponent("not-created-yet")
        XCTAssertEqual(
            KimiConfigLocation.activeConfigURL(environment: ["KIMI_CODE_HOME": custom.path], home: root),
            custom.appendingPathComponent("config.toml")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
    }

    // MARK: - default_permission_mode 同步

    func testDialTogglesExistingModeAndPreservesOtherBytes() throws {
        let original = "default_plan_mode = false\ndefault_permission_mode = \"manual\" # keep\n\n[[hooks]]\nevent = \"PreToolUse\"\n"
        let url = try writeFixture(original)

        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: true, configURL: url), .replaced)
        XCTAssertEqual(try text(of: url), original.replacingOccurrences(of: "\"manual\"", with: "\"auto\""))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: url), "auto")

        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: false, configURL: url), .replaced)
        XCTAssertEqual(try text(of: url), original)
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: false, configURL: url), .alreadyDesired)
    }

    func testMissingKeyIsInsertedBeforeFirstTable() throws {
        let url = try writeFixture("telemetry = true\n\n[[hooks]]\nevent = \"Stop\"\n")
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: true, configURL: url), .inserted)
        XCTAssertEqual(try text(of: url), "telemetry = true\n\ndefault_permission_mode = \"auto\"\n[[hooks]]\nevent = \"Stop\"\n")
    }

    func testUserChosenAutoModeSatisfiesAutoDial() throws {
        let original = "default_permission_mode = \"auto\"\n"
        let url = try writeFixture(original)
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: true, configURL: url), .alreadyDesired)
        XCTAssertEqual(try text(of: url), original)
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: false, configURL: url), .replaced)
        XCTAssertEqual(try text(of: url), "default_permission_mode = \"manual\"\n")
    }

    func testWritePreservesCredentialFilePermissions() throws {
        let url = try writeFixture("default_permission_mode = \"manual\"\n", permissions: 0o600)
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: true, configURL: url), .replaced)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testMissingOrAmbiguousConfigIsNeverWritten() throws {
        XCTAssertEqual(
            KimiPermissionModeSync.apply(switchStateAuto: true, configURL: root.appendingPathComponent("absent.toml")),
            .missingConfig
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("absent.toml").path))

        let duplicate = "default_permission_mode = \"manual\"\ndefault_permission_mode = \"auto\"\n"
        let url = try writeFixture(duplicate)
        XCTAssertEqual(KimiPermissionModeSync.apply(switchStateAuto: true, configURL: url), .duplicateKey)
        XCTAssertEqual(try text(of: url), duplicate)
    }

    // MARK: - 迁移来的裸 hooks

    func testRemovingMigratedHooksKeepsFollowingTables() {
        let agent = "/bin/zsh -lc ''\\''/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent'\\'' hook"
        let migrated = """
        default_permission_mode = "manual"

        [[hooks]]
        event = "PreToolUse"
        matcher = ""
        command = "\(agent) KimiPreToolUse'"
        timeout = 20

        [[hooks]]
        event = "Stop"
        matcher = "user-hook"
        command = "/usr/local/bin/notify"
        timeout = 10

        [[hooks]]
        event = "Stop"
        matcher = ""
        command = "\(agent) KimiStop'"
        timeout = 10

        [thinking]
        enabled = true

        [providers."managed:kimi-code"]
        type = "kimi"

        [models."kimi-code/k3"]
        provider = "managed:kimi-code"

        """
        let cleaned = KimiHookConfigText.removingBareAhaKeyHooks(
            from: migrated, blockMarkers: ["# BEGIN AhaKey Kimi Hooks", "# END AhaKey Kimi Hooks"]
        )
        XCTAssertFalse(cleaned.contains("ahakeyconfig-agent"))
        XCTAssertTrue(cleaned.contains("command = \"/usr/local/bin/notify\""))
        XCTAssertTrue(cleaned.contains("[thinking]\nenabled = true"))
        XCTAssertTrue(cleaned.contains("[providers.\"managed:kimi-code\"]\ntype = \"kimi\""))
        XCTAssertTrue(cleaned.contains("[models.\"kimi-code/k3\"]\nprovider = \"managed:kimi-code\""))
    }
}
