import XCTest

final class AhaKeyU1UserFacingCopyTests: XCTestCase {
    func testForbiddenLegacyPhrasesAreAbsentOutsideExactDiagnostics() throws {
        let output = try runCopyGate()
        XCTAssertEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("U1 user-facing copy gate ok"), output.text)
    }

    func testDirectTextControllerMutationFailsFullRootScan() throws {
        let output = try runCopyGate(mutation: "view-text-controller")
        XCTAssertEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("view-text-controller"), output.text)
        XCTAssertTrue(output.text.contains("控制方"), output.text)
    }

    func testCatalogStudioTakeoverMutationFailsFullRootScan() throws {
        let output = try runCopyGate(mutation: "catalog-studio-takeover")
        XCTAssertEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("catalog-studio-takeover"), output.text)
        XCTAssertTrue(
            output.text.contains("接管蓝牙") || output.text.contains("taken over by AhaKey Studio"),
            output.text
        )
    }

    func testAgentSourceMutationFailsFullRootScan() throws {
        let output = try runCopyGate(mutation: "agent-status")
        XCTAssertEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("agent-status"), output.text)
        XCTAssertTrue(
            output.text.contains("AhaKeyAgent.swift") || output.text.contains("接管蓝牙"),
            output.text
        )
    }

    func testCompatibilityMarkerDoesNotBlanketAllowOwnerCopy() throws {
        let snippet = """
        NSLocalizedString("兼容标识：控制方仍显示 Agent", comment: "")
        """
        let output = try runCopyGate(snippet: snippet)
        XCTAssertNotEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(
            output.text.contains("控制方") || output.text.contains("Agent"),
            output.text
        )
    }

    func testExactCompatibilityDiagnosticStillPasses() throws {
        let snippet = """
        NSLocalizedString("请确认 AhaKey Runtime 在跑并已连上键盘。（兼容标识：LaunchAgent / ahakeyconfig-agent）\\n", comment: "")
        """
        let output = try runCopyGate(snippet: snippet)
        XCTAssertEqual(output.exitCode, 0, output.text)
    }

    func testCursorProductAgentNameIsNotTreatedAsRuntimeIdentity() throws {
        let snippet = """
        NSLocalizedString("针对 Cursor Composer / Agent：Key2 发 ↵、Key3 发 ⌫（与裸键一致）。", comment: "")
        """
        let output = try runCopyGate(snippet: snippet)
        XCTAssertEqual(output.exitCode, 0, output.text)
    }

    func testLocalizationCatalogsLint() throws {
        let root = packageRoot()
        for rel in ["Resources/zh-Hans.lproj/Localizable.strings", "Resources/en.lproj/Localizable.strings"] {
            let url = root.appendingPathComponent(rel)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = ["-lint", url.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTAssertEqual(process.terminationStatus, 0, "\(rel): \(output)")
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runCopyGate(snippet: String? = nil, mutation: String? = nil) throws -> (exitCode: Int32, text: String) {
        let script = packageRoot().appendingPathComponent("scripts/check-u1-user-facing-copy.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        if let mutation {
            process.arguments = [script.path, "--mutation", mutation]
        } else if let snippet {
            process.arguments = [script.path, "--snippet", snippet]
        } else {
            process.arguments = [script.path]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
