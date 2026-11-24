import XCTest
@testable import AhaKeyConfigShared

final class AgentInstallLocationTests: XCTestCase {
    func testTranslocatedAndDiskImagePathsAreEphemeral() {
        XCTAssertTrue(AgentInstallLocation.isEphemeral(
            bundlePath: "/private/var/folders/98/x/T/AppTranslocation/A0DCD54C-DB13/d/AhaKey Studio.app"))
        XCTAssertTrue(AgentInstallLocation.isEphemeral(bundlePath: "/Volumes/AhaKey Studio/AhaKey Studio.app"))
        XCTAssertFalse(AgentInstallLocation.isEphemeral(bundlePath: "/Applications/AhaKey Studio.app"))
        XCTAssertFalse(AgentInstallLocation.isEphemeral(bundlePath: "/Users/me/Applications/AhaKey Studio.app"))
    }

    func testFindsAgentPathsInEscapedJSONAndTOML() {
        let json = #"{"command" : "'\/private\/var\/T\/AppTranslocation\/A0\/d\/AhaKey Studio.app\/Contents\/MacOS\/ahakeyconfig-agent' hook Stop"}"#
        XCTAssertEqual(AgentInstallLocation.referencedAgentPaths(in: json),
                       ["/private/var/T/AppTranslocation/A0/d/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent"])

        let toml = """
        command = "/bin/zsh -lc '\\'/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent\\' hook KimiStop'"
        other = "/usr/bin/true"
        """
        XCTAssertEqual(AgentInstallLocation.referencedAgentPaths(in: toml),
                       ["/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent"])
    }

    func testStaleOnlyWhenAnotherMissingBinaryIsReferenced() {
        let current = "/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent"
        let gone = "/private/var/T/AppTranslocation/A0/d/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent"
        let missing: (String) -> Bool = { _ in false }
        XCTAssertTrue(AgentInstallLocation.hasStaleAgentPath(in: "'\(gone)' hook Stop", currentAgentPath: current, isExecutable: missing))
        XCTAssertFalse(AgentInstallLocation.hasStaleAgentPath(in: "'\(current)' hook Stop", currentAgentPath: current, isExecutable: missing))
        XCTAssertFalse(AgentInstallLocation.hasStaleAgentPath(in: "'\(gone)' hook Stop", currentAgentPath: current, isExecutable: { _ in true }))
        XCTAssertFalse(AgentInstallLocation.hasStaleAgentPath(in: "no hooks here", currentAgentPath: current, isExecutable: missing))
    }

    func testGuardedCommandExitsQuietlyWhenBinaryIsMissing() throws {
        let command = AgentInstallLocation.guardedShellCommand(
            quotedBinary: "'/nonexistent/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent'", arguments: "hook Stop")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testGuardedCommandRunsTheBinaryWhenPresent() throws {
        let command = AgentInstallLocation.guardedShellCommand(quotedBinary: "'/bin/echo'", arguments: "hook Stop")
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(out, "hook Stop\n")
    }
}
