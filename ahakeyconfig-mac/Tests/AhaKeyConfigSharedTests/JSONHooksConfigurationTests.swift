import XCTest
@testable import AhaKeyConfigShared

final class JSONHooksConfigurationTests: XCTestCase {
    func testReceiptFingerprintSurvivesAnotherLaunchersHookAndSettings() throws {
        let entry = CodexHookInstallation().entryURL.path
        for client in [JSONHooksConfiguration.Client.claude, .cursor] {
            let original = try JSONHooksConfiguration.installing(in: [:], client: client, agentPath: entry)
            let originalData = try JSONSerialization.data(withJSONObject: original)
            let evidence = try XCTUnwrap(JSONHooksConfiguration.managedHookData(in: originalData, client: client))
            var modified = original
            var hooks = try XCTUnwrap(original["hooks"] as? [String: [[String: Any]]])
            let name = client == .claude ? "SessionStart" : "sessionStart"
            let command = ["type": "command", "command": "/bin/echo host"]
            let foreign: [String: Any] = client == .claude ? ["matcher": "", "hooks": [command]] : command
            hooks[name, default: []].insert(foreign, at: 0)
            modified["hooks"] = hooks
            modified["otherLauncherSettings"] = true
            XCTAssertEqual(JSONHooksConfiguration.managedHookData(
                in: try JSONSerialization.data(withJSONObject: modified), client: client), evidence)

            hooks[name] = [foreign]
            modified["hooks"] = hooks
            XCTAssertNotEqual(JSONHooksConfiguration.managedHookData(
                in: try JSONSerialization.data(withJSONObject: modified), client: client), evidence)
        }
    }

    func testWorkBuddyInstallsOnlyTaskHooksAndPreservesOtherCommands() throws {
        let original: [String: Any] = [
            "hooks": ["UserPromptSubmit": [["hooks": [["type": "command", "command": "echo user"]]]]],
            "permissions": ["defaultMode": "default"]
        ]
        let fixed = CodexHookInstallation().entryURL.path
        let installed = try JSONHooksConfiguration.installing(in: original, client: .workBuddy, agentPath: fixed)
        let reinstalled = try JSONHooksConfiguration.installing(in: installed, client: .workBuddy, agentPath: fixed)
        XCTAssertTrue(NSDictionary(dictionary: installed).isEqual(to: reinstalled))
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["UserPromptSubmit", "Stop", "SessionEnd"])
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(
            to: try JSONHooksConfiguration.removing(in: reinstalled, client: .workBuddy)
        ))
    }

    func testFixedEntryCanBeReinstalledAndRemoved() throws {
        let fixed = CodexHookInstallation().entryURL.path
        for client in [JSONHooksConfiguration.Client.claude, .cursor] {
            let original: [String: Any] = client == .cursor ? ["unrelated": true, "version": 1] : ["unrelated": true]
            let old = try JSONHooksConfiguration.installing(in: original, client: client,
                agentPath: "/tmp/preview/ahakeyconfig-agent")
            let once = try JSONHooksConfiguration.installing(in: old, client: client, agentPath: fixed)
            let twice = try JSONHooksConfiguration.installing(in: once, client: client, agentPath: fixed)
            XCTAssertTrue(NSDictionary(dictionary: once).isEqual(to: twice))
            XCTAssertFalse(String(describing: once).contains("/tmp/preview"))
            let removed = try JSONHooksConfiguration.removing(in: twice, client: client)
            XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: removed))
        }
        XCTAssertFalse(JSONHooksConfiguration.owns("/usr/local/bin/ahakey-hook hook Stop"))
    }

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
