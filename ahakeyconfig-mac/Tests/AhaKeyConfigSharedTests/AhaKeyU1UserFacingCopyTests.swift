import XCTest

final class AhaKeyU1UserFacingCopyTests: XCTestCase {
    func testForbiddenLegacyPhrasesAreAbsentOutsideExactDiagnostics() throws {
        let output = try runCopyGate()
        XCTAssertTrue(output.exitCode == 0, output.text)
        XCTAssertTrue(output.text.contains("U1 user-facing copy gate ok"), output.text)
    }

    func testLegacyOwnerPhraseFailsGate() throws {
        let snippet = """
        NSLocalizedString("点「修改」进入编辑态（接管 BLE）", comment: "")
        """
        let output = try runCopyGate(snippet: snippet)
        XCTAssertNotEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("接管 BLE"), output.text)
    }

    func testBareUserFacingAgentFailsGate() throws {
        let snippet = """
        NSLocalizedString("Runtime 离线：请确认 Agent 已安装并运行后重试。", comment: "")
        """
        let output = try runCopyGate(snippet: snippet)
        XCTAssertNotEqual(output.exitCode, 0, output.text)
        XCTAssertTrue(output.text.contains("Agent"), output.text)
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

    private func runCopyGate(snippet: String? = nil) throws -> (exitCode: Int32, text: String) {
        let script = packageRoot().appendingPathComponent("scripts/check-u1-user-facing-copy.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        if let snippet {
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
