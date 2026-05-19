import Foundation

/// Claude Code / Cursor / Codex / Kimi Code CLI hook 客户端
///
/// 作为 `ahakeyconfig-agent hook <EventName>` 子命令运行，被 IDE exec。
/// 通过 Unix socket 把事件通知到常驻 agent daemon，并在 **工具批准** 类场景下
/// 根据键盘拨杆状态向 stdout 输出各 IDE 所需的决策 JSON。
///
/// - Claude Code `PermissionRequest`：见 Apple hook 输出示例（`hookSpecificOutput`…）。
/// - Cursor `preToolUse` / `beforeShellExecution` / `beforeMCPExecution`：stdout 为
///   `{ "permission": "allow" | "deny" | "ask", ... }`（见 Cursor Hooks 文档）。
///   拨杆为 0 时还会同步 `~/.cursor/cli-config.json`（CLI 权限）与 `~/.cursor/permissions.json` 的 `terminalAllowlist`（IDE TUI 白名单，二者分离；非 0 时恢复快照）。
/// - Codex `PermissionRequest`：Codex 0.125 inline TOML hooks 需要 stdout JSON；自动档输出
///   `behavior=allow`，手动档只回 hookEventName，让 Codex 继续走自己的确认链（Codex 不支持 Claude 的 `ask`）。
/// - Kimi Code CLI：**`hooks/runner.py` 只对 `permissionDecision == "deny"` 拦工具**。交互跳过 Shell 批准靠 **`default_yolo`/`/yolo`**。**拨杆→`default_yolo` 磁盘同步**在可读拨杆时于 `PreToolUse` 内完成；已在跑的 kimi 会话请执行 **`/reload`**（会再次 `load_config()`），**不比退出 kimi 更重**——无法从子进程改写父进程内存中的 `approval.set_yolo`。
enum HookClient {
    /// 与 LED / 协议 `sendState` 对应；批准类查询统一用 `permissionLedValue`。
    private static let permissionLedValue: UInt8 = 1

    private enum EventMode {
        /// 只发 `cmd: state`（无关批准）。
        case fireAndForgetState(UInt8)
        /// Claude：`PermissionRequest` → `hookSpecificOutput` + 拨杆。
        case claudePermissionRequest
        /// Cursor：从 stdin 读 JSON，stdout 回 `permission` 字段 + 拨杆。
        case cursorToolPermission
        /// Codex：发状态并输出空 JSON，保持 command hook 输出合法。
        case codexState(UInt8)
        /// Codex：`PermissionRequest` → 自动档 allow；手动档交回 Codex。
        case codexPermissionRequest
        /// Kimi：`PreToolUse` → （1）可读拨杆则同步 **`default_yolo`** 磁盘项；（2）上游仅 **`deny`** 有特殊语义——自动/手动 stdout 仍为空。
        case kimiPreToolPermission
    }

    private static let eventMap: [String: EventMode] = [
        "Notification": .fireAndForgetState(0),
        "PermissionRequest": .claudePermissionRequest,
        "PostToolUse": .fireAndForgetState(2),
        "PreToolUse": .fireAndForgetState(3),
        "SessionStart": .fireAndForgetState(4),
        "Stop": .fireAndForgetState(5),
        "TaskCompleted": .fireAndForgetState(6),
        "UserPromptSubmit": .fireAndForgetState(7),
        "SessionEnd": .fireAndForgetState(8),

        "sessionStart": .fireAndForgetState(4),
        "sessionEnd": .fireAndForgetState(8),
        "postToolUse": .fireAndForgetState(2),
        "stop": .fireAndForgetState(5),
        "preToolUse": .cursorToolPermission,
        "beforeShellExecution": .cursorToolPermission,
        "beforeMCPExecution": .cursorToolPermission,

        "CodexSessionStart": .codexState(4),
        "CodexPostToolUse": .codexState(2),
        "CodexPreToolUse": .codexState(3),
        "CodexUserPromptSubmit": .codexState(7),
        "CodexStop": .codexState(5),
        "CodexPermissionRequest": .codexPermissionRequest,

        "KimiNotification": .fireAndForgetState(0),
        "KimiSessionStart": .fireAndForgetState(4),
        "KimiSessionEnd": .fireAndForgetState(8),
        "KimiPreToolUse": .kimiPreToolPermission,
        "KimiPostToolUse": .fireAndForgetState(2),
        "KimiUserPromptSubmit": .fireAndForgetState(7),
        "KimiStop": .fireAndForgetState(5),
    ]

    private static let socketPath = "/tmp/ahakey.sock"
    private static let stateRequestTimeout: Double = 2.0
    /// 读拨杆 + BLE 可能略慢，批准路径单独放宽。
    private static let permissionRequestTimeout: Double = 5.0

    /// 诊断日志 `ts`：本地时区，`HH` 为 24 小时制（`en_US_POSIX` 避免随地区变成 12 小时制）。
    private static let diagnosticTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// 返回进程退出码。Hook 子进程以 0 表示成功；Cursor 上 exit 2 等同 deny（我们优先 stdout JSON）。
    static func run(event: String) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        guard let mode = eventMap[event] else {
            FileHandle.standardError.write(
                Data("[ahakey-hook] unknown event: \(event)\n".utf8)
            )
            return 0
        }

        switch mode {
        case .fireAndForgetState(let v):
            handleFireAndForgetState(stateValue: v)
        case .claudePermissionRequest:
            handleClaudePermissionRequest()
        case .cursorToolPermission:
            handleCursorToolPermission(hookEvent: event)
        case .codexState(let v):
            handleCodexState(stateValue: v)
        case .codexPermissionRequest:
            handleCodexPermissionRequest()
        case .kimiPreToolPermission:
            handleKimiPreToolPermission()
        }
        return 0
    }

    // MARK: - Event handlers

    private static func handleFireAndForgetState(stateValue: UInt8) {
        let request: [String: Any] = ["cmd": "state", "value": Int(stateValue)]
        _ = sendJsonRequest(request, timeout: stateRequestTimeout)
    }

    private static func handleCodexState(stateValue: UInt8) {
        let stdinData = readAllStdinSilently()
        let ctx = parseStdinContext(stdinData, label: "Codex")
        let request: [String: Any]
        switch stateValue {
        case 2:
            request = ["cmd": "state_with_reset", "value": Int(stateValue), "resetValue": 4, "delayMs": 900]
        case 7:
            request = ["cmd": "state_with_reset", "value": Int(stateValue), "resetValue": 4, "delayMs": 1200]
        default:
            request = ["cmd": "state", "value": Int(stateValue)]
        }
        let reply = sendJsonRequest(request, timeout: stateRequestTimeout)
        appendCodexHookLog(
            hookEvent: ctx["hook_event_name"] as? String,
            agentEvent: codexAgentEventName(forStateValue: stateValue),
            stateValue: stateValue,
            toolContext: ctx,
            reply: reply,
            switchState: intValue(reply?["switchState"]),
            decision: nil
        )
        print("{}")
    }

    // MARK: Claude PermissionRequest

    private static func handleClaudePermissionRequest() {
        let stdinData = readAllStdinSilently()
        let ctx = parseStdinContext(stdinData, label: "Claude")
        let request: [String: Any] = ["cmd": "permission", "value": Int(permissionLedValue)]
        let reply = sendJsonRequest(request, timeout: permissionRequestTimeout)
        let switchState = intValue(reply?["switchState"])
        let isAuto = switchState == 0
        let behavior: String
        if isAuto {
            behavior = "allow"
        } else {
            emitPermissionStderr(
                ide: "Claude", hookName: "PermissionRequest",
                reply: reply, switchState: switchState
            )
            behavior = "ask"
        }

        let out: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": behavior],
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        appendDiagnostic(
            ide: "claude", hookEvent: "PermissionRequest",
            toolContext: ctx,
            reply: reply, switchState: switchState, isAuto: isAuto,
            claudeBehavior: behavior, cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: nil
        )
    }

    // MARK: Cursor preToolUse / beforeShell* / beforeMCP*

    private static func handleCursorToolPermission(hookEvent: String) {
        let stdinData = readAllStdinSilently()
        let ctx = parseStdinContext(stdinData, label: "Cursor")
        let request: [String: Any] = ["cmd": "permission", "value": Int(permissionLedValue)]
        let reply = sendJsonRequest(request, timeout: permissionRequestTimeout)
        let switchState = intValue(reply?["switchState"])
        let isAuto = switchState == 0
        let perm: String
        if isAuto {
            perm = "allow"
        } else {
            emitPermissionStderr(
                ide: "Cursor", hookName: hookEvent,
                reply: reply, switchState: switchState
            )
            perm = "ask"
        }

        // 仅当能读到有效拨杆时：① cli-config（CLI 权限）② permissions.json 的 terminalAllowlist（IDE TUI「Not in allowlist」层，与 cli-config 不共用）。
        if let s = switchState {
            let auto = s == 0
            CursorCliLeverSync.apply(switchStateAuto: auto)
            CursorPermissionsJsonLeverSync.apply(switchStateAuto: auto)
        }

        let out: [String: Any] = [
            "permission": perm,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            // 单行 JSON，与 Cursor 示例一致
            print(str)
        }

        let cursorDebug = buildCursorHookDebug(
            stdinData: stdinData,
            commandPreview: ctx["commandPreview"] as? String
        )
        appendDiagnostic(
            ide: "cursor", hookEvent: hookEvent,
            toolContext: ctx,
            reply: reply, switchState: switchState, isAuto: isAuto,
            claudeBehavior: nil, cursorPermission: perm,
            cursorDebug: cursorDebug,
            kimiPreToolDecision: nil
        )
    }

    // MARK: Codex PermissionRequest

    private static func handleCodexPermissionRequest() {
        let stdinData = readAllStdinSilently()
        let ctx = parseStdinContext(stdinData, label: "Codex")
        let request: [String: Any] = ["cmd": "permission", "value": Int(permissionLedValue)]
        let reply = sendJsonRequest(request, timeout: permissionRequestTimeout)
        let switchState = intValue(reply?["switchState"])
        let isAuto = switchState == 0

        if !isAuto {
            emitPermissionStderr(
                ide: "Codex", hookName: "PermissionRequest",
                reply: reply, switchState: switchState
            )
        }

        var hookOut: [String: Any] = [
            "hookEventName": "PermissionRequest",
        ]
        if isAuto {
            hookOut["decision"] = ["behavior": "allow"]
        }
        appendCodexHookLog(
            hookEvent: "PermissionRequest",
            agentEvent: "CodexPermissionRequest",
            stateValue: permissionLedValue,
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            decision: isAuto ? "allow" : "pass_through"
        )
        let out: [String: Any] = [
            "hookSpecificOutput": hookOut,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        appendDiagnostic(
            ide: "codex", hookEvent: "PermissionRequest",
            toolContext: ctx,
            reply: reply, switchState: switchState, isAuto: isAuto,
            claudeBehavior: nil, cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: nil
        )
    }

    // MARK: Kimi PreToolUse

    private static func handleKimiPreToolPermission() {
        let stdinData = readAllStdinSilently()
        let ctx = parseStdinContext(stdinData, label: "Kimi")
        KimiHookDebugLog.append(event: "kimi_PreToolUse_start", details: [
            "stdinBytes": stdinData.count,
            "toolPreview": ctx,
            "hintLogFile": KimiHookDebugLog.logPath,
        ])
        KimiHookDebugLog.stderrLine("PreToolUse hook start bytes=\(stdinData.count); full log=\(KimiHookDebugLog.logPath)")

        let request: [String: Any] = ["cmd": "permission", "value": Int(permissionLedValue)]
        let reply = sendJsonRequest(request, timeout: permissionRequestTimeout)
        let switchState = intValue(reply?["switchState"])
        let isAuto = switchState == 0

        KimiHookDebugLog.append(event: "kimi_PreToolUse_agent_reply", details: [
            "agentReplyNil": reply == nil,
            "switchState": switchState.map { $0 } ?? NSNull(),
            "computedIsAuto": isAuto,
            "replyPreview": kimiReplyPreview(reply),
        ])
        KimiHookDebugLog.stderrLine("agent socket reply: switchState=\(switchState.map { String($0) } ?? "nil") isAuto=\(isAuto)")

        // kimi_cli/hooks/runner.py：仅当 permissionDecision=="deny" 时 block；否则仍可能走 Shell 交互审批（与 default_yolo / /yolo 关联）。
        let stdoutPayload: String
        let kimiPreToolDecision: String
        if isAuto {
            // 空 stdout：与「不写 deny JSON」等价，且不把冗余 JSON 注入 kimi 钩子上下文。
            stdoutPayload = ""
            kimiPreToolDecision = "auto_no_stdout_no_veto"
        } else {
            stdoutPayload = ""
            kimiPreToolDecision = "manual_lever_no_stdout"
            emitPermissionStderr(
                ide: "Kimi", hookName: "PreToolUse",
                reply: reply, switchState: switchState
            )
        }

        let kimiProbeInitial = KimiConfigDiagnostic.snapshotForLog()
        KimiHookDebugLog.append(event: "kimi_PreToolUse_probe_before_lever_sync", details: [
            "kimiLeverDebug_preview": kimiProbeInitial,
            "switchStateNil": switchState == nil,
            "kimiRunnerNote": "upstream_kimi_hooks_runner_only_handles_permissionDecision_deny",
        ])
        var leverSnapshotForLog = kimiProbeInitial
        if switchState == nil {
            KimiHookDebugLog.stderrLine("no switchState from agent → skipped default_yolo sync; kimiPreTool=\(kimiPreToolDecision); check BLE/agent")
        } else {
            KimiConfigLeverSync.apply(switchStateAuto: isAuto)
            leverSnapshotForLog = KimiConfigLeverSync.diagnosticSnapshotForLog()
            KimiHookDebugLog.append(event: "kimi_PreToolUse_after_default_yolo_disk_sync", details: leverSnapshotForLog)
            KimiHookDebugLog.stderrLine(
                "default_yolo synced on disk (\(isAuto ? "true" : "false")); if kimi is already running: enter /reload in that session — no quit needed."
            )
            let yoloSnippet: String
            if let v = leverSnapshotForLog["default_yolo_valueSnippet"], !(v is NSNull) {
                yoloSnippet = String(describing: v)
            } else {
                yoloSnippet = "(unset/absent)"
            }
            KimiHookDebugLog.stderrLine("on-disk default_yolo now reads \(yoloSnippet); /reload picks it up.")
        }
        // 不向 stdout 打换行：`print()` 也会产生一行，易被 kimi 当作「钩子有输出」。
        if !stdoutPayload.isEmpty {
            FileHandle.standardOutput.write(Data(stdoutPayload.utf8))
        }
        KimiHookDebugLog.append(event: "kimi_PreToolUse_stdout", details: [
            "kimiDecision": kimiPreToolDecision,
            "stdoutChars": stdoutPayload.count,
            "hint": "kimi-cli 读 default_yolo 在 KimiCLI.create/load_config；已开着的会话请输入 /reload 即可（不必退出 kimi）。PreToolUse 仍仅 deny 会拦工具；default_yolo 管交互批准层。",
        ])
        KimiHookDebugLog.stderrLine("stdout chars=\(stdoutPayload.count) decision=\(kimiPreToolDecision)")

        appendDiagnostic(
            ide: "kimi", hookEvent: "PreToolUse",
            toolContext: ctx,
            reply: reply, switchState: switchState, isAuto: isAuto,
            claudeBehavior: nil, cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: kimiPreToolDecision,
            kimiLeverDebug: KimiConfigLeverSync.diagnosticSnapshotForLog()
        )
    }

    /// 仅摘要 agent 回包字段，不把整包写进磁盘以免过大。
    private static func kimiReplyPreview(_ reply: [String: Any]?) -> [String: Any] {
        guard let reply else {
            return ["nil": true]
        }
        var o: [String: Any] = [:]
        if let sv = reply["switchState"] {
            o["switchState"] = String(String(describing: sv).prefix(48))
        }
        if let ok = reply["ok"] {
            o["ok"] = ok
        }
        if let err = reply["error"] as? String {
            o["error"] = String(err.prefix(160))
        }
        return o
    }

    private static func emitPermissionStderr(
        ide: String, hookName: String,
        reply: [String: Any]?, switchState: Int?
    ) {
        if switchState == nil, reply == nil {
            let msg = "[ahakey-hook] \(ide) \(hookName): agent 无回包或 Unix socket 失败（/tmp/ahakey.sock 连不上/超时，超时 \(Int(permissionRequestTimeout))s）。"
                + "请确认 LaunchAgent 里 ahakeyconfig-agent 在跑、且蓝牙已选「由 Agent 占用」并连上键盘。\n"
            FileHandle.standardError.write(Data(msg.utf8))
        } else if switchState == nil, reply != nil {
            let msg = "[ahakey-hook] \(ide) \(hookName): 回包无有效 switchState（需 BLE 已连且能读到拨杆 0=自动批准），将按交回用户/终端处理。\n"
            FileHandle.standardError.write(Data(msg.utf8))
        } else if let s = switchState, s != 0 {
            let msg = "[ahakey-hook] \(ide) \(hookName): 拨杆 switchState=\(s)（非 0），不自动批准。\n"
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    private static func codexAgentEventName(forStateValue stateValue: UInt8) -> String {
        switch stateValue {
        case 2: return "CodexPostToolUse"
        case 3: return "CodexPreToolUse"
        case 4: return "CodexSessionStart"
        case 5: return "CodexStop"
        case 7: return "CodexUserPromptSubmit"
        default: return "CodexState\(stateValue)"
        }
    }

    private static func appendCodexHookLog(
        hookEvent: String?,
        agentEvent: String,
        stateValue: UInt8,
        toolContext: [String: Any],
        reply: [String: Any]?,
        switchState: Int?,
        decision: String?
    ) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = dir.appendingPathComponent("codex-hook.log")

        var lineObj: [String: Any] = [
            "ts": diagnosticTimestampFormatter.string(from: Date()),
            "agentEvent": agentEvent,
            "hookEvent": hookEvent ?? NSNull(),
            "stateValue": Int(stateValue),
            "agentReply": reply == nil ? false : true,
            "switchState": switchState.map { $0 } ?? NSNull(),
            "tool": toolContext,
        ]
        if let decision { lineObj["decision"] = decision }

        guard let data = try? JSONSerialization.data(withJSONObject: lineObj, options: []),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        appendLine(line, to: fileURL)
    }

    /// 从各 IDE 经 stdin 传入的 JSON 里取可安全写入日志的短文本（不记录大段 tool_input 以免泄密）。
    private static func parseStdinContext(_ data: Data, label: String) -> [String: Any] {
        var out: [String: Any] = [
            "stdinBytes": data.count,
            "parser": label,
        ]
        guard !data.isEmpty,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return out
        }
        if let t = obj["tool_name"] as? String {
            out["tool_name"] = t
        }
        if let c = obj["command"] as? String {
            out["commandPreview"] = String(c.prefix(120))
        }
        if out["tool_name"] == nil, let t = obj["name"] as? String {
            out["name"] = t
        }
        if let he = obj["hook_event_name"] as? String {
            out["hook_event_name"] = he
        }
        if let sid = obj["session_id"] as? String {
            out["session_id_short"] = String(sid.prefix(16))
        }
        if let cw = obj["cwd"] as? String {
            out["cwdPreview"] = String(cw.prefix(120))
        }
        return out
    }

    // MARK: Cursor 诊断块（permission-request.log → `cursorDebug`）

    private static let cursorStdinLogKeys: [String] = [
        "cursorVersion", "cursor_version", "appVersion", "app_version", "version",
        "workspacePath", "workspace_path", "workspaceFolders", "workspace_folders", "workspaceRoot",
        "cwd", "root", "shell", "shell_type", "sessionId", "conversation_id",
    ]

    private static func buildCursorHookDebug(stdinData: Data, commandPreview: String?) -> [String: Any] {
        var out: [String: Any] = [
            "userCliConfig": CursorCliLeverSync.diagnosticSnapshotForLog(),
            "userPermissionsJson": CursorPermissionsJsonLeverSync.diagnosticSnapshotForLog(),
            "note": "IDE「Not in allowlist」用 ~/.cursor/permissions.json 的 terminalAllowlist，与 userCliConfig（cli-config=CLI）分离；见 cursor.com/docs/reference/permissions",
            "stdinFields": cursorStdinDebugFields(stdinData),
            "processEnvCursorVscode": cursorRelatedEnvForLog(),
        ]
        if let cd = inferredCdPathFromShellCommand(commandPreview) {
            out["inferredCdPath"] = cd
            let proj = (cd as NSString).appendingPathComponent(".cursor/cli.json")
            out["projectCliJsonPath"] = proj
            out["projectCliJsonExists"] = FileManager.default.fileExists(atPath: proj)
        }
        return out
    }

    private static func cursorStdinDebugFields(_ data: Data) -> [String: Any] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["parse": "empty_or_invalid_json"]
        }
        var o: [String: Any] = [:]
        for k in cursorStdinLogKeys {
            guard let v = obj[k] else { continue }
            o[k] = stringifyDebugValue(v, maxLen: 220)
        }
        if o.isEmpty { o["note"] = "no_whitelisted_keys_in_stdin" }
        return o
    }

    private static func stringifyDebugValue(_ v: Any, maxLen: Int) -> String {
        if let s = v as? String { return String(s.prefix(maxLen)) }
        if let n = v as? NSNumber { return n.stringValue }
        if let a = v as? [String] {
            return String(a.prefix(12).joined(separator: ", ").prefix(maxLen))
        }
        return String(String(describing: v).prefix(maxLen))
    }

    private static func cursorRelatedEnvForLog() -> [String: Any] {
        var o: [String: Any] = [:]
        for (k, v) in ProcessInfo.processInfo.environment.sorted(by: { $0.key < $1.key }) {
            let ku = k.uppercased()
            guard ku.contains("CURSOR") || ku.hasPrefix("VSCODE_") || ku == "TERM" else { continue }
            o[k] = String(v.prefix(200))
            if o.count >= 32 { break }
        }
        return o
    }

    /// 从 `cd /a/b && ...` 取首段目录，用于判断项目下 `.cursor/cli.json` 是否存在。
    private static func inferredCdPathFromShellCommand(_ command: String?) -> String? {
        guard let raw = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("cd ") else { return nil }
        var rest = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if let r = rest.range(of: " && ") { rest = String(rest[..<r.lowerBound]) }
        if let r = rest.firstIndex(of: ";") { rest = String(rest[..<r]) }
        if let r = rest.firstIndex(of: "|") { rest = String(rest[..<r]) }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("\"") {
            let drop = rest.dropFirst()
            if let end = drop.firstIndex(of: "\"") {
                return String(drop[..<end])
            }
        }
        // 非引号：取到空白或行尾
        if let sp = rest.firstIndex(where: { $0.isWhitespace }) {
            return String(rest[..<sp])
        }
        return rest.isEmpty ? nil : rest
    }

    private static func appendDiagnostic(
        ide: String,
        hookEvent: String,
        toolContext: [String: Any],
        reply: [String: Any]?,
        switchState: Int?,
        isAuto: Bool,
        claudeBehavior: String?,
        cursorPermission: String?,
        cursorDebug: [String: Any]? = nil,
        kimiPreToolDecision: String? = nil,
        kimiLeverDebug: [String: Any]? = nil
    ) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let fileURL = dir.appendingPathComponent("permission-request.log")
        let path = fileURL.path

        let diagnostic: String
        if reply == nil {
            diagnostic = "no_agent_reply"
        } else if switchState == nil {
            diagnostic = "no_switch_in_reply"
        } else if isAuto {
            diagnostic = "allow"
        } else {
            diagnostic = "ask"
        }
        var lineObj: [String: Any] = [
            "ts": diagnosticTimestampFormatter.string(from: Date()),
            "ide": ide,
            "hookEvent": hookEvent,
            "switchState": switchState.map { $0 } ?? NSNull(),
            "isAuto": isAuto,
            "agentReply": reply == nil ? false : true,
            "diagnostic": diagnostic,
            "tool": toolContext,
        ]
        if let b = claudeBehavior { lineObj["claudeBehavior"] = b }
        if let p = cursorPermission { lineObj["cursorPermission"] = p }
        if let c = cursorDebug { lineObj["cursorDebug"] = c }
        if let k = kimiPreToolDecision { lineObj["kimiPreToolDecision"] = k }
        if let kd = kimiLeverDebug { lineObj["kimiLeverDebug"] = kd }

        guard let data = try? JSONSerialization.data(withJSONObject: lineObj, options: []),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        appendLine(line, to: URL(fileURLWithPath: path))
    }

    private static func appendLine(_ line: String, to fileURL: URL) {
        guard let out = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? out.write(to: fileURL, options: .atomic)
            return
        }
        if let h = try? FileHandle(forWritingTo: fileURL) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            h.write(out)
        }
    }

    @discardableResult
    private static func readAllStdinSilently() -> Data {
        let handle = FileHandle.standardInput
        return (try? handle.readToEnd()) ?? Data()
    }

    // MARK: - Unix socket client

    private static func sendJsonRequest(_ dict: [String: Any], timeout: Double) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var tv = timeval(
            tv_sec: __darwin_time_t(timeout),
            tv_usec: suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let dst = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                _ = strcpy(dst, src)
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLen)
            }
        }
        guard connected == 0 else { return nil }

        guard var payload = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            return nil
        }
        payload.append(0x0A)
        let wrote = payload.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return write(fd, base, ptr.count)
        }
        guard wrote >= 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 1024 * 4)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { return nil }
        let slice = Data(buf[0 ..< Int(n)])
        return (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any]
    }

    private static func intValue(_ v: Any?) -> Int? {
        switch v {
        case let i as Int:
            return i
        case let n as NSNumber:
            return n.intValue
        case let d as Double:
            return Int(d)
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }
}
