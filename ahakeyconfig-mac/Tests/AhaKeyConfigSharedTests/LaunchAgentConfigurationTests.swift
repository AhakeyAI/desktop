import XCTest
@testable import AhaKeyConfigShared

final class LaunchAgentConfigurationTests: XCTestCase {
    func testCapturedSystemDisabledOverrideMatchesOnlyOurExactLabel() {
        let output = #"""
            disabled services = {
                "lab.jawa.ahakeyconfig.agent.hil" => enabled
                "lab.jawa.ahakeyconfig.agent" => disabled
                "other.background.service" => disabled
            }
            """#
        XCTAssertEqual(LaunchAgentConfiguration.systemDisabledOverride(in: output,
            commandSucceeded: true, label: "lab.jawa.ahakeyconfig.agent"), true)
        XCTAssertEqual(LaunchAgentConfiguration.systemDisabledOverride(in: output,
            commandSucceeded: true, label: "lab.jawa.ahakeyconfig.agent.hil"), false)
        XCTAssertNil(LaunchAgentConfiguration.systemDisabledOverride(in: output,
            commandSucceeded: true, label: "lab.jawa.ahakeyconfig"))
        XCTAssertNil(LaunchAgentConfiguration.systemDisabledOverride(in: output,
            commandSucceeded: false, label: "lab.jawa.ahakeyconfig.agent"))
    }

    func testMissingMalformedAndConflictingOverrideRowsAreUnknown() {
        for output in ["", "not available", #""lab.jawa.ahakeyconfig.agent" => not-disabled"#,
                       "\"lab.jawa.ahakeyconfig.agent\" => enabled\n\"lab.jawa.ahakeyconfig.agent\" => disabled"] {
            XCTAssertNil(LaunchAgentConfiguration.systemDisabledOverride(in: output,
                commandSucceeded: true, label: "lab.jawa.ahakeyconfig.agent"))
        }
        XCTAssertEqual(LaunchAgentConfiguration.systemDisabledOverride(
            in: #""lab.jawa.ahakeyconfig.agent" => true"#,
            commandSucceeded: true, label: "lab.jawa.ahakeyconfig.agent"), true)
        XCTAssertEqual(LaunchAgentConfiguration.systemDisabledOverride(
            in: #""lab.jawa.ahakeyconfig.agent" => false,"#,
            commandSucceeded: true, label: "lab.jawa.ahakeyconfig.agent"), false)
    }

    func testSameBinaryWithOldSocketMustBeMigratedBeforeStarting() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let binary = "/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent"
        let expected = [binary, "--socket", "/tmp/ahakey.sock"]
        let previous = [binary, "--socket", "/Users/test/Library/Application Support/AhaKeyConfig/ahakey.sock"]
        let data = try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": previous], format: .xml, options: 0)
        try data.write(to: url)
        XCTAssertTrue(LaunchAgentConfiguration.needsRewrite(plistURL: url, expectedArguments: expected))
        let migrated = try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": expected], format: .xml, options: 0)
        try migrated.write(to: url)
        XCTAssertFalse(LaunchAgentConfiguration.needsRewrite(plistURL: url, expectedArguments: expected))
    }

    func testUnreadableOrMalformedLaunchContractRequiresRewrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(LaunchAgentConfiguration.needsRewrite(plistURL: url, expectedArguments: ["agent"]))
        try Data("invalid plist".utf8).write(to: url)
        XCTAssertTrue(LaunchAgentConfiguration.needsRewrite(plistURL: url, expectedArguments: ["agent"]))
        try PropertyListSerialization.data(fromPropertyList: ["RunAtLoad": true], format: .xml, options: 0).write(to: url)
        XCTAssertTrue(LaunchAgentConfiguration.needsRewrite(plistURL: url, expectedArguments: ["agent"]))
    }
}
