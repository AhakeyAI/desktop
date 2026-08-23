import XCTest
@testable import AhaKeyConfigShared

final class CursorHookInstallerTests: XCTestCase {
    private let foreignCommand = "/usr/local/bin/foreign-hook"
    private let agentCommand = "/Applications/AhaKey.app/ahakeyconfig-agent"

    func testUpgradeRemovesLegacyPermissionEntriesAndPreservesThirdPartyHooks() throws {
        let settings = try loadFixture("cursor-hooks-v0-nine-events")

        let upgraded = CursorHookInstaller.install(in: settings, agentCommand: agentCommand)
        let hooks = try XCTUnwrap(upgraded["hooks"] as? [String: Any])
        let expected = try loadFixture("cursor-hooks-v1-single-entry")

        XCTAssertEqual(try canonicalJSON(upgraded), try canonicalJSON(expected))
        XCTAssertEqual(managedEntries(in: hooks, event: "preToolUse").count, 1)
        XCTAssertTrue(commands(in: hooks, event: "preToolUse").contains(foreignCommand))
        XCTAssertTrue(commands(in: hooks, event: "beforeShellExecution").contains(foreignCommand))
        XCTAssertTrue(managedEntries(in: hooks, event: "beforeShellExecution").isEmpty)
        XCTAssertTrue(managedEntries(in: hooks, event: "beforeMCPExecution").isEmpty)
        XCTAssertTrue(managedEntries(in: hooks, event: "beforeReadFile").isEmpty)
    }

    func testReinstallIsIdempotent() throws {
        let once = CursorHookInstaller.install(in: ["version": 1, "hooks": [:]], agentCommand: agentCommand)
        let twice = CursorHookInstaller.install(in: once, agentCommand: agentCommand)
        let hooks = try XCTUnwrap(twice["hooks"] as? [String: Any])

        for event in CursorHookInstaller.installedEvents {
            XCTAssertEqual(managedEntries(in: hooks, event: event).count, 1, event)
        }
    }

    func testManagedCommandDetectionDoesNotRemoveLookalikeThirdPartyCommands() {
        XCTAssertFalse(
            CursorHookInstaller.isManagedCommand(
                "/usr/bin/foreign --label=ahakeyconfig-agent-compatible"
            )
        )
        XCTAssertTrue(
            CursorHookInstaller.isManagedCommand(
                #"'/Applications/AhaKey.app/ahakeyconfig-agent' hook preToolUse"#
            )
        )
    }

    func testUninstallRemovesManagedEntriesAcrossAllEventsAndKeepsForeignEntries() throws {
        let installed = CursorHookInstaller.install(
            in: [
                "version": 1,
                "hooks": [
                    "customEvent": [
                        ["command": foreignCommand, "timeout": 10],
                        ["command": "/old/ahakeyconfig-agent hook legacyEvent", "timeout": 20],
                    ],
                ],
            ],
            agentCommand: agentCommand
        )

        let removed = CursorHookInstaller.uninstall(from: installed)
        let hooks = try XCTUnwrap(removed["hooks"] as? [String: Any])

        XCTAssertEqual(commands(in: hooks, event: "customEvent"), [foreignCommand])
        for event in CursorHookInstaller.installedEvents {
            XCTAssertTrue(managedEntries(in: hooks, event: event).isEmpty, event)
        }
    }

    private func entries(in hooks: [String: Any], event: String) -> [[String: Any]] {
        hooks[event] as? [[String: Any]] ?? []
    }

    private func commands(in hooks: [String: Any], event: String) -> [String] {
        entries(in: hooks, event: event).compactMap { $0["command"] as? String }
    }

    private func managedEntries(in hooks: [String: Any], event: String) -> [[String: Any]] {
        entries(in: hooks, event: event).filter {
            CursorHookInstaller.isManagedCommand(($0["command"] as? String) ?? "")
        }
    }

    private func loadFixture(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonicalJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
