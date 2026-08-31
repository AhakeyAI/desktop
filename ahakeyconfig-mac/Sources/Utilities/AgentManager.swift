import Foundation
import os.log
import AhaKeyConfigShared

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "AgentManager")

/// 管理 ahakeyconfig-agent 守护进程的安装、启停、状态查询
@MainActor
final class AgentManager: ObservableObject {
    static let shared = AgentManager()

    private static let appGroupSuite = "lab.jawa.ahakeyconfig"
    private static let kimiTUIAdapterEnabledKey = "kimiTUIAdapterEnabled"

    @Published private(set) var isInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var isAgentBLEConnected = false   // agent 的 BLE 是否真正连上键盘
    @Published private(set) var hooksInstalled = false        // Claude / Cursor / Codex / Kimi hooks 是否装了任何一个
    @Published private(set) var claudeHooksInstalled = false
    @Published private(set) var cursorHooksInstalled = false
    @Published private(set) var codexHooksInstalled = false
    @Published private(set) var kimiHooksInstalled = false

    /// 实验性「实时控制当前前台 Kimi」开关。
    /// 开启后，拨杆切到自动/手动时会尝试向前台 Terminal.app / iTerm2 的当前 Kimi tab
    /// 发送 `/yolo on` 或 `/yolo off`。
    /// 使用 app group suite，保证主 App 与 agent 进程读写同一个值。
    @Published var kimiTUIAdapterEnabled: Bool = false {
        didSet {
            UserDefaults(suiteName: Self.appGroupSuite)?.set(kimiTUIAdapterEnabled, forKey: Self.kimiTUIAdapterEnabledKey)
        }
    }

    /// 安装 / 启停 Agent、写 Hooks 等操作的结果说明；关闭弹窗后由 UI 置 `nil`。
    @Published var agentUserAlert: String?

    /// 正在执行安装或 launchctl 启停，用于界面显示进度，避免「点了没反应」。
    @Published private(set) var isAgentOperationInProgress = false

    private let label = "lab.jawa.ahakeyconfig.agent"
    private let socketPath = AhaKeyPaths.agentSocketPath

    private var launchAgentsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var plistPath: String {
        launchAgentsDirectoryURL.appendingPathComponent("\(label).plist").path
    }

    /// `~/Library/LaunchAgents` 在全新系统用户下可能尚不存在，必须先创建再写 plist，否则会报「folder doesn't exist」类错误。
    private func ensureLaunchAgentsDirectory() throws {
        try FileManager.default.createDirectory(at: launchAgentsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    private var agentBinaryPath: String {
        // agent 安装到 app bundle 内部（发版须将 ahakeyconfig-agent 与主程序一并复制到 Contents/MacOS/）
        let appPath = Bundle.main.bundlePath
        return "\(appPath)/Contents/MacOS/ahakeyconfig-agent"
    }

    /// 供界面判断：包内是否带有 agent 可执行文件（发版缺拷贝时 LaunchAgent 无法真正运行）。
    var isAgentBinaryPresentInBundle: Bool {
        FileManager.default.isExecutableFile(atPath: agentBinaryPath)
    }

    /// 兼容性：老版本通过 shell 脚本转发；现在直接调用 agent 二进制。保留路径用于卸载时清理。
    private var legacyHookScriptPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/hooks/ahakey-state.sh").path
    }

    private var claudeSettingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json").path
    }

    private var cursorHooksPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cursor/hooks.json").path
    }

    private var codexConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml").path
    }

    private var codexAppCliPath: String {
        "/Applications/Codex.app/Contents/Resources/codex"
    }

    private var kimiConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi/config.toml").path
    }

    private var localBinDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true).path
    }

    private var localCodexCliPath: String {
        (localBinDirectoryPath as NSString).appendingPathComponent("codex")
    }

    private var zshrcPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zshrc").path
    }

    /// `~/.cursor/cli-config.json`：Cursor **CLI** 的 `permissions`（`Shell(...)` 等）与 `approvalMode`。
    private var cursorCliConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/cli-config.json").path
    }

    /// `~/.cursor/permissions.json`：IDE 内 **Agent 终端 TUI** 的 `terminalAllowlist`（与 cli-config 独立，见官方文档）。
    private var cursorPermissionsJsonPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/permissions.json").path
    }

    init() {
        kimiTUIAdapterEnabled = UserDefaults(suiteName: Self.appGroupSuite)?.bool(forKey: Self.kimiTUIAdapterEnabledKey) ?? false
        refresh()
    }

    // MARK: - 状态刷新

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: plistPath)
        isRunning = checkRunning()
        claudeHooksInstalled = detectClaudeHooksInstalled()
        cursorHooksInstalled = detectCursorHooksInstalled()
        codexHooksInstalled = detectCodexHooksInstalled()
        kimiHooksInstalled = detectKimiHooksInstalled()
        hooksInstalled = claudeHooksInstalled || cursorHooksInstalled || codexHooksInstalled || kimiHooksInstalled
        if isRunning {
            let socketPath = socketPath
            DispatchQueue.global(qos: .utility).async { [weak self, socketPath] in
                let bleConnected = Self.querySocketBLEConnected(socketPath: socketPath)
                DispatchQueue.main.async { self?.isAgentBLEConnected = bleConnected }
            }
        } else {
            isAgentBLEConnected = false
        }
    }

    /// 通知 agent 设置/清除虚拟拨杆覆盖。fire-and-forget；agent 会:
    /// 1) 落进 UserDefaults 持久化
    /// 2) 写入共享文件让主 App 立即看到
    /// 3) 不再发送旧 0x91；最新固件 0x91 用于灯效预览
    /// value=nil 表示清除覆盖（回到读真实 GPIO 值）。
    func sendSwitchOverride(_ value: UInt8?) {
        DispatchQueue.global(qos: .userInitiated).async { [socketPath] in
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            defer { close(fd) }
            var tv = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            socketPath.withCString { src in
                withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                    _ = strcpy(UnsafeMutableRawPointer(dst).assumingMemoryBound(to: CChar.self), src)
                }
            }
            let ok = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard ok == 0 else { return }
            let valuePart: String = value.map { "\($0)" } ?? "null"
            let payload = "{\"cmd\":\"set_switch_override\",\"value\":\(valuePart)}\n"
            guard let data = payload.data(using: .utf8) else { return }
            _ = data.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return write(fd, base, ptr.count)
            }
            var buf = [UInt8](repeating: 0, count: 256)
            _ = read(fd, &buf, buf.count) // 等回包再关 fd，避免 agent 还没处理就被 reset
        }
    }

    /// 向 agent socket 发 status 命令，switchState 非 null 即代表 BLE 已连上键盘。
    /// 同步执行，需在后台线程调用。
    nonisolated private static func querySocketBLEConnected(socketPath: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                _ = strcpy(UnsafeMutableRawPointer(dst).assumingMemoryBound(to: CChar.self), src)
            }
        }
        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { return false }

        guard let payload = "{\"cmd\":\"status\"}\n".data(using: .utf8) else { return false }
        let wrote = payload.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return write(fd, base, ptr.count)
        }
        guard wrote > 0 else { return false }

        var buf = [UInt8](repeating: 0, count: 256)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return false }

        guard let json = try? JSONSerialization.jsonObject(with: Data(buf[0..<n])) as? [String: Any] else {
            return false
        }
        return !(json["switchState"] is NSNull) && json["switchState"] != nil
    }

    /// 从 launchd 卸载 Agent（比 `stop` 更彻底：`KeepAlive` 下 stop 会立刻重启进程，仍占着蓝牙）。
    private func unloadAgentLaunchJobRemovingSocket() {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            removeStaleSocketIfNeeded()
            return
        }
        _ = runLaunchctlQuiet(["unload", plistPath])
        removeStaleSocketIfNeeded()
    }

    private func removeStaleSocketIfNeeded() {
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    private func detectClaudeHooksInstalled() -> Bool {
        guard let settings = loadClaudeSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let eventHooks = value as? [[String: Any]] else { continue }
            for entry in eventHooks {
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                if cmds.contains(where: { isAhakeyHookCommand(($0["command"] as? String) ?? "") }) {
                    return true
                }
            }
        }
        return false
    }

    private func detectCursorHooksInstalled() -> Bool {
        guard let settings = loadCursorSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            if entries.contains(where: { isAhakeyHookCommand(($0["command"] as? String) ?? "") }) {
                return true
            }
        }
        return false
    }

    private func detectCodexHooksInstalled() -> Bool {
        guard let text = try? String(contentsOfFile: codexConfigPath, encoding: .utf8) else {
            return false
        }
        // AhaKey 写入的 BEGIN/END 块即可判定（不依赖文件中是否仍能匹配到 ahakeyconfig-agent 字面量，避免因路径别名/重装 App 路径变化导致误判未装）
        if text.contains(codexHookBlockStart), text.contains(codexHookBlockEnd) {
            return true
        }
        return isAhakeyHookCommand(text)
            && (text.contains("hook Codex") || text.contains("CodexPermissionRequest"))
    }

    private func detectKimiHooksInstalled() -> Bool {
        guard let text = try? String(contentsOfFile: kimiConfigPath, encoding: .utf8) else {
            return false
        }
        return text.contains(kimiHookBlockStart)
            && text.contains(kimiHookBlockEnd)
            && isAhakeyHookCommand(text)
    }

    private func isAhakeyHookCommand(_ command: String) -> Bool {
        CursorHookInstaller.isManagedCommand(command)
    }

    private func checkRunning() -> Bool {
        // 检查 socket 是否存在（agent 运行时会创建）
        var statBuf = stat()
        return stat(socketPath, &statBuf) == 0 && (statBuf.st_mode & S_IFSOCK) != 0
    }

    // MARK: - 安装/卸载 LaunchAgent

    private func launchAgentPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(agentBinaryPath)</string>
                <string>--socket</string>
                <string>\(socketPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(logFilePath)</string>
            <key>StandardErrorPath</key>
            <string>\(logFilePath)</string>
        </dict>
        </plist>
        """
    }

    @discardableResult
    private func writeLaunchAgentPlist() -> Bool {
        do {
            try ensureLaunchAgentsDirectory()
            try launchAgentPlist().write(toFile: plistPath, atomically: true, encoding: .utf8)
            log.info("LaunchAgent 已安装: \(self.plistPath)")
            return true
        } catch {
            log.error("LaunchAgent 安装失败: \(error)")
            agentUserAlert = String(format: NSLocalizedString("无法写入后台服务配置文件：%@\n\n将写入：%@\n已尝试创建目录：%@\n若仍失败，请检查对「~/Library」是否有写权限，或本机管理策略是否禁止用户登录项。", comment: ""), String(error.localizedDescription), String(plistPath), String(launchAgentsDirectoryURL.path))
            return false
        }
    }

    private func launchAgentNeedsRewrite() -> Bool {
        // 必须比较完整 ProgramArguments：旧版本 plist 的 --socket 参数指向 /tmp/ahakey.sock，
        // 只比二进制路径会在同路径覆盖安装后保留旧 socket 路径，导致 Agent 在 /tmp 绑定而 GUI 在
        // Application Support 等待，表现为"已 load/start 但未检测到 Agent 在运行"。
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let args = plist["ProgramArguments"] as? [String] else { return true }
        return args != [agentBinaryPath, "--socket", socketPath]
    }

    func install() {
        agentUserAlert = nil
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }

        guard isAgentBinaryPresentInBundle else {
            agentUserAlert = NSLocalizedString("应用包内没有后台服务可执行文件，无法安装 AhaKey Runtime。请使用完整「AhaKey Studio.app」或联系开发者。", comment: "")
            return
        }

        // 1. 先卸载旧 job，再写入 plist。否则同 Label 已加载时 launchd 可能继续持有旧 ProgramArguments。
        unloadAgentLaunchJobRemovingSocket()
        guard writeLaunchAgentPlist() else { return }

        // 2. 载入并启动 Agent LaunchJob
        var loadFailed = false
        let load = runLaunchctlDetailed(["load", plistPath])
        if !load.ok && !isBenignLaunchctlLoadMessage(load.mergedOutput) {
            loadFailed = true
            log.error("launchctl load failed: \(load.mergedOutput)")
            let out = load.mergedOutput.isEmpty ? NSLocalizedString("（无输出，退出非 0）", comment: "") : load.mergedOutput
            agentUserAlert = String(format: NSLocalizedString("后台服务配置已保存，但系统未能载入后台服务。\n\n系统输出：\n%@\n\n常见原因：同一服务已存在、配置无效、对登录项目录无写权限。可先点「卸载」再装，或在「控制台」搜索 %@。", comment: ""), String(out), String(label))
        }

        // 3. 安装 Claude / Cursor / Codex / Kimi hooks（直接指向 agent 二进制 hook 子命令）
        let claudeLine = installClaudeHooks()
        let cursorLine = installCursorHooks()
        let codexLine = installCodexHooks()
        let kimiLine = installKimiHooks()

        refresh()

        var lines: [String] = []
        if !loadFailed {
            lines.append(NSLocalizedString("launchctl load 已执行。若数秒后未显示「运行中」，请点「查看日志」。", comment: ""))
        }
        if !claudeLine.isEmpty { lines.append(claudeLine) }
        if !cursorLine.isEmpty { lines.append(cursorLine) }
        if !codexLine.isEmpty { lines.append(codexLine) }
        if !kimiLine.isEmpty { lines.append(kimiLine) }
        let tail = lines.joined(separator: "\n\n")
        if let err = agentUserAlert {
            agentUserAlert = err + (tail.isEmpty ? "" : "\n\n——\n\n" + tail)
        } else {
            agentUserAlert = tail.isEmpty ? NSLocalizedString("安装完成。", comment: "") : tail
        }
    }

    func uninstall() {
        // 1. 卸载 LaunchAgent
        _ = runLaunchctlQuiet(["unload", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)

        // 2. 清理老版本 shell hook 脚本（如果存在）
        try? FileManager.default.removeItem(atPath: legacyHookScriptPath)

        // 3. 移除 Claude / Cursor / Codex / Kimi hooks 中的 ahakey 条目（同时覆盖老 shell 脚本与新二进制命令）
        removeClaudeHooks()
        removeCursorHooks()
        removeCodexHooks()
        _ = removeKimiHooks()

        // 4. 清理 socket
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        log.info("已卸载 agent + hooks")
        refresh()
    }

    /// 启动 Agent 守护进程（先确保 Job 已 load，再 start；适合「已安装但未运行」）。
    func start() {
        guard isInstalled else {
            agentUserAlert = NSLocalizedString("尚未安装后台服务。请先点「安装并启用」。", comment: "")
            return
        }
        if launchAgentNeedsRewrite() {
            unloadAgentLaunchJobRemovingSocket()
            guard writeLaunchAgentPlist() else { return }
        }
        isAgentOperationInProgress = true
        let loadRes = runLaunchctlDetailed(["load", plistPath])
        let startRes = runLaunchctlDetailed(["start", label])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self else { return }
            self.isAgentOperationInProgress = false
            self.refresh()
            if !self.isRunning {
                var m = String(format: NSLocalizedString("已执行启动，但尚未检测到后台服务在运行（未出现 %@）。\n\n", comment: ""), socketPath)
                if !loadRes.ok && !isBenignLaunchctlLoadMessage(loadRes.mergedOutput) {
                    m += "load：\n\(loadRes.mergedOutput.isEmpty ? "（无输出）" : loadRes.mergedOutput)\n\n"
                }
                if !startRes.ok {
                    m += "start：\n\(startRes.mergedOutput.isEmpty ? "（无输出）" : startRes.mergedOutput)\n\n"
                }
                m += String(format: NSLocalizedString("请点「查看日志」检查 %@；并确认系统「隐私与安全性」中已允许本应用使用蓝牙；若通过登录项拉起后台服务，也需为同一签名的二进制授权。", comment: ""), String(self.logFilePath))
                self.agentUserAlert = m
            } else if (!loadRes.ok && !isBenignLaunchctlLoadMessage(loadRes.mergedOutput)) || !startRes.ok {
                self.agentUserAlert = String(format: NSLocalizedString("AhaKey Runtime 已运行。附注：launchctl 输出 — load：%@ start：%@", comment: ""), String(loadRes.mergedOutput), String(startRes.mergedOutput))
            }
        }
    }

    /// 停止 Agent 并 **unload** 出 launchd，否则 `KeepAlive` 会让进程立刻重启并继续占蓝牙。
    func stop() {
        unloadAgentLaunchJobRemovingSocket()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Log

    var logFilePath: String {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics")
        try? FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent.log").path
    }

    /// Hook 子进程在每次 Claude `PermissionRequest` 时追加 JSON 行，与 `HookClient` 中 diagnostics 路径一致。
    var permissionRequestLogPath: String {
        URL(fileURLWithPath: logFilePath).deletingLastPathComponent()
            .appendingPathComponent("permission-request.log")
            .path
    }

    /// Codex 所有 AhaKey hook 触发记录：状态 hook 与 PermissionRequest 都会追加 JSON 行。
    var codexHookLogPath: String {
        URL(fileURLWithPath: logFilePath).deletingLastPathComponent()
            .appendingPathComponent("codex-hook.log")
            .path
    }

    func readLog() -> String {
        (try? String(contentsOfFile: logFilePath, encoding: .utf8)) ?? NSLocalizedString("(无日志)", comment: "")
    }

    // MARK: - Cursor 用户级文件（可展示、可合并，非 Hook 子进程管理）

    /// 与「安装 Cursor Hooks」写入路径一致，便于在 UI 中展示或对照。
    var userCursorHooksJsonFilePath: String { cursorHooksPath }

    /// Codex 0.125 使用 `~/.codex/config.toml` 的 inline `[[hooks.Event]]`。
    var userCodexConfigFilePath: String { codexConfigPath }

    /// Kimi Code CLI（Beta）使用 `~/.kimi/config.toml` 的 `[[hooks]]`。
    var userKimiConfigFilePath: String { kimiConfigPath }

    /// Cursor CLI / Agent 的全局 `permissions` 等（控制 Shell 等是否仍弹层确认，与 `hooks.json` 独立）。
    var userCursorCliConfigFilePath: String { cursorCliConfigPath }

    /// 将 `~/.cursor/hooks.json` 以可读（pretty）形式读出；不存在时返回说明。
    func readUserCursorHooksJsonForDisplay() -> String {
        let path = cursorHooksPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("（文件不存在：%@）\n\n可先点「安装 Cursor Hooks」生成或合并；若只使用**项目内** `.cursor/hooks.json`，本路径仍可能为空。", comment: ""), String(path))
        }
        return Self.prettyJsonString(atPath: path) ?? String(format: NSLocalizedString("（存在但无法解析为 JSON：%@）", comment: ""), String(path))
    }

    /// 将 `~/.cursor/cli-config.json` 以可读（pretty）形式读出；不存在时提示。
    func readUserCursorCliConfigForDisplay() -> String {
        let path = cursorCliConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("（文件不存在：%@）\n\n可点诊断面板中「合并 Shell 白名单 + approvalMode=auto」从空白创建；或自行在文档中按 `permissions` 配置。", comment: ""), String(path))
        }
        return Self.prettyJsonString(atPath: path) ?? String(format: NSLocalizedString("（存在但无法解析为 JSON：%@）", comment: ""), String(path))
    }

    /// 将 `~/.codex/config.toml` 原样读出；Codex hooks 是 TOML，不是 JSON。
    func readUserCodexConfigForDisplay() -> String {
        let path = codexConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("（文件不存在：%@）\n\n可先点「安装 Codex Hooks」创建并合并 `[features].hooks` 与 AhaKey hook block。", comment: ""), String(path))
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? String(format: NSLocalizedString("（存在但无法读取：%@）", comment: ""), String(path))
    }

    /// `~/.kimi/config.toml` 原样读出（Kimi Hooks 配置为文本 TOML）。
    func readUserKimiConfigForDisplay() -> String {
        let path = kimiConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("（文件不存在：%@）\n\n可先点「安装 Kimi Hooks」创建并写入 AhaKey 标记块；须已安装并使用 Kimi Code CLI：https://moonshotai.github.io/kimi-cli/", comment: ""), String(path))
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? String(format: NSLocalizedString("（存在但无法读取：%@）", comment: ""), String(path))
    }

    /// 备份当前 `cli-config` 后，合并 `permissions.allow`（不删你已有项），并设置 `approvalMode` 为 `auto`。
    /// 用于减轻「hook 已 allow 但 Cursor 仍要求再点一次」中 **Cursor 自己那一层** 的拦阻。
    /// - Returns: 给用户看的结果说明。
    func mergeUserCursorCliConfigForShellAutoApprove() -> String {
        let path = cursorCliConfigPath
        let cursorDir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        } catch {
            return String(format: NSLocalizedString("无法创建目录 %@：%@", comment: ""), String(cursorDir), String(error.localizedDescription))
        }
        if FileManager.default.fileExists(atPath: path) {
            let bak = path + ".ahakey.bak"
            do {
                if FileManager.default.fileExists(atPath: bak) {
                    try FileManager.default.removeItem(atPath: bak)
                }
                try FileManager.default.copyItem(atPath: path, toPath: bak)
            } catch {
                return String(format: NSLocalizedString("已存在 %@ 但无法复制备份到 %@：%@", comment: ""), String(path), String(bak), String(error.localizedDescription))
            }
        }
        var root = loadCursorCliConfig() ?? [:]
        if root["version"] == nil { root["version"] = 1 }

        var perms = root["permissions"] as? [String: Any] ?? [:]
        var allow = Self.stringArrayValue(perms["allow"])
        let additions: [String] = [
            "Shell(*)", "Shell(cd)", "Shell(swift)", "Shell(xcodebuild)", "Shell(git)", "Shell(python3)", "Shell(npm)", "Shell(cargo)", "Shell(curl)", "Shell(ls)",
        ]
        var merged = 0
        for a in additions {
            if !allow.contains(a) {
                allow.append(a)
                merged += 1
            }
        }
        perms["allow"] = allow
        if perms["deny"] == nil { perms["deny"] = [String]() }
        root["permissions"] = perms
        root["approvalMode"] = "auto"

        guard saveCursorCliConfig(root) else {
            return String(format: NSLocalizedString("合并后的 JSON 无法写回：%@", comment: ""), String(path))
        }
        log.info("cli-config: merged Shell allow + approvalMode=auto at \(path)")
        return String(format: NSLocalizedString("已写回：%@\n（此前若存在同路径文件，已备份为 %@.ahakey.bak）\n\n本次在 permissions.allow 中新增合并 %@ 条常见 Shell(...) 规则（已有规则保留）；approvalMode 已设为 auto。\n\n若某版本仍弹窗，请把仍被拦的命令首词对照文档自行追加白名单：\nhttps://cursor.com/docs/cli/reference/permissions\n或检查工作区 .cursor/cli.json 是否另有限制。", comment: ""), String(path), String(path), String(merged))
    }

    /// 合并 `~/.cursor/permissions.json` 的 `terminalAllowlist`（**IDE「Not in allowlist」** 与 cli-config 无关）。
    func mergeUserCursorPermissionsJsonForAgentTUI() -> String {
        let path = cursorPermissionsJsonPath
        let cursorDir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        } catch {
            return String(format: NSLocalizedString("无法创建目录 %@：%@", comment: ""), String(cursorDir), String(error.localizedDescription))
        }
        if FileManager.default.fileExists(atPath: path) {
            let bak = path + ".ahakey.bak"
            do {
                if FileManager.default.fileExists(atPath: bak) { try FileManager.default.removeItem(atPath: bak) }
                try FileManager.default.copyItem(atPath: path, toPath: bak)
            } catch {
                return String(format: NSLocalizedString("已存在 permissions.json 但无法备份到 %@：%@", comment: ""), String(bak), String(error.localizedDescription))
            }
        }
        var root = loadCursorPermissionsJson() ?? [:]
        var list = Self.stringArrayValue(root["terminalAllowlist"])
        let additions = [
            "cd", "swift", "swift build", "xcodebuild", "git", "npm", "yarn", "pnpm", "bun", "deno", "node",
            "make", "cargo", "go", "python3", "python", "bash", "zsh", "sh", "curl", "ls",
        ]
        var n = 0
        for a in additions where !list.contains(a) {
            list.append(a)
            n += 1
        }
        root["terminalAllowlist"] = list
        guard saveCursorPermissionsJson(root) else {
            return String(format: NSLocalizedString("无法写回：%@", comment: ""), String(path))
        }
        log.info("permissions.json: merged terminalAllowlist at \(path)")
        return String(format: NSLocalizedString("已写回：%@（备份为 %@.ahakey.bak）\n\n本次在 terminalAllowlist 中新增合并 %@ 条前缀；用于 Cursor 终端内「Not in allowlist」层，与 cli-config 的 Shell(...) 是两套。文档：\nhttps://cursor.com/docs/reference/permissions", comment: ""), String(path), String(path), String(n))
    }

    private func loadCursorPermissionsJson() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: cursorPermissionsJsonPath),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return j
    }

    private func saveCursorPermissionsJson(_ root: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: cursorPermissionsJsonPath), options: .atomic)
            return true
        } catch {
            log.error("saveCursorPermissionsJson: \(error.localizedDescription)")
            return false
        }
    }

    private static func prettyJsonString(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    private static func stringArrayValue(_ v: Any?) -> [String] {
        if let a = v as? [String] { return a }
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    private func loadCursorCliConfig() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: cursorCliConfigPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func saveCursorCliConfig(_ root: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: cursorCliConfigPath), options: .atomic)
            return true
        } catch {
            log.error("saveCursorCliConfig: \(error.localizedDescription)")
            return false
        }
    }

    /// 只读；由 `ahakeyconfig-agent` 在 `PermissionRequest` 与 Cursor 批准类 hook 中写入。
    func readPermissionRequestLog() -> String {
        (try? String(contentsOfFile: permissionRequestLogPath, encoding: .utf8))
            ?? NSLocalizedString("尚无记录。在 Claude 中触发 PermissionRequest，在 Cursor 中让模型调工具/Shell/MCP，或在 Kimi Code CLI 中触发工具调用后，会在此追加带 `ide` / `hookEvent` 的 JSON 行。若始终为空，请确认已安装 AhaKey Runtime、IDE 集成，且 `~/Library/.../AhaKeyConfig/diagnostics/` 可写。", comment: "")
    }

    /// 只读；由 `ahakeyconfig-agent hook Codex*` 子进程写入，用于判断 Codex 客户端/终端是否真的触发了 hook。
    func readCodexHookLog() -> String {
        (try? String(contentsOfFile: codexHookLogPath, encoding: .utf8))
            ?? NSLocalizedString("尚无记录。触发 Codex 后应在此追加 JSON 行。若终端 Codex 有记录、Codex 客户端没有记录，说明客户端未加载当前 `~/.codex/config.toml` hook，通常需要重启 Codex 客户端/新开终端后再测。", comment: "")
    }

    // MARK: - Claude hooks 追加

    /// Claude Code 支持的 hook 事件（和 HookClient.eventMap 对齐）
    private let hookEvents: [String] = [
        "Notification",
        "PermissionRequest",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SubagentStop",  // Claude Code 拆分后：手动终止任务时触发此事件
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "TaskCompleted",
        "PreCompact",
    ]

    /// Shell 安全地引用一个路径（单引号包裹 + 转义内部单引号）
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 空串表示已写入；非空为「跳过 / 失败」说明，需展示给用户。
    private func installClaudeHooks() -> String {
        guard var settings = loadClaudeSettings() else {
            return NSLocalizedString("Claude Hooks：未找到 ~/.claude/settings.json，已跳过。使用 Claude Code 并生成该文件后，可再点「安装 Claude Hooks」。", comment: "")
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let binQuoted = shellQuote(agentBinaryPath)

        for event in hookEvents {
            let ahakeyCmd = "\(binQuoted) hook \(event)"
            var eventHooks = hooks[event] as? [[String: Any]] ?? []

            // 先清掉老的 ahakey 条目，避免 shell 脚本 + 新二进制并存
            for i in eventHooks.indices {
                var entry = eventHooks[i]
                if var cmds = entry["hooks"] as? [[String: Any]] {
                    cmds.removeAll { isAhakeyHookCommand(($0["command"] as? String) ?? "") }
                    entry["hooks"] = cmds
                    eventHooks[i] = entry
                }
            }

            if let idx = eventHooks.firstIndex(where: { ($0["matcher"] as? String) == "" }) {
                var entry = eventHooks[idx]
                var cmds = entry["hooks"] as? [[String: Any]] ?? []
                cmds.append(["type": "command", "command": ahakeyCmd])
                entry["hooks"] = cmds
                eventHooks[idx] = entry
            } else {
                eventHooks.append([
                    "matcher": "",
                    "hooks": [["type": "command", "command": ahakeyCmd]],
                ])
            }
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks
        if saveClaudeSettings(settings) {
            log.info("Claude hooks 已写入 ahakeyconfig-agent hook 子命令")
            return ""
        }
        return String(format: NSLocalizedString("Claude Hooks：无法写入 %@。请检查该文件或父目录的权限/只读状态。", comment: ""), String(claudeSettingsPath))
    }

    private func removeClaudeHooks() {
        guard var settings = loadClaudeSettings() else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in hookEvents {
            guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
            for i in eventHooks.indices {
                var entry = eventHooks[i]
                if var cmds = entry["hooks"] as? [[String: Any]] {
                    cmds.removeAll { isAhakeyHookCommand(($0["command"] as? String) ?? "") }
                    entry["hooks"] = cmds
                    eventHooks[i] = entry
                }
            }
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks
        if !saveClaudeSettings(settings) {
            log.error("removeClaudeHooks: 无法写回 settings")
        } else {
            log.info("Claude hooks 中 ahakey 条目已移除")
        }
    }

    private func loadClaudeSettings() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func saveClaudeSettings(_ settings: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: claudeSettingsPath), options: .atomic)
            return true
        } catch {
            log.error("saveClaudeSettings: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Cursor hooks

    private let codexHookBlockStart = "# BEGIN AhaKey Codex Hooks"
    private let codexHookBlockEnd = "# END AhaKey Codex Hooks"
    private let codexHookEvents: [(event: String, agentEvent: String, timeout: Int)] = [
        ("SessionStart", "CodexSessionStart", 10),
        ("PostToolUse", "CodexPostToolUse", 10),
        ("PreToolUse", "CodexPreToolUse", 20),
        ("PermissionRequest", "CodexPermissionRequest", 20),
        ("UserPromptSubmit", "CodexUserPromptSubmit", 10),
        ("Stop", "CodexStop", 10),
    ]

    private let kimiHookBlockStart = "# BEGIN AhaKey Kimi Hooks"
    private let kimiHookBlockEnd = "# END AhaKey Kimi Hooks"
    private let kimiHookEntries: [(event: String, agentEvent: String, timeout: Int)] = [
        ("Notification", "KimiNotification", 10),
        ("SessionStart", "KimiSessionStart", 10),
        ("SessionEnd", "KimiSessionEnd", 10),
        ("PreToolUse", "KimiPreToolUse", 20),
        ("PostToolUse", "KimiPostToolUse", 10),
        ("UserPromptSubmit", "KimiUserPromptSubmit", 10),
        ("Stop", "KimiStop", 10),
    ]

    /// 单独安装 Claude hooks
    func installClaudeHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        let s = installClaudeHooks()
        agentUserAlert = s.isEmpty ? NSLocalizedString("Claude Hooks 已写入 ~/.claude/settings.json。", comment: "") : s
        refresh()
    }

    /// 单独移除 Claude hooks
    func removeClaudeHooksOnly() {
        removeClaudeHooks()
        refresh()
    }

    /// 单独安装 Cursor hooks（公开给 UI 用，例如只想补装 Cursor 时调用）
    func installCursorHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        let s = installCursorHooks()
        agentUserAlert = s.isEmpty ? NSLocalizedString("Cursor Hooks 已写入 ~/.cursor/hooks.json。", comment: "") : s
        refresh()
    }

    /// 单独安装 Codex hooks（Codex 0.125 为 inline TOML）。
    func installCodexHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        let s = installCodexHooks()
        agentUserAlert = s.isEmpty ? NSLocalizedString("Codex Hooks 已写入 ~/.codex/config.toml。\n\n安装完成。请重启 Codex 终端或客户端后再使用。", comment: "") : s
        refresh()
    }

    /// 单独移除 Cursor hooks
    func removeCursorHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        agentUserAlert = performRemoveCursorHooksUserMessage()
        refresh()
    }

    /// 单独移除 Codex hooks。
    func removeCodexHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        agentUserAlert = removeCodexHooks()
        refresh()
    }

    /// 单独安装 Kimi Code CLI hooks（`~/.kimi/config.toml`，Beta）。
    func installKimiHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        let s = installKimiHooks()
        agentUserAlert = s.isEmpty
            ? NSLocalizedString("""
            Kimi Hooks 已写入 ~/.kimi/config.toml。

            **AhaKey 拨杆接管也已部署**：
            - 配置层：`~/.kimi-code/config.toml` 的 `default_permission_mode` 会随拨杆同步，决定**新启动**的 Kimi 会话默认权限。
            - Launcher 层：`~/.ahakey/bin/kimi` 会在新会话启动时根据拨杆自动注入 `--yolo`（自动档）或不注入（手动档）。

            如果 kimi 当前已经打开，请**完全关闭并重新打开一次**，新会话才会生效。正在运行的会话不受影响；如需实时切换当前会话，请手动输入 `/yolo on` 或 `/yolo off`。
            以后若你**升级了 kimi-cli**，再次点击一次「安装 Kimi Hooks」即可把 launcher 补回去。

            安装完成。Hooks 为 Beta，行为以官方文档为准。
            """, comment: "")
            : s
        refresh()
    }

    /// 单独移除 Kimi Hooks 标记块。
    func removeKimiHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        agentUserAlert = removeKimiHooks()
        refresh()
    }

    private func installCursorHooks() -> String {
        // Cursor 的目录可能不存在，先建好
        let cursorDir = (cursorHooksPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        } catch {
            return String(format: NSLocalizedString("Cursor Hooks：无法创建目录 %@：%@", comment: ""), String(cursorDir), String(error.localizedDescription))
        }

        let settings = CursorHookInstaller.install(
            in: loadCursorSettings() ?? [:],
            agentCommand: shellQuote(agentBinaryPath)
        )
        if saveCursorSettings(settings) {
            log.info("Cursor hooks v1 已写入（单一 preToolUse 决策入口）")
            return ""
        }
        return String(format: NSLocalizedString("Cursor Hooks：无法写入 %@。请检查权限或磁盘空间。", comment: ""), String(cursorHooksPath))
    }

    private func installCodexHooks() -> String {
        let codexDir = (codexConfigPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: codexDir, withIntermediateDirectories: true)
        } catch {
            return String(format: NSLocalizedString("Codex Hooks：无法创建目录 %@：%@", comment: ""), String(codexDir), String(error.localizedDescription))
        }

        var config = (try? String(contentsOfFile: codexConfigPath, encoding: .utf8)) ?? ""
        config = removeCodexHookBlock(from: config)
        config = ensureCodexHooksFeatureEnabled(in: config)
        config = config.trimmingCharacters(in: .whitespacesAndNewlines)
        if !config.isEmpty { config += "\n\n" }
        config += buildCodexHookBlock()
        config += "\n"
        // Codex 新版本要求 hooks 内容哈希已记录信任（[hooks.state] trusted_hash）才会执行；
        // 每次重装都会改动内容使旧信任失效，必须与 hook 块一起重写信任条目。
        config = CodexHookTrust.upsertTrustEntries(
            in: config,
            configPath: codexConfigPath,
            entries: codexHookTrustEntries()
        )

        do {
            try config.write(toFile: codexConfigPath, atomically: true, encoding: .utf8)
            guard FileManager.default.fileExists(atPath: codexConfigPath),
                  let written = try? String(contentsOfFile: codexConfigPath, encoding: .utf8),
                  written.contains(codexHookBlockStart),
                  written.contains(codexHookBlockEnd) else {
                log.error("installCodexHooks: 写入后校验失败 \(self.codexConfigPath)")
                return String(format: NSLocalizedString("Codex Hooks：已尝试写入 %@，但校验时未发现 AhaKey 标记块。请确认对「用户主目录 /.codex」有写权限，或关闭占用该文件的其它程序。", comment: ""), String(codexConfigPath))
            }
            log.info("Codex hooks 已写入 ~/.codex/config.toml")
            let cliRepair = repairCodexCliPathIfNeeded()
            return cliRepair.isEmpty
                ? ""
                : String(format: NSLocalizedString("Codex Hooks 已写入 ~/.codex/config.toml。\n\n%@\n\n安装完成。请重启 Codex 终端或客户端后再使用。", comment: ""), String(cliRepair))
        } catch {
            log.error("installCodexHooks: \(error.localizedDescription)")
            return String(format: NSLocalizedString("Codex Hooks：无法写入 %@：%@", comment: ""), String(codexConfigPath), String(error.localizedDescription))
        }
    }

    private func repairCodexCliPathIfNeeded() -> String {
        if isExecutableOnPath("codex") {
            return ""
        }
        guard FileManager.default.isExecutableFile(atPath: codexAppCliPath) else {
            return String(format: NSLocalizedString("未在 PATH 中找到 `codex` 命令，也未找到 Codex App 自带 CLI：%@。Hook 配置已安装；若需在终端使用 Codex，请先安装或更新 Codex 客户端。", comment: ""), String(codexAppCliPath))
        }

        do {
            try FileManager.default.createDirectory(atPath: localBinDirectoryPath, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: localCodexCliPath) {
                try FileManager.default.removeItem(atPath: localCodexCliPath)
            }
            try FileManager.default.createSymbolicLink(atPath: localCodexCliPath, withDestinationPath: codexAppCliPath)
        } catch {
            return String(format: NSLocalizedString("检测到终端中 `codex` 不可用，但无法创建 %@：%@。Hook 配置已安装。", comment: ""), String(localCodexCliPath), String(error.localizedDescription))
        }

        let zshLine = #"export PATH="$HOME/.local/bin:$PATH""#
        do {
            var zshrc = (try? String(contentsOfFile: zshrcPath, encoding: .utf8)) ?? ""
            if !zshrc.contains("HOME/.local/bin") && !zshrc.contains("$HOME/.local/bin") {
                if FileManager.default.fileExists(atPath: zshrcPath) {
                    let bak = zshrcPath + ".ahakey.bak"
                    if FileManager.default.fileExists(atPath: bak) {
                        try FileManager.default.removeItem(atPath: bak)
                    }
                    try FileManager.default.copyItem(atPath: zshrcPath, toPath: bak)
                }
                zshrc = zshrc.trimmingCharacters(in: .whitespacesAndNewlines)
                if !zshrc.isEmpty { zshrc += "\n" }
                zshrc += zshLine + "\n"
                try zshrc.write(toFile: zshrcPath, atomically: true, encoding: .utf8)
                return String(format: NSLocalizedString("已检测到 Codex App 自带 CLI，并修复终端命令：\n%@ → %@\n\n已将 `~/.local/bin` 加入 ~/.zshrc（若原文件存在，已备份为 ~/.zshrc.ahakey.bak）。", comment: ""), String(localCodexCliPath), String(codexAppCliPath))
            }
        } catch {
            return String(format: NSLocalizedString("已创建 %@，但无法更新 ~/.zshrc：%@。请手动把 `~/.local/bin` 加入 PATH。", comment: ""), String(localCodexCliPath), String(error.localizedDescription))
        }

        return String(format: NSLocalizedString("已检测到 Codex App 自带 CLI，并创建终端命令：\n%@ → %@", comment: ""), String(localCodexCliPath), String(codexAppCliPath))
    }

    private func isExecutableOnPath(_ command: String) -> Bool {
        executablePathOnPath(command) != nil
    }

    private func executablePathOnPath(_ command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    private func removeCodexHooks() -> String {
        let path = codexConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("未找到 %@，无需移除 Codex Hooks。", comment: ""), String(path))
        }
        guard let config = try? String(contentsOfFile: path, encoding: .utf8) else {
            return String(format: NSLocalizedString("无法读取 %@，请检查权限。", comment: ""), String(path))
        }
        // 连同 AhaKey 管理的 [hooks.state] 信任条目一起移除，避免卸载后残留失效哈希。
        let next = CodexHookTrust.removeTrustEntries(in: removeCodexHookBlock(from: config), configPath: path)
        guard next != config else {
            return String(format: NSLocalizedString("在 %@ 中未发现 AhaKey Codex hook 标记块。", comment: ""), String(path))
        }
        do {
            try next.write(toFile: path, atomically: true, encoding: .utf8)
            log.info("Codex hooks 中 AhaKey 标记块已移除")
            return String(format: NSLocalizedString("已从 %@ 移除 AhaKey Codex Hooks。", comment: ""), String(path))
        } catch {
            return String(format: NSLocalizedString("已生成移除后的内容，但无法写回 %@：%@", comment: ""), String(path), String(error.localizedDescription))
        }
    }

    private func buildCodexHookBlock() -> String {
        let binQuoted = shellQuote(agentBinaryPath)
        var lines: [String] = [
            codexHookBlockStart,
            "# Managed by AhaKey Studio. Codex 0.125 uses inline TOML hooks; each command hook needs type = \"command\".",
        ]
        for item in codexHookEvents {
            lines.append("")
            lines.append("[[hooks.\(item.event)]]")
            lines.append("matcher = \"\"")
            lines.append("")
            lines.append("[[hooks.\(item.event).hooks]]")
            lines.append("type = \"command\"")
            lines.append("command = \"\(escapeTomlBasicString("/bin/zsh -lc \(shellQuote("\(binQuoted) hook \(item.agentEvent)"))"))\"")
            lines.append("timeout = \(item.timeout)")
        }
        lines.append("")
        lines.append(codexHookBlockEnd)
        return lines.joined(separator: "\n")
    }

    /// 与 buildCodexHookBlock 写入内容一一对应的 [hooks.state] 信任条目。
    /// command 取 TOML 反转义后的原始值（与 codex 解析后参与哈希的值一致）。
    private func codexHookTrustEntries() -> [(key: String, hash: String)] {
        let binQuoted = shellQuote(agentBinaryPath)
        return codexHookEvents.compactMap { item in
            let command = "/bin/zsh -lc \(shellQuote("\(binQuoted) hook \(item.agentEvent)"))"
            guard let key = CodexHookTrust.stateKey(configPath: codexConfigPath, event: item.event),
                  let hash = CodexHookTrust.trustedHash(event: item.event, matcher: "", command: command, timeout: item.timeout)
            else { return nil }
            return (key, hash)
        }
    }

    private func removeCodexHookBlock(from config: String) -> String {
        var lines = config.components(separatedBy: .newlines)
        while let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == codexHookBlockStart }),
              let end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == codexHookBlockEnd }) {
            lines.removeSubrange(start...end)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func ensureCodexHooksFeatureEnabled(in config: String) -> String {
        var lines = config.components(separatedBy: .newlines)
        var featuresStart: Int?
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "[features]" {
                featuresStart = idx
                break
            }
        }

        guard let start = featuresStart else {
            var next = config.trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty { next += "\n\n" }
            next += "[features]\nhooks = true\n"
            return next
        }

        var sectionEnd = lines.count
        if start + 1 < lines.count {
            for idx in (start + 1)..<lines.count {
                let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    sectionEnd = idx
                    break
                }
            }
        }

        // Codex 新版用 `hooks`；旧版写过已废弃的 `codex_hooks`（会触发 deprecation 警告）。
        // 两者都识别：保留/改写第一个命中为 `hooks = true`，其余（含所有 `codex_hooks`）删除。
        let keyPattern = #"^\s*(codex_)?hooks\s*="#
        let regex = try? NSRegularExpression(pattern: keyPattern)
        var matchedIndices: [Int] = []
        for idx in (start + 1)..<sectionEnd {
            let line = lines[idx]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if regex?.firstMatch(in: line, range: range) != nil {
                matchedIndices.append(idx)
            }
        }

        guard let first = matchedIndices.first else {
            lines.insert("hooks = true", at: start + 1)
            return lines.joined(separator: "\n")
        }

        lines[first] = "hooks = true"
        for idx in matchedIndices.dropFirst().reversed() {
            lines.remove(at: idx)
        }
        return lines.joined(separator: "\n")
    }

    private func escapeTomlBasicString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func installKimiHooks() -> String {
        let kimiDir = (kimiConfigPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: kimiDir, withIntermediateDirectories: true)
        } catch {
            return String(format: NSLocalizedString("Kimi Hooks：无法创建目录 %@：%@", comment: ""), String(kimiDir), String(error.localizedDescription))
        }

        var config = (try? String(contentsOfFile: kimiConfigPath, encoding: .utf8)) ?? ""
        config = removeKimiHookBlock(from: config)
        config = removeLegacyKimiHookEntries(from: config)
        config = config.trimmingCharacters(in: .whitespacesAndNewlines)
        if !config.isEmpty { config += "\n\n" }
        config += buildKimiHookBlock()
        config += "\n"

        do {
            try config.write(toFile: kimiConfigPath, atomically: true, encoding: .utf8)
            log.info("Kimi hooks 已写入 ~/.kimi/config.toml")
            return installKimiCodeLauncher() ?? ""
        } catch {
            log.error("installKimiHooks: \(error.localizedDescription)")
            return String(format: NSLocalizedString("Kimi Hooks：无法写入 %@：%@", comment: ""), String(kimiConfigPath), String(error.localizedDescription))
        }
    }

    /// 新版 Kimi Code dial-aware launcher 脚本内容。
    /// 通过 PATH 前置 (`~/.ahakey/bin/kimi`) 拦截启动，不覆盖厂商二进制。
    private let kimiLauncherScript = #"""
    #!/bin/zsh
    # ahakey-kimi-launcher (experimental)
    # PATH-prepend wrapper that decides whether to start a new interactive Kimi
    # session in yolo mode based on the AhaKey hardware dial.
    #
    # Limitations:
    # - Only affects newly launched Kimi sessions.
    # - Cannot switch a running Kimi session in real time.
    # - Physical dial is ignored when the user explicitly passes -y/--yolo/--auto.
    set -euo pipefail

    REAL_KIMI="${AHAKEY_REAL_KIMI:-${HOME}/.kimi-code/bin/kimi}"
    SOCKET="${AHAKEY_SOCKET_PATH:-${HOME}/Library/Application Support/AhaKeyConfig/ahakey.sock}"

    # If the real binary cannot be found, fall back to searching PATH but exclude
    # this launcher directory to avoid recursion.
    if [[ ! -x "$REAL_KIMI" ]]; then
        local launcher_dir="${0:A:h}"
        local stripped_path=""
        local old_ifs="$IFS"
        IFS=':'
        for p in ${(s.:.)PATH}; do
            if [[ "$p" != "$launcher_dir" ]]; then
                if [[ -z "$stripped_path" ]]; then
                    stripped_path="$p"
                else
                    stripped_path="${stripped_path}:$p"
                fi
            fi
        done
        IFS="$old_ifs"
        REAL_KIMI="$(PATH="$stripped_path" command -v kimi 2>/dev/null || true)"
        if [[ -z "$REAL_KIMI" ]] || [[ ! -x "$REAL_KIMI" ]]; then
            echo "ahakey-kimi-launcher: cannot find real kimi binary" >&2
            exit 1
        fi
    fi

    # Explicit permission flags always win over the physical dial.
    # Also skip if -y is already present to avoid duplicate injection.
    local explicit_permission=0
    for explicit_arg in "$@"; do
        case "$explicit_arg" in
            -y|--yolo|--auto)
                explicit_permission=1
                ;;
        esac
    done
    if (( explicit_permission )); then
        exec "$REAL_KIMI" "$@"
    fi

    # Decide whether this invocation is a fresh interactive session launch.
    # We do NOT inject -y for non-interactive subcommands, help/version, prompt
    # mode, or session resume (where Kimi may keep the previous permission state).
    local skip_injection=0
    for cmd_arg in "$@"; do
        case "$cmd_arg" in
            -h|--help|-V|--version|--prompt|-p|--output-format)
                skip_injection=1
                ;;
            doctor|upgrade|update|provider|export|server|web|login|vis|migrate|acp)
                skip_injection=1
                ;;
            --continue|-c|--session|-S)
                skip_injection=1
                ;;
        esac
    done

    local add_yolo=0
    if (( ! skip_injection )); then
        if [[ -S "$SOCKET" ]]; then
            local response
            response=$(/usr/bin/nc -U "$SOCKET" -w 1 2>/dev/null <<<'{"cmd":"approval_status"}' || true)
            if [[ -n "$response" ]]; then
                # Lightweight JSON extraction of switchState without python3.
                local switch_state
                switch_state=$(printf '%s' "$response" | awk 'BEGIN{RS=",";FS=":"} /"switchState"/{gsub(/[^0-9-]/,"",$2); print $2; exit}')
                if [[ "$switch_state" == "0" ]]; then
                    add_yolo=1
                fi
            fi
        fi
    fi

    if (( add_yolo )); then
        exec "$REAL_KIMI" -y "$@"
    else
        exec "$REAL_KIMI" "$@"
    fi
    """#

    private var launcherBinDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ahakey/bin", isDirectory: true)
            .path
    }

    private var launcherPath: String {
        (launcherBinDirectory as NSString).appendingPathComponent("kimi")
    }

    private var shellConfigPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            (home as NSString).appendingPathComponent(".zshrc"),
            (home as NSString).appendingPathComponent(".bash_profile"),
        ]
    }

    /// 为新版 Kimi Code 安装 PATH 前置的 dial-aware launcher。
    /// 不覆盖厂商二进制，只在 `~/.ahakey/bin/kimi` 放置 launcher 并在 shell 配置里前置 PATH。
    /// - Returns: 失败时返回给用户看的说明；成功或已是 launcher 时返回 nil。
    private func installKimiCodeLauncher() -> String? {
        let fm = FileManager.default
        let binDir = launcherBinDirectory
        let launcher = launcherPath

        do {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

            // 如果已经存在同内容 launcher，就不再重复写入
            if let existing = try? String(contentsOfFile: launcher, encoding: .utf8),
               existing == kimiLauncherScript {
                // 仍尝试更新 PATH 配置
                var pathMessages: [String] = []
                for configPath in shellConfigPaths where fm.fileExists(atPath: configPath) {
                    if let msg = prependAhaKeyBinToShellConfig(configPath) {
                        pathMessages.append(msg)
                    }
                }
                return pathMessages.isEmpty ? nil : pathMessages.joined(separator: "\n")
            }

            try kimiLauncherScript.write(toFile: launcher, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher)

            var pathMessages: [String] = []
            for configPath in shellConfigPaths where fm.fileExists(atPath: configPath) {
                if let msg = prependAhaKeyBinToShellConfig(configPath) {
                    pathMessages.append(msg)
                }
            }

            log.info("Kimi Code launcher installed at \(launcher)")
            let baseMessage = String(format: NSLocalizedString("新版 Kimi Code 的 dial-aware launcher 已安装到 %@。", comment: ""), String(launcher))
            if pathMessages.isEmpty {
                return baseMessage + NSLocalizedString("\n\n请重新打开终端，或执行 `source ~/.zshrc`，让 launcher 生效。", comment: "")
            } else {
                return baseMessage + "\n\n" + pathMessages.joined(separator: "\n")
            }
        } catch {
            log.error("installKimiCodeLauncher: \(error.localizedDescription)")
            return String(format: NSLocalizedString("无法安装新版 Kimi Code launcher：%@", comment: ""), String(error.localizedDescription))
        }
    }

    /// 卸载新版 Kimi Code launcher，恢复原版 PATH 顺序。
    private func removeKimiCodeLauncher() -> String {
        let fm = FileManager.default
        let launcher = launcherPath

        var messages: [String] = []

        if fm.fileExists(atPath: launcher) {
            do {
                try fm.removeItem(atPath: launcher)
                log.info("Kimi Code launcher removed at \(launcher)")
            } catch {
                messages.append(String(format: NSLocalizedString("无法删除 launcher %@：%@", comment: ""), String(launcher), String(error.localizedDescription)))
            }
        }

        for configPath in shellConfigPaths where fm.fileExists(atPath: configPath) {
            if let msg = removeAhaKeyBinFromShellConfig(configPath) {
                messages.append(msg)
            }
        }

        return messages.joined(separator: "\n")
    }

    /// 在 shell 配置文件末尾追加 `export PATH="$HOME/.ahakey/bin:$PATH"`。
    ///
    /// 必须让它在所有其他 PATH export（包括 `~/.kimi-code/bin`）**之后**执行，这样
    /// `~/.ahakey/bin` 才会被 prepend 到 PATH 最前面，保证 launcher 优先。
    /// 若文件中已有该 export，会先移除旧行再追加到末尾，避免重复或位置错误。
    private func prependAhaKeyBinToShellConfig(_ configPath: String) -> String? {
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return String(format: NSLocalizedString("无法读取 %@", comment: ""), String(configPath))
        }

        let marker = "$HOME/.ahakey/bin"
        let newLine = "export PATH=\"$HOME/.ahakey/bin:$PATH\""

        // 如果文件非空且最后一行已经是目标 export，视为已正确安装。
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(newLine) {
            return nil
        }

        let backupPath = configPath + ".ahakey.bak"
        do {
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
        } catch {
            return String(format: NSLocalizedString("备份 %@ 失败：%@", comment: ""), String(configPath), String(error.localizedDescription))
        }

        var lines = text.components(separatedBy: .newlines)
        // 移除所有旧的 AhaKey PATH 行，避免残留导致顺序错误。
        lines.removeAll { line in
            line.contains(marker) && line.contains("PATH=")
        }

        // 清理末尾多余空行，然后追加一个空行和目标 export。
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        lines.append("")
        lines.append(newLine)

        do {
            try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return String(format: NSLocalizedString("无法写入 %@：%@", comment: ""), String(configPath), String(error.localizedDescription))
        }
    }

    /// 从 shell 配置文件中移除 `~/.ahakey/bin` 的 PATH 行。
    private func removeAhaKeyBinFromShellConfig(_ configPath: String) -> String? {
        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        let marker = "$HOME/.ahakey/bin"
        guard text.contains(marker) else { return nil }

        let backupPath = configPath + ".ahakey.bak"
        do {
            try? FileManager.default.removeItem(atPath: backupPath)
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
        } catch {
            return String(format: NSLocalizedString("备份 %@ 失败：%@", comment: ""), String(configPath), String(error.localizedDescription))
        }

        var lines = text.components(separatedBy: .newlines)
        let originalCount = lines.count
        lines.removeAll { line in
            line.contains(marker) && line.contains("PATH=")
        }
        guard lines.count != originalCount else { return nil }

        do {
            try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return String(format: NSLocalizedString("无法恢复 %@：%@", comment: ""), String(configPath), String(error.localizedDescription))
        }
    }

    @discardableResult
    private func removeKimiHooks() -> String {
        let path = kimiConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("未找到 %@，无需移除 Kimi Hooks。", comment: ""), String(path))
        }
        guard let config = try? String(contentsOfFile: path, encoding: .utf8) else {
            return String(format: NSLocalizedString("无法读取 %@，请检查权限。", comment: ""), String(path))
        }
        let next = removeLegacyKimiHookEntries(from: removeKimiHookBlock(from: config))
        guard next != config else {
            return String(format: NSLocalizedString("在 %@ 中未发现 AhaKey Kimi hook 标记块或旧版裸 hook。", comment: ""), String(path))
        }
        do {
            try next.write(toFile: path, atomically: true, encoding: .utf8)
            log.info("Kimi hooks 中 AhaKey 标记块与旧版裸 hook 已移除")
            let launcherRestoreError = removeKimiCodeLauncher()
            let baseMessage = String(format: NSLocalizedString("已从 %@ 移除 AhaKey Kimi Hooks。", comment: ""), String(path))
            if launcherRestoreError.isEmpty {
                return baseMessage
            } else {
                return baseMessage + "\n\n" + launcherRestoreError
            }
        } catch {
            return String(format: NSLocalizedString("已生成移除后的内容，但无法写回 %@：%@", comment: ""), String(path), String(error.localizedDescription))
        }
    }

    private func buildKimiHookBlock() -> String {
        let binQuoted = shellQuote(agentBinaryPath)
        var lines: [String] = [
            kimiHookBlockStart,
            "# Managed by AhaKey Studio. Kimi CLI (Beta): multiple [[hooks]] entries; each runs with JSON on stdin.",
            "# Dial integration is managed by AhaKey Studio. Re-click 'Install Kimi Hooks' after kimi-cli upgrades, then reopen kimi once.",
        ]
        for item in kimiHookEntries {
            let cmdToml = escapeTomlBasicString("/bin/zsh -lc \(shellQuote("\(binQuoted) hook \(item.agentEvent)"))")
            lines.append("")
            lines.append("[[hooks]]")
            lines.append("event = \"\(item.event)\"")
            lines.append("matcher = \"\"")
            lines.append("command = \"\(cmdToml)\"")
            lines.append("timeout = \(item.timeout)")
        }
        lines.append("")
        lines.append(kimiHookBlockEnd)
        return lines.joined(separator: "\n")
    }

    private func removeKimiHookBlock(from config: String) -> String {
        var lines = config.components(separatedBy: .newlines)
        while let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == kimiHookBlockStart }),
              let end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == kimiHookBlockEnd }) {
            lines.removeSubrange(start...end)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// 清理未包在 BEGIN/END 标记块中的旧版 AhaKey Kimi hook，避免同一事件重复触发两次。
    private func removeLegacyKimiHookEntries(from config: String) -> String {
        let lines = config.components(separatedBy: .newlines)
        var kept: [String] = []
        var idx = 0

        while idx < lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            guard trimmed == "[[hooks]]" else {
                kept.append(lines[idx])
                idx += 1
                continue
            }

            var block = [lines[idx]]
            idx += 1
            while idx < lines.count {
                let nextTrimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                if nextTrimmed == "[[hooks]]" || nextTrimmed == kimiHookBlockStart || nextTrimmed == kimiHookBlockEnd {
                    break
                }
                block.append(lines[idx])
                idx += 1
            }

            let joined = block.joined(separator: "\n")
            if isAhakeyHookCommand(joined), joined.contains("hook Kimi") {
                continue
            }
            kept.append(contentsOf: block)
        }

        return kept.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// 供「卸载主流程」等内部调用，无 UI 提示。
    private func removeCursorHooks() {
        _ = performRemoveCursorHooksUserMessage(writeAndLog: true, preferCompactMessage: true)
    }

    /// 从 `~/.cursor/hooks.json` 的 **全部** 事件里删掉指向 ahakey 的条目，并写回文件。
    /// - Returns: 给用户看的说明（弹窗用）；`writeAndLog==false` 时仍返回文案但不写盘（当前未用）。
    private func performRemoveCursorHooksUserMessage(writeAndLog: Bool = true, preferCompactMessage: Bool = false) -> String {
        let path = cursorHooksPath
        guard FileManager.default.fileExists(atPath: path) else {
            return String(format: NSLocalizedString("未找到用户级 %@。\n\n若你只在**项目**里合并过 `.cursor/hooks.json`，需在该项目根目录中手动编辑或删除 AhaKey 相关条目，用户级里本来就没有可卸内容。", comment: ""), String(path))
        }
        guard var settings = loadCursorSettings() else {
            return String(format: NSLocalizedString("无法解析 %@（非合法 JSON 或已损坏）。请用编辑器打开修正后再试，或从备份恢复。", comment: ""), String(path))
        }
        guard var hooks = settings["hooks"] as? [String: Any], !hooks.isEmpty else {
            return NSLocalizedString("hooks.json 中无「hooks」或为空，没有可移除的 AhaKey 项。", comment: "")
        }

        var removedCount = 0
        for event in Array(hooks.keys).sorted() {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            let before = entries.count
            entries.removeAll { isAhakeyHookCommand(($0["command"] as? String) ?? "") }
            removedCount += before - entries.count
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if removedCount == 0 {
            return String(format: NSLocalizedString("在 %@ 中**未发现** AhaKey Runtime 相关 `command`。\n\n若 Hook 在**项目级** `.cursor/hooks.json`，请在该仓库内手动删除；本按钮只改用户级 `~/.cursor/hooks.json`。", comment: ""), String(path))
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        if writeAndLog {
            if !saveCursorSettings(settings) {
                log.error("removeCursorHooks: 无法写回 hooks.json")
                return String(format: NSLocalizedString("已删除内存中的 AhaKey 条目，但**无法写回** %@。请检查对「用户目录下 .cursor」的写权限，或关闭占用该文件的其他应用后重试。", comment: ""), String(path))
            }
            log.info("Cursor hooks: removed \(removedCount) ahakey command(s)")
        }

        if preferCompactMessage { return "" }
        return String(format: NSLocalizedString("已从用户级 Cursor Hooks 中移除 AhaKey 相关条目（共 %@ 条子命令）。\n\n文件：%@\n\n若某仓库仍有**项目级** `.cursor/hooks.json` 且其中含有本工具，其优先级可能更高，需在该项目内同步删除或合并。", comment: ""), String(removedCount), String(path))
    }

    private func loadCursorSettings() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: cursorHooksPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func saveCursorSettings(_ settings: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: cursorHooksPath), options: .atomic)
            return true
        } catch {
            log.error("saveCursorSettings: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - launchctl

    private struct LaunchctlResult {
        let ok: Bool
        let mergedOutput: String
    }

    private func runLaunchctlDetailed(_ args: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return LaunchctlResult(ok: process.terminationStatus == 0, mergedOutput: text)
        } catch {
            return LaunchctlResult(ok: false, mergedOutput: error.localizedDescription)
        }
    }

    /// 再次 load 时系统常提示「已加载」类信息，不当作致命错误。
    private func isBenignLaunchctlLoadMessage(_ message: String) -> Bool {
        let m = message.lowercased()
        if m.isEmpty { return false }
        if m.contains("already") { return true }
        if m.contains("repeated load") { return true }
        if m.contains("service already") { return true }
        return false
    }

    @discardableResult
    private func runLaunchctlQuiet(_ args: [String]) -> Bool {
        runLaunchctlDetailed(args).ok
    }
}
