import Foundation

/// Claude Code / Cursor hook 客户端
///
/// 作为 `ahakeyconfig-agent hook <EventName>` 子命令运行，被 IDE exec。
/// 通过 Unix socket 把事件通知到常驻 agent daemon，并在 **工具批准** 类场景下
/// 根据键盘拨杆状态向 stdout 输出各 IDE 所需的决策 JSON。
///
/// - Claude Code `PermissionRequest`：见 Apple hook 输出示例（`hookSpecificOutput`…）。
/// - Cursor `preToolUse` / `beforeShellExecution` / `beforeMCPExecution`：stdout 为
///   `{ "permission": "allow" | "deny" | "ask", ... }`（见 Cursor Hooks 文档）。
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
    ]

    private static let socketPath = "/tmp/ahakey.sock"
    private static let stateRequestTimeout: Double = 2.0
    /// 读拨杆 + BLE 可能略慢，批准路径单独放宽。
    private static let permissionRequestTimeout: Double = 5.0

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
        }
        return 0
    }

    // MARK: - Event handlers

    private static func handleFireAndForgetState(stateValue: UInt8) {
        let request: [String: Any] = ["cmd": "state", "value": Int(stateValue)]
        _ = sendJsonRequest(request, timeout: stateRequestTimeout)
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
            claudeBehavior: behavior, cursorPermission: nil
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
            perm = "deny"
        }

        let out: [String: Any] = [
            "permission": perm,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            // 单行 JSON，与 Cursor 示例一致
            print(str)
        }

        appendDiagnostic(
            ide: "cursor", hookEvent: hookEvent,
            toolContext: ctx,
            reply: reply, switchState: switchState, isAuto: isAuto,
            claudeBehavior: nil, cursorPermission: perm
        )
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
        return out
    }

    private static func appendDiagnostic(
        ide: String,
        hookEvent: String,
        toolContext: [String: Any],
        reply: [String: Any]?,
        switchState: Int?,
        isAuto: Bool,
        claudeBehavior: String?,
        cursorPermission: String?
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
            "ts": ISO8601DateFormatter().string(from: Date()),
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

        guard let data = try? JSONSerialization.data(withJSONObject: lineObj, options: []),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        guard let out = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: path) {
            try? out.write(to: URL(fileURLWithPath: path), options: .atomic)
            return
        }
        if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
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
