import XCTest
@testable import AhaKeyConfigShared

final class CodexHookInstallationTests: XCTestCase {
    private let path = "/tmp/config.toml"
    private var block: String {
        """
        \(CodexHookTrust.blockStart)
        [[hooks.SessionStart]]
        matcher = ""
        [[hooks.SessionStart.hooks]]
        type = "command"
        command = "true"
        timeout = 10
        \(CodexHookTrust.blockEnd)
        """
    }
    private var user: String {
        """
        [[hooks.SessionStart]]
        [[hooks.SessionStart.hooks]]
        type = "command"
        command = "echo user"
        [hooks.state."/tmp/config.toml:session_start:0:0"]
        enabled = false
        trusted_hash = "sha256:user"
        """
    }
    private func install(_ config: String) throws -> String {
        try CodexHookTrust.install(in: config, configPath: path, block: block,
            hashes: [("SessionStart", CodexHookTrust.trustedHash(event: "SessionStart", matcher: "", command: "true", timeout: 10)!)])
    }

    func testMigrationChangesManagedTrustButKeepsTheUsersEntries() throws {
        let old = try CodexHookTrust.installAgentHooks(in: user, configPath: path,
            agentBinaryPath: "/private/tmp/preview/ahakeyconfig-agent")
        let fixed = CodexHookInstallation().entryURL.path
        let next = try CodexHookTrust.installAgentHooks(in: old, configPath: path, agentBinaryPath: fixed)
        XCTAssertTrue(next.contains(user))
        XCTAssertTrue(next.contains(fixed))
        XCTAssertFalse(next.contains("/private/tmp/preview"))
        let fingerprint = try XCTUnwrap(CodexHookTrust.managedFingerprint(in: next, configPath: path))
        XCTAssertNotEqual(try CodexHookTrust.managedFingerprint(in: old, configPath: path), fingerprint)
        let withUserSettings = next + "\n[tui]\nnotifications = true\n"
        XCTAssertEqual(try CodexHookTrust.managedFingerprint(in: withUserSettings, configPath: path), fingerprint)
        let changed = next + "enabled = false\n"
        XCTAssertNotEqual(try CodexHookTrust.managedFingerprint(in: changed, configPath: path), fingerprint)
    }

    func testFeatureUpdateUsesActualTableAndPreservesUserSettings() throws {
        let original = "notes = '''\n[features]\nhooks = false\n'''\n[features] # keep\nplugins = false\ncodex_hooks = false\nhooks = false # comment\n[tui]\nnotifications = true\n"
        let next = try CodexHookTrust.enablingHooksFeature(in: original)
        XCTAssertTrue(next.contains("notes = '''\n[features]\nhooks = false\n'''"))
        XCTAssertTrue(next.contains("[features] # keep\nplugins = false"))
        XCTAssertTrue(next.contains("hooks = true # comment\n[tui]\nnotifications = true"))
        XCTAssertFalse(next.contains("codex_hooks"))
        XCTAssertEqual(try CodexHookTrust.enablingHooksFeature(in: next), next)
        XCTAssertEqual(try CodexHookTrust.enablingHooksFeature(in: "features.plugins = false\n[tui]\n"),
                       "features.plugins = false\nfeatures.hooks = true\n[tui]\n")
    }

    func testOnlyTheFixedEntryCanConfirmTheCurrentInstallation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let installation = CodexHookInstallation(directory: directory)
        try FileManager.default.createDirectory(at: installation.entryURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: installation.entryURL)
        let entry = try XCTUnwrap(CodexHookInstallation.EntryIdentity(at: installation.entryURL))
        XCTAssertNil(installation.status(configuration: "configuration-1"))
        try installation.confirm(configuration: "configuration-1", entry: entry, migrated: true)
        let payload = ["hook_event_name": "SessionStart", "session_id_short": "test-session"]
        let current = installation.eventRecorder(executablePath: installation.entryURL.path, host: .orca)
        let legacy = installation.eventRecorder(executablePath: "/tmp/preview/ahakeyconfig-agent")
        legacy("SessionStart", payload)
        current("Stop", payload)
        current("SessionStart", ["hook_event_name": "SessionStart"])
        XCTAssertEqual(installation.status(configuration: "configuration-1")?.entryChecked, true)
        XCTAssertEqual(installation.status(configuration: "configuration-1")?.eventReceived, false)
        current("SessionStart", payload)
        XCTAssertEqual(installation.status(configuration: "configuration-1")?.eventReceived, true)
        installation.eventRecorder(executablePath: installation.entryURL.path, host: .codexDesktop)("SessionStart", payload)
        XCTAssertEqual(installation.status(configuration: "configuration-1")?.hosts, [.orca, .codexDesktop])
        XCTAssertEqual(installation.status(configuration: "different")?.configurationWritten, false)
        try installation.confirm(configuration: "configuration-1", entry: entry, migrated: false)
        XCTAssertEqual(installation.status(configuration: "configuration-1")?.eventReceived, true)
        try installation.confirm(configuration: "configuration-2", entry: entry, migrated: true)
        current("SessionStart", payload)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.eventReceived, false)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.hosts, [])
        installation.eventRecorder(executablePath: installation.entryURL.path)("SessionStart", payload)
        let replacement = directory.appendingPathComponent("replacement")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: replacement)
        _ = try FileManager.default.replaceItemAt(installation.entryURL, withItemAt: replacement)
        let updatedEntry = try XCTUnwrap(CodexHookInstallation.EntryIdentity(at: installation.entryURL))
        try installation.confirmEntryUpgrade(updatedEntry)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.configurationWritten, true)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.entryChecked, true)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.eventReceived, false)
        try FileManager.default.removeItem(at: installation.entryURL)
        XCTAssertEqual(installation.status(configuration: "configuration-2")?.entryChecked, false)
        installation.clear()
        XCTAssertNil(installation.status(configuration: "configuration-2"))
    }

    func testInstallReinstallAndUninstallPreserveExistingUserHooksAndTrust() throws {
        let once = try install(user)
        XCTAssertTrue(once.contains(user))
        XCTAssertTrue(once.contains("[hooks.state.\"/tmp/config.toml:session_start:1:0\"]"))
        let twice = try install(once)
        XCTAssertTrue(twice.contains(user))
        XCTAssertEqual(twice.components(separatedBy: "[[hooks.SessionStart]]").count - 1, 2)
        XCTAssertEqual(twice.components(separatedBy: "session_start:1:0").count - 1, 1)
        let removed = try CodexHookTrust.removingManagedHooks(in: twice, configPath: path)
        XCTAssertTrue(removed.contains(user))
        XCTAssertFalse(removed.contains("session_start:1:0"))
        XCTAssertFalse(removed.contains(CodexHookTrust.blockStart))
        XCTAssertEqual(try CodexHookTrust.removingManagedHooks(in: removed, configPath: path), removed)
    }

    func testUserGroupsAfterManagedBlockKeepTrustWhenIndicesShift() throws {
        let installed = try install("")
        let laterUser = user.replacingOccurrences(of: "session_start:0:0", with: "session_start:1:0")
        let config = installed + "\n" + laterUser
        let removed = try CodexHookTrust.removingManagedHooks(in: config, configPath: path)
        XCTAssertTrue(removed.contains(user))
        XCTAssertFalse(removed.contains("session_start:1:0"))
        let reinstalled = try install(config)
        XCTAssertTrue(reinstalled.contains(user))
        XCTAssertTrue(reinstalled.contains("session_start:1:0"))
    }

    // AHK-047: Codex appends new tables before the trailing END comment, so they land inside our markers.
    func testReinstallKeepsForeignContentWrittenInsideManagedBlock() throws {
        let foreign = """
        [tui]
        notifications = true

        [projects."/Users/x/repo"]
        trust_level = "trusted"

        [hooks.state."/proj/.codex/hooks.json:pre_tool_use:0:0"]
        trusted_hash = "sha256:project"
        """
        let installed = try install(user)
        let config = installed.replacingOccurrences(of: CodexHookTrust.blockEnd, with: foreign + "\n" + CodexHookTrust.blockEnd)
        let reinstalled = try install(config)
        XCTAssertTrue(reinstalled.contains(user))
        XCTAssertTrue(reinstalled.contains(foreign))
        XCTAssertEqual(reinstalled.components(separatedBy: "[[hooks.SessionStart]]").count - 1, 2)
        XCTAssertEqual(reinstalled.components(separatedBy: CodexHookTrust.blockStart).count - 1, 1)
        XCTAssertEqual(reinstalled.components(separatedBy: "session_start:1:0").count - 1, 1)
        XCTAssertEqual(try install(reinstalled), reinstalled)
        let removed = try CodexHookTrust.removingManagedHooks(in: config, configPath: path)
        XCTAssertTrue(removed.contains(user))
        XCTAssertTrue(removed.contains(foreign))
        XCTAssertFalse(removed.contains("session_start:1:0"))
        XCTAssertFalse(removed.contains(CodexHookTrust.blockStart))
        XCTAssertFalse(removed.contains("command = \"true\""))
    }

    func testHeadersAndMarkersInMultilineStringsAreNotHooks() throws {
        let config = "description = '''\n[[hooks.SessionStart]]\n" + block + "\n'''\n" + user
        let result = try install(config)
        XCTAssertTrue(result.contains(config))
        XCTAssertTrue(result.contains("session_start:1:0"))
        XCTAssertFalse(result.contains("session_start:2:0"))
    }

    func testQuotedTablePathsAndGranularPolicyAreSupported() throws {
        let config = "approval_policy = { granular = { sandbox_approval = true } }\n" +
            user.replacingOccurrences(of: "[[hooks.SessionStart]]", with: "[[ 'hooks' . \"SessionStart\" ]] # user group")
        let result = try install(config)
        XCTAssertTrue(result.contains(config))
        XCTAssertTrue(result.contains("session_start:1:0"))
    }

    func testUnmatchedMarkerOrInlineHookLayoutFailsBeforeWriting() {
        for config in [CodexHookTrust.blockStart, CodexHookTrust.blockEnd,
                       "hooks = { SessionStart = [] }", "[hooks]\nSessionStart = []"] {
            XCTAssertThrowsError(try install(config))
        }
    }

    func testConfigPathsAreEscapedAsTomlStrings() throws {
        let unusualPath = "/tmp/a\"b\\c/config.toml"
        let result = try CodexHookTrust.install(in: "", configPath: unusualPath, block: block,
            hashes: [("SessionStart", "sha256:test")])
        let statements = try TomlPolicyLocator.statements(in: result)
        XCTAssertTrue(statements.contains { statement in
            if case let .table(path, _) = statement.kind {
                return path == ["hooks", "state", unusualPath + ":session_start:0:0"]
            }
            return false
        })
    }
}
