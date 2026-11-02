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

    /// permission 挂钩没有官方文件化：plugin 必须能「找不到就退回不介入」，而不是抛错或静默挂住。
    func testScriptDegradesGracefullyWithoutPermissionHook() {
        let script = OpenCodePluginInstaller.script(agentBinaryPath: "/tmp/agent")
        XCTAssertTrue(script.contains("permission.hook unavailable"),
                      "缺挂钩时应明确落日志，而不是静默失败")
        XCTAssertTrue(script.contains("typeof ctx.permission.hook"),
                      "应先检查挂钩是否存在（缺失时不拦截审批）")
        XCTAssertTrue(script.contains("session.execution.started"),
                      "事件映射应存在于脚本里")
    }

    /// 殘留的 running session 會讓燈條永遠停在「執行中」（實測：任務結束 13 秒後被心跳拉回藍色）。
    func testScriptRecoversFromStaleRunningSession() {
        let script = OpenCodePluginInstaller.script(agentBinaryPath: "/tmp/agent")
        XCTAssertTrue(script.contains("pruneStaleSessions"), "应有超时清理残留 running 的逻辑")
        XCTAssertTrue(script.contains("location.shutdown"), "location 关闭时应立即收尾")
        XCTAssertTrue(script.contains("STALE_RUNNING_MS"), "清理阈值应可辨识")
    }

    /// 短暫提示（工具完成/權限）之後必須回到聚合狀態，否則燈條會停在提示態（模擬測試抓到）。
    func testScriptRecoversFromTransientStates() {
        let script = OpenCodePluginInstaller.script(agentBinaryPath: "/tmp/agent")
        XCTAssertTrue(script.contains("emitDirect"), "短暂提示应走 emitDirect")
        XCTAssertTrue(script.contains("TRANSIENT_RECOVER_MS"), "应有回收计时器")
        XCTAssertTrue(script.contains("scheduleTransientRecovery"))
    }

    /// 事件流结束（plugin 重载 / location 关闭）时必须停掉计时器，否则旧实例会继续写状态。
    func testScriptStopsTimersWhenEventStreamEnds() {
        let script = OpenCodePluginInstaller.script(agentBinaryPath: "/tmp/agent")
        XCTAssertTrue(script.contains("} finally {"), "应在事件流结束时清理")
        XCTAssertTrue(script.contains("clearInterval(heartbeatTimer)"), "应停掉心跳")
        XCTAssertTrue(script.contains("transientTimers.clear()"))
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
