import XCTest
@testable import AhaKeyConfigShared

final class JSONHooksConfigurationTests: XCTestCase {
    func testRemovalPreservesUserCommandsThatOnlyMentionAgent() throws {
        for client in [JSONHooksConfiguration.Client.claude, .cursor] {
            let user = ["echo ahakeyconfig-agent", "'/usr/local/bin/ahakeyconfig-agent-backup' hook Stop", "echo '/tmp/ahakey-state.sh'", "other --label=ahakeyconfig-agent"]
            let commands: [[String: Any]] = user.map { ["type": "command", "command": $0] }
            let entries: [[String: Any]] = client == .claude ? [["matcher": "", "hooks": commands]] : commands
            let original: [String: Any] = ["hooks": ["Stop": entries], "unrelated": "keep"]
            let result = try JSONHooksConfiguration.removing(in: original, client: client)
            XCTAssertTrue(NSDictionary(dictionary: result).isEqual(to: original))
        }
    }
    func testInstallReinstallRemovePreservesUserHooksAndSettings() throws {
        for client in [JSONHooksConfiguration.Client.claude, .cursor] {
            let command: [String: Any] = ["type": "command", "command": "echo user", "timeout": 9]
            let entries: [[String: Any]] = client == .claude ? [["matcher": "Bash", "hooks": [command]]] : [command]
            let original: [String: Any] = ["version": 1, "hooks": ["PreToolUse": entries, "FutureEvent": client == .claude ? [["matcher": "", "hooks": []]] : []], "permissions": ["deny": ["Bash(rm *)"]]]
            let once = try JSONHooksConfiguration.installing(in: original, client: client, agentPath: "/tmp/agent's space/ahakeyconfig-agent")
            let twice = try JSONHooksConfiguration.installing(in: once, client: client, agentPath: "/tmp/agent's space/ahakeyconfig-agent")
            XCTAssertTrue(NSDictionary(dictionary: once).isEqual(to: twice))
            let removed = try JSONHooksConfiguration.removing(in: twice, client: client)
            XCTAssertTrue(NSDictionary(dictionary: removed).isEqual(to: original))
        }
    }
    func testLiteralOwnershipAndLegacyScriptMigration() {
        for command in ["'/tmp/agent\'s space/ahakeyconfig-agent' hook Stop", "/tmp/ahakeyconfig-agent hook Stop | cat", "echo ahakey-state.sh", "/tmp/ahakeyconfig-agent\nhook Stop", "/tmp/ahakeyconfig-agent hook Unknown", "$(which ahakeyconfig-agent) hook Stop"] {
            XCTAssertFalse(JSONHooksConfiguration.owns(command), command)
        }
        for command in ["'/tmp/agent'\\''s space/ahakeyconfig-agent' hook Stop", "/bin/sh -c \"/tmp/ahakeyconfig-agent hook Stop\"", "/usr/bin/env AHAKEY_TEST=1 /tmp/ahakeyconfig-agent hook preToolUse", "~/.claude/hooks/ahakey-state.sh Notification", "/bin/bash /tmp/ahakey-state.sh Stop"] {
            XCTAssertTrue(JSONHooksConfiguration.owns(command), command)
        }
    }
    func testMalformedSettingsAndUnsafePathsAreNotOverwritten() throws {
        for settings: [String: Any] in [["hooks": "broken"], ["hooks": ["Stop": "broken"]], ["hooks": ["Stop": [["hooks": "broken"]]]]] {
            XCTAssertThrowsError(try JSONHooksConfiguration.installing(in: settings, client: .claude, agentPath: "/tmp/ahakeyconfig-agent"))
        }
        XCTAssertThrowsError(try JSONHooksConfiguration.installing(in: [:], client: .cursor, agentPath: "relative"))
    }

}
