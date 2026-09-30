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
