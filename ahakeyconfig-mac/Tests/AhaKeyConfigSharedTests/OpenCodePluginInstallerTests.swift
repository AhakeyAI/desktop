import XCTest
@testable import AhaKeyConfigShared

final class OpenCodePluginInstallerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-opencode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 安装 → 看得见标记 → 卸载 → 文件消失。
    func testInstallAndRemoveRoundTrip() throws {
        let url = tempDir.appendingPathComponent("ahakey-bridge.js")
        XCTAssertFalse(OpenCodePluginInstaller.isInstalled(at: url))

        try OpenCodePluginInstaller.install(agentBinaryPath: "/Applications/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", to: url)
        XCTAssertTrue(OpenCodePluginInstaller.isInstalled(at: url))
        XCTAssertTrue(try OpenCodePluginInstaller.remove(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// 使用者自己写的同名文件（没有标记）不能被当成我们的，也不能被删。
    func testForeignFileIsNeverRemoved() throws {
        let url = tempDir.appendingPathComponent("ahakey-bridge.js")
        try "// my own plugin\nexport default { id: 'x', async setup() {} }\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(OpenCodePluginInstaller.isInstalled(at: url))
        XCTAssertFalse(try OpenCodePluginInstaller.remove(at: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// 生成的内嵌脚本必须带上真实二进制路径、且不再残留占位符。
    func testScriptEmbedsAgentPathSafely() {
        let path = "/tmp/with \"quotes\" and \\backslash/ahakeyconfig-agent"
        let script = OpenCodePluginInstaller.script(agentBinaryPath: path)
        XCTAssertFalse(script.contains(OpenCodePluginInstaller.agentPlaceholder))
        XCTAssertTrue(script.contains(OpenCodePluginInstaller.marker))
        XCTAssertTrue(script.contains("OpenCodePermissionEvaluate"))
        // 路径必须被正确转义成合法 JS 字符串（能再被 JSON 解析回来）。
        let line = script.split(separator: "\n").first { $0.hasPrefix("const AGENT_BIN =") }
        let literal = try? XCTUnwrap(line).replacingOccurrences(of: "const AGENT_BIN = ", with: "").replacingOccurrences(of: ";", with: "")
        let data = Data((literal ?? "").utf8)
        // 顶层裸字符串是 JSON fragment，必须显式允许，否则永远解析成 nil。
        let decoded = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
        XCTAssertEqual(decoded ?? nil, path)
    }

    /// XDG_CONFIG_HOME 优先，其次是 ~/.config。
    func testPluginsDirectoryFollowsXDG() {
        let home = URL(fileURLWithPath: "/Users/example")
        let xdg = OpenCodePluginInstaller.pluginsDirectory(environment: ["XDG_CONFIG_HOME": "/custom/cfg"], home: home)
        XCTAssertEqual(xdg.path, "/custom/cfg/opencode/plugins")
        let plain = OpenCodePluginInstaller.pluginsDirectory(environment: [:], home: home)
        XCTAssertEqual(plain.path, "/Users/example/.config/opencode/plugins")
    }
}
