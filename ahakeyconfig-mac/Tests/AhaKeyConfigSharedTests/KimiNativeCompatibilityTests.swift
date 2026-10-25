import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class KimiNativeCompatibilityTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testDiscoveryHonorsRelocationManagedLegacyAndActualNativeExecutable() throws {
        let home = try directory(), custom = home.appendingPathComponent("custom home")
        let explicit = KimiConfigPolicySync.location(home: home, environment: ["KIMI_CODE_HOME": custom.path], executables: [])
        XCTAssertEqual(explicit.layout, .nativeV2)
        XCTAssertEqual(explicit.configURL, custom.appendingPathComponent("config.toml"))
        let legacy = KimiConfigPolicySync.location(home: home,
            environment: ["KIMI_CODE_HOME": custom.path, "AHAKEY_KIMI_LAYOUT": "legacy"], executables: [])
        XCTAssertEqual(legacy.configURL, home.appendingPathComponent(".kimi/config.toml"))
        let executable = home.appendingPathComponent("kimi")
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        XCTAssertEqual(KimiConfigPolicySync.location(home: home, environment: [:], executables: [executable]).layout, .nativeV2)
        try Data("#!/usr/bin/python3\n".utf8).write(to: executable)
        XCTAssertEqual(KimiConfigPolicySync.location(home: home, environment: [:], executables: [executable]).layout, .legacyPython)
    }
    func testNativeOwnershipRevokesOnlyOurYoloAndPreservesUserNeverAskChange() throws {
        let root = try directory(), config = root.appendingPathComponent("config.toml"), control = root.appendingPathComponent("control")
        try "default_permission_mode = 'manual' # keep\r\n[other]\nvalue = 9\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control, layout: .nativeV2), .updated)
        XCTAssertEqual(KimiConfigPolicySync.releaseOwnedAutomation(configURL: config), .updated)
        XCTAssertTrue(try String(contentsOf: config).contains("default_permission_mode = \"manual\" # keep\r\n"))
        _ = KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control, layout: .nativeV2)
        try "default_permission_mode = \"auto\"\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiConfigPolicySync.releaseOwnedAutomation(configURL: config), .notOwned)
        XCTAssertEqual(try String(contentsOf: config), "default_permission_mode = \"auto\"\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: KimiConfigPolicySync.leaseURL(config).path))
    }
    func testNativeInvalidOrDuplicateModeDoesNotWriteOrAcquireLease() throws {
        let root = try directory(), config = root.appendingPathComponent("config.toml")
        for input in ["default_permission_mode = true\n", "default_permission_mode = \"other\"\n",
            "default_permission_mode = \"manual\"\ndefault_permission_mode = \"yolo\"\n", "[default_permission_mode]\nvalue = 1\n"] {
            try input.write(to: config, atomically: true, encoding: .utf8)
            XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config,
                controlDirectory: root.appendingPathComponent("control"), layout: .nativeV2), .invalid)
            XCTAssertEqual(try String(contentsOf: config), input)
            XCTAssertFalse(FileManager.default.fileExists(atPath: KimiConfigPolicySync.leaseURL(config).path))
        }
    }
    func testNativeNestedModesAndMultilinePromptAreNotRootPermission() throws {
        let root = try directory(), config = root.appendingPathComponent("config.toml")
        let input = "prompt = '''\ndefault_permission_mode = \"auto\"\n'''\n[other]\ndefault_permission_mode = \"auto\"\n"
        try input.write(to: config, atomically: true, encoding: .utf8)
        _ = KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: root.appendingPathComponent("control"), layout: .nativeV2)
        XCTAssertEqual(try String(contentsOf: config), input.replacingOccurrences(of: "[other]", with: "default_permission_mode = \"yolo\"\n[other]"))
    }
    func testHookReinstallRemovalPreserveFollowingProvidersAndUserHook() throws {
        let root = try directory(), location = KimiConfigPolicySync.location(home: root, environment: ["KIMI_CODE_HOME": root.path], executables: [])
        let input = "[[hooks]]\nevent = \"Stop\"\ncommand = \"/tmp/ahakeyconfig-agent hook KimiStop\"\n[providers.user]\napi_key = \"fixture-only\"\n[[hooks]]\nevent = \"Stop\"\ncommand = \"echo user\"\n"
        let first = try KimiHooksConfiguration.installing(in: input, location: location, agentPath: "/tmp/test agent's/ahakeyconfig-agent")
        XCTAssertTrue(first.contains("[providers.user]\napi_key = \"fixture-only\""))
        XCTAssertTrue(first.contains("command = \"echo user\""))
        XCTAssertTrue(first.contains("event = \"PermissionRequest\""))
        XCTAssertTrue(first.contains("event = \"PermissionResult\""))
        XCTAssertTrue(first.contains("AHAKEY_KIMI_APPROVAL_OBSERVATIONS=1"))
        XCTAssertEqual(try KimiHooksConfiguration.installing(in: first, location: location,
            agentPath: "/tmp/test agent's/ahakeyconfig-agent"), first)
        let removed = try KimiHooksConfiguration.removing(in: first)
        XCTAssertFalse(removed.contains("hook Kimi")); XCTAssertTrue(removed.contains("api_key = \"fixture-only\""))
        XCTAssertTrue(removed.contains("command = \"echo user\""))
    }
    func testMarkersInsideMultilinePromptDoNotGrantRemovalOwnership() throws {
        let input = "prompt = '''\n# BEGIN AhaKey Kimi Hooks\n[[hooks]]\ncommand = \"ahakeyconfig-agent hook KimiStop\"\n# END AhaKey Kimi Hooks\n'''\n"
        XCTAssertEqual(try KimiHooksConfiguration.removing(in: input), input)
        XCTAssertThrowsError(try KimiHooksConfiguration.removing(in: "# BEGIN AhaKey Kimi Hooks\n"))
    }
    func testLegacyInstallDoesNotGainUnsupportedNativeObservationEvents() throws {
        let root = try directory()
        let location = KimiConfigPolicySync.Location(layout: .legacyPython, root: root)
        let text = try KimiHooksConfiguration.installing(in: "", location: location, agentPath: "/tmp/ahakeyconfig-agent")
        XCTAssertFalse(text.contains("event = \"PermissionRequest\""))
        XCTAssertFalse(text.contains("event = \"PermissionResult\""))
        XCTAssertFalse(text.contains("AHAKEY_KIMI_APPROVAL_OBSERVATIONS"))
        XCTAssertEqual(text.components(separatedBy: "[[hooks]]").count - 1, 7)
    }
    func testMentionsPipelinesAndOtherProgramsDoNotGrantHookRemovalOwnership() throws {
        for command in ["echo 'ahakeyconfig-agent hook KimiStop'", "/tmp/other-agent hook KimiStop",
            "/bin/sh -c 'echo user; /tmp/ahakeyconfig-agent hook KimiStop'"] {
            let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let input = "[[hooks]]\nevent = \"Stop\"\ncommand = \"\(quoted)\"\n"
            XCTAssertEqual(try KimiHooksConfiguration.removing(in: input), input)
        }
    }
    func testRevocationFindsOwnedRelocatedConfigEvenWhenGUISelectsAnotherHome() throws {
        let root = try directory(), config = root.appendingPathComponent("relocated.toml"), control = root.appendingPathComponent("control")
        try "default_permission_mode = \"manual\"\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control, layout: .nativeV2), .updated)
        XCTAssertTrue(ApprovalAutomationControl.revoke(.kimi, directory: control,
            codexURL: root.appendingPathComponent("unused-codex.toml"), kimiURL: root.appendingPathComponent("different-home.toml"),
            cursorDirectory: root.appendingPathComponent("cursor")))
        XCTAssertEqual(try String(contentsOf: config), "default_permission_mode = \"manual\"\n")
        XCTAssertEqual(KimiConfigPolicySync.ownedConfigURLs(directory: control), [])
    }
    func testCorruptOwnershipRegistryPreventsNewAutomaticGrant() throws {
        let root = try directory(), config = root.appendingPathComponent("config.toml"), control = root.appendingPathComponent("control")
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        try "not JSON".write(to: control.appendingPathComponent("kimi-owned-configs.json"), atomically: true, encoding: .utf8)
        let input = "default_permission_mode = \"manual\"\n"
        try input.write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control, layout: .nativeV2), .writeFailed)
        XCTAssertEqual(try String(contentsOf: config), input)
    }
    func testNativeHookCannotCreateUnrevocableAutomaticSessionsOrRewriteUserDefaults() throws {
        let root = try directory(), location = KimiConfigPolicySync.location(home: root,
            environment: ["KIMI_CODE_HOME": root.path], executables: [])
        let input = "default_permission_mode = \"manual\"\n"
        try input.write(to: location.configURL, atomically: true, encoding: .utf8)
        for auto in [true, false] {
            XCTAssertEqual(KimiConfigPolicySync.apply(auto: auto, location: location,
                controlDirectory: root.appendingPathComponent("control")), .unsupportedRuntime)
            XCTAssertEqual(try String(contentsOf: location.configURL), input)
        }
    }
    func testUnchangedLegacyHookDoesNotRewriteOwnershipFileOrClaimUserAuto() throws {
        let root = try directory(), config = root.appendingPathComponent("config.toml"), control = root.appendingPathComponent("control")
        try "default_yolo = false\n".write(to: config, atomically: true, encoding: .utf8)
        _ = KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control)
        let file = control.appendingPathComponent("kimi-owned-configs.json")
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber
        for _ in 0..<5 { XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control), .unchanged) }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber, before)
        _ = KimiConfigPolicySync.releaseOwnedAutomation(configURL: config)
        _ = KimiConfigPolicySync.record(config, owned: false, directory: control)
        try "default_yolo = true\n".write(to: config, atomically: true, encoding: .utf8)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: true, configURL: config, controlDirectory: control), .unchanged)
        XCTAssertEqual(KimiConfigPolicySync.ownedConfigURLs(directory: control), [])
    }
    func testMalformedUnownedConfigDoesNotPreventRevokingOurOtherConfig() throws {
        let root = try directory(), owned = root.appendingPathComponent("owned.toml"), other = root.appendingPathComponent("unowned.toml")
        let control = root.appendingPathComponent("control")
        try "default_yolo = false\n".write(to: owned, atomically: true, encoding: .utf8)
        let malformed = "prompt = '''unclosed"
        try malformed.write(to: other, atomically: true, encoding: .utf8)
        _ = KimiConfigPolicySync.apply(auto: true, configURL: owned, controlDirectory: control)
        XCTAssertTrue(ApprovalAutomationControl.revoke(.kimi, directory: control,
            codexURL: root.appendingPathComponent("codex"), kimiURL: other, cursorDirectory: root.appendingPathComponent("cursor")))
        XCTAssertEqual(try String(contentsOf: owned), "default_yolo = false\n")
        XCTAssertEqual(try String(contentsOf: other), malformed)
    }
    func testNativeManualModeMustReplaceEffectiveFieldRatherThanIgnoredLegacyBoolean() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml")
        try Data("default_permission_mode = \"auto\"\n[providers.test]\napi_key = \"fixture-only\"\n".utf8).write(to: config)
        XCTAssertEqual(KimiConfigPolicySync.apply(auto: false, configURL: config,
            controlDirectory: root.appendingPathComponent("control"), layout: .nativeV2), .updated)
        let actual = try String(contentsOf: config)
        XCTAssertTrue(actual.contains("default_permission_mode = \"manual\""))
        XCTAssertFalse(actual.contains("default_yolo"))
        XCTAssertTrue(actual.contains("api_key = \"fixture-only\""))
    }
}
