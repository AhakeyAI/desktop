import Foundation
import os.log

private let log = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "AgentManager")

// MARK: - 蓝牙占用方（AhaKey Studio 与 Agent 是两套独立进程，同一时刻只应有一个 GATT 连接键盘）

/// 由谁持有与键盘的 BLE 连接。
/// - `ahaKeyStudio`：主 App 连接，用于改键、OLED、本机 LED 测试等。
/// - `agentDaemon`：仅运行 `ahakeyconfig-agent`（Hook → Unix socket → 写 0x90 状态、读拨杆），由 LaunchAgent 拉起。
enum BluetoothConnectionOwner: String, CaseIterable, Identifiable {
    case ahaKeyStudio
    case agentDaemon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ahaKeyStudio: return "AhaKey Studio"
        case .agentDaemon: return "ahakeyconfig-agent"
        }
    }

    var shortDetail: String {
        switch self {
        case .ahaKeyStudio: return "本 App 连接蓝牙，用于配置与同步。Agent 的 LaunchJob 在持有方为 App 时不会加载，避免抢连接。"
        case .agentDaemon: return "仅 Agent 连接蓝牙。Claude/Cursor Hook 才能驱动灯条与拨杆查询；本 App 里无法对键盘发 BLE 命令。"
        }
    }
}

/// 管理 ahakeyconfig-agent 守护进程的安装、启停、状态查询
@MainActor
final class AgentManager: ObservableObject {
    static let shared = AgentManager()

    private static let bluetoothOwnerKey = "lab.jawa.ahakeyconfig.bluetoothConnectionOwner"
    private static var didApplyLaunchBluetoothPreference = false

    @Published private(set) var isInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var isAgentBLEConnected = false   // agent 的 BLE 是否真正连上键盘
    @Published private(set) var hooksInstalled = false        // Claude OR Cursor hooks 是否装了任何一个
    @Published private(set) var claudeHooksInstalled = false
    @Published private(set) var cursorHooksInstalled = false

    /// 用户选择的蓝牙占用方（存 UserDefaults，启动时应用一次）
    @Published var bluetoothConnectionOwner: BluetoothConnectionOwner = .agentDaemon

    /// 安装 / 启停 Agent、写 Hooks 等操作的结果说明；关闭弹窗后由 UI 置 `nil`。
    @Published var agentUserAlert: String?

    /// 正在执行安装或 launchctl 启停，用于界面显示进度，避免「点了没反应」。
    @Published private(set) var isAgentOperationInProgress = false

    private let label = "lab.jawa.ahakeyconfig.agent"
    private let socketPath = "/tmp/ahakey.sock"

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
        bluetoothConnectionOwner = .agentDaemon
        UserDefaults.standard.set(BluetoothConnectionOwner.agentDaemon.rawValue, forKey: Self.bluetoothOwnerKey)
        refresh()
    }

    // MARK: - 状态刷新

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: plistPath)
        isRunning = checkRunning()
        claudeHooksInstalled = detectClaudeHooksInstalled()
        cursorHooksInstalled = detectCursorHooksInstalled()
        hooksInstalled = claudeHooksInstalled || cursorHooksInstalled
        if isRunning {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let bleConnected = self.querySocketBLEConnected()
                DispatchQueue.main.async { self.isAgentBLEConnected = bleConnected }
            }
        } else {
            isAgentBLEConnected = false
        }
    }

    /// 向 agent socket 发 status 命令，switchState 非 null 即代表 BLE 已连上键盘。
    /// 同步执行，需在后台线程调用。
    private func querySocketBLEConnected() -> Bool {
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

    // MARK: - 蓝牙占用方（App ↔ Agent 二选一）

    /// 启动主窗口时调用一次：按用户上次选择，要么由 App 连键盘，要么交给 Agent（不自动连 App）。
    func applyStoredBluetoothPreferenceOnLaunch(bleManager: AhaKeyBLEManager) {
        guard !Self.didApplyLaunchBluetoothPreference else { return }
        Self.didApplyLaunchBluetoothPreference = true
        applyBluetoothOwner(bluetoothConnectionOwner, bleManager: bleManager, isLaunch: true)
    }

    /// 用户在「设备信息」里切换占用方时调用。
    func setBluetoothConnectionOwner(_ owner: BluetoothConnectionOwner, bleManager: AhaKeyBLEManager) {
        guard owner != bluetoothConnectionOwner else { return }
        bluetoothConnectionOwner = owner
        UserDefaults.standard.set(owner.rawValue, forKey: Self.bluetoothOwnerKey)
        applyBluetoothOwner(owner, bleManager: bleManager, isLaunch: false)
    }

    private func applyBluetoothOwner(_ owner: BluetoothConnectionOwner, bleManager: AhaKeyBLEManager, isLaunch: Bool) {
        switch owner {
        case .ahaKeyStudio:
            bleManager.setSuppressedForAgentOwningKeyboard(false)
            unloadAgentLaunchJobRemovingSocket()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(isLaunch ? 700 : 600))
                guard !bleManager.isConnected, !bleManager.isScanning else { return }
                bleManager.connectAutomatically()
            }
        case .agentDaemon:
            bleManager.setSuppressedForAgentOwningKeyboard(true)
            bleManager.disconnect()
            guard isInstalled else {
                log.info("未安装 LaunchAgent，无法将蓝牙交给 Agent，临时允许 App 连接")
                bleManager.setSuppressedForAgentOwningKeyboard(false)
                if !isLaunch {
                    agentUserAlert = "尚未安装 Agent，无法切回「键盘控制中」。请在「更多 → 设备信息 · Agent」里先安装并启用 Agent。"
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if !bleManager.isConnected, !bleManager.isScanning {
                        bleManager.connectAutomatically()
                    }
                }
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(isLaunch ? 500 : 550))
                _ = runLaunchctlQuiet(["load", plistPath])
                _ = runLaunchctlQuiet(["start", label])
                self.refresh()
            }
        }
        if !isLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                self?.refresh()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.refresh()
            }
        }
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

    private func isAhakeyHookCommand(_ command: String) -> Bool {
        command.contains("ahakeyconfig-agent") || command.contains("ahakey-state")
    }

    private func checkRunning() -> Bool {
        // 检查 socket 是否存在（agent 运行时会创建）
        var statBuf = stat()
        return stat(socketPath, &statBuf) == 0 && (statBuf.st_mode & S_IFSOCK) != 0
    }

    // MARK: - 安装/卸载 LaunchAgent

    func install() {
        agentUserAlert = nil
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }

        guard isAgentBinaryPresentInBundle else {
            agentUserAlert = "应用包内没有可执行的 ahakeyconfig-agent（路径：…/Contents/MacOS/ahakeyconfig-agent）。请确认发版脚本已把该二进制一并打进 .app；仅有主程序时无法安装守护进程。"
            return
        }

        // 1. 创建 LaunchAgent plist
        let plist = """
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

        do {
            try ensureLaunchAgentsDirectory()
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            log.info("LaunchAgent 已安装: \(self.plistPath)")
        } catch {
            log.error("LaunchAgent 安装失败: \(error)")
            agentUserAlert = "无法写入 LaunchAgent 配置文件：\(error.localizedDescription)\n\n将写入：\(plistPath)\n已尝试创建目录：\(launchAgentsDirectoryURL.path)\n若仍失败，请检查对「~/Library」是否有写权限，或本机管理策略是否禁止用户 LaunchAgents。"
            return
        }

        // 2. 仅当用户希望 Agent 持有蓝牙时才 load（否则只写入 plist，避免装完立刻抢 GATT）
        var loadFailed = false
        if bluetoothConnectionOwner == .agentDaemon {
            let load = runLaunchctlDetailed(["load", plistPath])
            if !load.ok && !isBenignLaunchctlLoadMessage(load.mergedOutput) {
                loadFailed = true
                log.error("launchctl load failed: \(load.mergedOutput)")
                let out = load.mergedOutput.isEmpty ? "（无输出，退出非 0）" : load.mergedOutput
                agentUserAlert = "LaunchAgent 的 plist 已保存，但 launchctl load 失败，守护进程未载入。\n\nlaunchctl 输出：\n\(out)\n\n常见原因：同一 Label 已存在、plist 无效、对 ~/Library/LaunchAgents 无写权限。可先点「卸载」再装，或在「控制台」搜索 \(label)。"
            }
        }

        // 3. 安装 Claude / Cursor hooks（直接指向 agent 二进制 hook 子命令）
        let claudeLine = installClaudeHooks()
        let cursorLine = installCursorHooks()

        refresh()

        var lines: [String] = []
        if bluetoothConnectionOwner == .agentDaemon, !loadFailed {
            lines.append("launchctl load 已执行。若数秒后未显示「运行中」，请点「查看日志」。")
        }
        if !claudeLine.isEmpty { lines.append(claudeLine) }
        if !cursorLine.isEmpty { lines.append(cursorLine) }
        let tail = lines.joined(separator: "\n\n")
        if let err = agentUserAlert {
            agentUserAlert = err + (tail.isEmpty ? "" : "\n\n——\n\n" + tail)
        } else {
            agentUserAlert = tail.isEmpty ? "安装完成。" : tail
        }
    }

    func uninstall(bleManager: AhaKeyBLEManager? = nil) {
        // 1. 卸载 LaunchAgent
        _ = runLaunchctlQuiet(["unload", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)

        // 2. 清理老版本 shell hook 脚本（如果存在）
        try? FileManager.default.removeItem(atPath: legacyHookScriptPath)

        // 3. 移除 Claude / Cursor hooks 中的 ahakey 条目（同时覆盖老 shell 脚本与新二进制命令）
        removeClaudeHooks()
        removeCursorHooks()

        // 4. 清理 socket
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        bluetoothConnectionOwner = .ahaKeyStudio
        UserDefaults.standard.set(BluetoothConnectionOwner.ahaKeyStudio.rawValue, forKey: Self.bluetoothOwnerKey)
        bleManager?.setSuppressedForAgentOwningKeyboard(false)

        log.info("已卸载 agent + hooks")
        refresh()
    }

    /// 启动 Agent 守护进程（先确保 Job 已 load，再 start；适合「已安装但未运行」）。
    func start() {
        guard isInstalled else {
            agentUserAlert = "尚未安装 LaunchAgent。请先点「安装并启用」。"
            return
        }
        isAgentOperationInProgress = true
        let loadRes = runLaunchctlDetailed(["load", plistPath])
        let startRes = runLaunchctlDetailed(["start", label])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self else { return }
            self.isAgentOperationInProgress = false
            self.refresh()
            if !self.isRunning {
                var m = "已执行 launchctl load / start，但尚未检测到 Agent 在运行（未出现 /tmp/ahakey.sock）。\n\n"
                if !loadRes.ok && !isBenignLaunchctlLoadMessage(loadRes.mergedOutput) {
                    m += "load：\n\(loadRes.mergedOutput.isEmpty ? "（无输出）" : loadRes.mergedOutput)\n\n"
                }
                if !startRes.ok {
                    m += "start：\n\(startRes.mergedOutput.isEmpty ? "（无输出）" : startRes.mergedOutput)\n\n"
                }
                m += "请点「查看日志」检查 \(self.logFilePath)；并确认系统「隐私与安全性」中已允许本应用使用蓝牙；若通过 LaunchAgent 拉起 agent 子进程，也需为同一签名的二进制授权。"
                self.agentUserAlert = m
            } else if (!loadRes.ok && !isBenignLaunchctlLoadMessage(loadRes.mergedOutput)) || !startRes.ok {
                self.agentUserAlert = "Agent 已运行。附注：launchctl 输出 — load：\(loadRes.mergedOutput) start：\(startRes.mergedOutput)"
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

    func readLog() -> String {
        (try? String(contentsOfFile: logFilePath, encoding: .utf8)) ?? "(无日志)"
    }

    // MARK: - Cursor 用户级文件（可展示、可合并，非 Hook 子进程管理）

    /// 与「安装 Cursor Hooks」写入路径一致，便于在 UI 中展示或对照。
    var userCursorHooksJsonFilePath: String { cursorHooksPath }

    /// Cursor CLI / Agent 的全局 `permissions` 等（控制 Shell 等是否仍弹层确认，与 `hooks.json` 独立）。
    var userCursorCliConfigFilePath: String { cursorCliConfigPath }

    /// 将 `~/.cursor/hooks.json` 以可读（pretty）形式读出；不存在时返回说明。
    func readUserCursorHooksJsonForDisplay() -> String {
        let path = cursorHooksPath
        guard FileManager.default.fileExists(atPath: path) else {
            return "（文件不存在：\(path)）\n\n可先点「安装 Cursor Hooks」生成或合并；若只使用**项目内** `.cursor/hooks.json`，本路径仍可能为空。"
        }
        return Self.prettyJsonString(atPath: path) ?? "（存在但无法解析为 JSON：\(path)）"
    }

    /// 将 `~/.cursor/cli-config.json` 以可读（pretty）形式读出；不存在时提示。
    func readUserCursorCliConfigForDisplay() -> String {
        let path = cursorCliConfigPath
        guard FileManager.default.fileExists(atPath: path) else {
            return "（文件不存在：\(path)）\n\n可点诊断面板中「合并 Shell 白名单 + approvalMode=auto」从空白创建；或自行在文档中按 `permissions` 配置。"
        }
        return Self.prettyJsonString(atPath: path) ?? "（存在但无法解析为 JSON：\(path)）"
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
            return "无法创建目录 \(cursorDir)：\(error.localizedDescription)"
        }
        if FileManager.default.fileExists(atPath: path) {
            let bak = path + ".ahakey.bak"
            do {
                if FileManager.default.fileExists(atPath: bak) {
                    try FileManager.default.removeItem(atPath: bak)
                }
                try FileManager.default.copyItem(atPath: path, toPath: bak)
            } catch {
                return "已存在 \(path) 但无法复制备份到 \(bak)：\(error.localizedDescription)"
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
            return "合并后的 JSON 无法写回：\(path)"
        }
        log.info("cli-config: merged Shell allow + approvalMode=auto at \(path)")
        return "已写回：\(path)\n（此前若存在同路径文件，已备份为 \(path).ahakey.bak）\n\n本次在 permissions.allow 中新增合并 \(merged) 条常见 Shell(...) 规则（已有规则保留）；approvalMode 已设为 auto。\n\n若某版本仍弹窗，请把仍被拦的命令首词对照文档自行追加白名单：\nhttps://cursor.com/docs/cli/reference/permissions\n或检查工作区 .cursor/cli.json 是否另有限制。"
    }

    /// 合并 `~/.cursor/permissions.json` 的 `terminalAllowlist`（**IDE「Not in allowlist」** 与 cli-config 无关）。
    func mergeUserCursorPermissionsJsonForAgentTUI() -> String {
        let path = cursorPermissionsJsonPath
        let cursorDir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        } catch {
            return "无法创建目录 \(cursorDir)：\(error.localizedDescription)"
        }
        if FileManager.default.fileExists(atPath: path) {
            let bak = path + ".ahakey.bak"
            do {
                if FileManager.default.fileExists(atPath: bak) { try FileManager.default.removeItem(atPath: bak) }
                try FileManager.default.copyItem(atPath: path, toPath: bak)
            } catch {
                return "已存在 permissions.json 但无法备份到 \(bak)：\(error.localizedDescription)"
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
            return "无法写回：\(path)"
        }
        log.info("permissions.json: merged terminalAllowlist at \(path)")
        return "已写回：\(path)（备份为 \(path).ahakey.bak）\n\n本次在 terminalAllowlist 中新增合并 \(n) 条前缀；用于 Agent 内「Not in allowlist」层，与 cli-config 的 Shell(...) 是两套。文档：\nhttps://cursor.com/docs/reference/permissions"
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
            ?? "尚无记录。在 Claude 中触发 PermissionRequest，或在 Cursor 中让 Agent 调工具/Shell/MCP 后，会在此追加带 `ide` / `hookEvent` 的 JSON 行。若始终为空，请确认已安装 Agent、Hooks、蓝牙由 Agent 占用，且 `~/Library/.../AhaKeyConfig/diagnostics/` 可写。"
    }

    // MARK: - Claude hooks 追加

    /// Claude Code 支持的 hook 事件（和 HookClient.eventMap 对齐）
    private let hookEvents: [String] = [
        "Notification",
        "PermissionRequest",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "TaskCompleted",
    ]

    /// Shell 安全地引用一个路径（单引号包裹 + 转义内部单引号）
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 空串表示已写入；非空为「跳过 / 失败」说明，需展示给用户。
    private func installClaudeHooks() -> String {
        guard var settings = loadClaudeSettings() else {
            return "Claude Hooks：未找到 ~/.claude/settings.json，已跳过。使用 Claude Code 并生成该文件后，可再点「安装 Claude Hooks」。"
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
        return "Claude Hooks：无法写入 \(claudeSettingsPath)。请检查该文件或父目录的权限/只读状态。"
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

    /// Cursor 支持的 hook 事件（小驼峰，与 `HookClient` 一致）。
    /// 批准链集中在 `preToolUse`（在任意工具前调用，可 stdout `permission`）；若你在 `hooks.json` 里自行添加
    /// `beforeShellExecution` / `beforeMCPExecution` 并指向本 agent，其事件名在 `HookClient` 中同样支持拨杆。
    /// 安装时写入这些事件；**卸载**时会遍历 `hooks` 的**所有键**（含旧版/合并进的 `beforeReadFile`、`beforeSubmitPrompt` 等），避免只卸一半导致「没反应」。
    private let cursorHookEvents: [String] = [
        "sessionStart",
        "sessionEnd",
        "preToolUse",
        "beforeShellExecution",
        "beforeMCPExecution",
        "beforeReadFile",
        "beforeSubmitPrompt",
        "postToolUse",
        "stop",
    ]

    /// 单独安装 Claude hooks
    func installClaudeHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        let s = installClaudeHooks()
        agentUserAlert = s.isEmpty ? "Claude Hooks 已写入 ~/.claude/settings.json。" : s
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
        agentUserAlert = s.isEmpty ? "Cursor Hooks 已写入 ~/.cursor/hooks.json。" : s
        refresh()
    }

    /// 单独移除 Cursor hooks
    func removeCursorHooksOnly() {
        isAgentOperationInProgress = true
        defer { isAgentOperationInProgress = false }
        agentUserAlert = performRemoveCursorHooksUserMessage()
        refresh()
    }

    private func installCursorHooks() -> String {
        // Cursor 的目录可能不存在，先建好
        let cursorDir = (cursorHooksPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: cursorDir, withIntermediateDirectories: true)
        } catch {
            return "Cursor Hooks：无法创建目录 \(cursorDir)：\(error.localizedDescription)"
        }

        var settings = loadCursorSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let binQuoted = shellQuote(agentBinaryPath)

        for event in cursorHookEvents {
            let cmd = "\(binQuoted) hook \(event)"
            // Cursor：`{ "hooks": { "<event>": [{ "command": "...", "timeout": N }] } }`
            // 读拨杆/写状态略慢，长超时与 `HookClient` 一致
            let t: Int
            if event == "beforeSubmitPrompt" { t = 30 }
            else if ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "sessionStart"].contains(event) { t = 20 }
            else { t = 10 }
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { isAhakeyHookCommand(($0["command"] as? String) ?? "") }
            entries.append(["command": cmd, "timeout": t])
            hooks[event] = entries
        }

        settings["hooks"] = hooks
        if settings["version"] == nil {
            settings["version"] = 1
        }
        if saveCursorSettings(settings) {
            log.info("Cursor hooks 已写入")
            return ""
        }
        return "Cursor Hooks：无法写入 \(cursorHooksPath)。请检查权限或磁盘空间。"
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
            return "未找到用户级 \(path)。\n\n若你只在**项目**里合并过 `.cursor/hooks.json`，需在该项目根目录中手动编辑或删除 AhaKey 相关条目，用户级里本来就没有可卸内容。"
        }
        guard var settings = loadCursorSettings() else {
            return "无法解析 \(path)（非合法 JSON 或已损坏）。请用编辑器打开修正后再试，或从备份恢复。"
        }
        guard var hooks = settings["hooks"] as? [String: Any], !hooks.isEmpty else {
            return "hooks.json 中无「hooks」或为空，没有可移除的 AhaKey 项。"
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
            return "在 \(path) 中**未发现**包含 `ahakeyconfig-agent` 或 `ahakey-state` 的 `command`。\n\n若 Hook 在**项目级** `.cursor/hooks.json`，请在该仓库内手动删除；本按钮只改用户级 `~/.cursor/hooks.json`。"
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        if writeAndLog {
            if !saveCursorSettings(settings) {
                log.error("removeCursorHooks: 无法写回 hooks.json")
                return "已删除内存中的 AhaKey 条目，但**无法写回** \(path)。请检查对「用户目录下 .cursor」的写权限，或关闭占用该文件的其他应用后重试。"
            }
            log.info("Cursor hooks: removed \(removedCount) ahakey command(s)")
        }

        if preferCompactMessage { return "" }
        return "已从用户级 Cursor Hooks 中移除 AhaKey 相关条目（共 \(removedCount) 条子命令）。\n\n文件：\(path)\n\n若某仓库仍有**项目级** `.cursor/hooks.json` 且其中含有本工具，其优先级可能更高，需在该项目内同步删除或合并。"
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
