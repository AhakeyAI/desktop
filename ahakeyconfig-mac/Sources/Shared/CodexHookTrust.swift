import CryptoKit
import Foundation

/// Codex（约 0.13x 起）引入 hook 信任机制：`~/.codex/config.toml` 里的 hook 只有在
/// `[hooks.state."<configPath>:<event>:<group>:<index>"]` 中记录了与当前内容匹配的
/// `trusted_hash` 才会执行；否则 exec 模式静默跳过，TUI 启动时要求人工
/// 「Trust all and continue」。AhaKey 每次安装/更新 hooks 都会改动内容、使旧信任失效，
/// 因此安装器必须同步重写与所装内容匹配的 trusted_hash（等价于用户在 TUI 里点信任）。
///
/// 哈希算法与 codex 保持一致（codex-rs/hooks/src/engine/discovery.rs `command_hook_hash`
/// + codex-rs/config/src/fingerprint.rs `version_for_toml`）：对归一化 hook 身份
/// （event_name + matcher + 单个 command handler）做键排序的紧凑 JSON，取 SHA-256。
public enum CodexHookTrust {
    /// codex 持久化状态时使用的事件标签（snake_case）。
    private static let eventLabels: [String: String] = [
        "PreToolUse": "pre_tool_use",
        "PermissionRequest": "permission_request",
        "PostToolUse": "post_tool_use",
        "PreCompact": "pre_compact",
        "PostCompact": "post_compact",
        "SessionStart": "session_start",
        "SessionEnd": "session_end",
        "UserPromptSubmit": "user_prompt_submit",
        "SubagentStart": "subagent_start",
        "SubagentStop": "subagent_stop",
        "Stop": "stop",
    ]

    /// `[hooks.state]` 表键：`<configPath>:<eventLabel>:<groupIndex>:<handlerIndex>`。
    public static func stateKey(configPath: String, event: String, groupIndex: Int = 0, handlerIndex: Int = 0) -> String? {
        guard let label = eventLabels[event] else { return nil }
        return "\(configPath):\(label):\(groupIndex):\(handlerIndex)"
    }

    /// 与 codex `command_hook_hash` 等价的 trusted_hash（含 "sha256:" 前缀）。
    /// command/timeout 必须是写入 config.toml 的 hook 原始值（TOML 反转义之后）。
    public static func trustedHash(event: String, matcher: String, command: String, timeout: Int) -> String? {
        guard let label = eventLabels[event] else { return nil }
        // codex 先把归一化身份序列化为 TOML 再转 JSON：TOML 序列化会丢弃 None 字段
        // （commandWindows/statusMessage/additionalContextLimit），因此这里直接不含这些键。
        let handler: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": timeout,
            "async": false,
        ]
        var identity: [String: Any] = [
            "event_name": label,
            "hooks": [handler],
        ]
        // Codex drops ignored matchers from the normalized identity for these events.
        // https://learn.chatgpt.com/docs/hooks#matcher-patterns
        if !["UserPromptSubmit", "Stop", "Interrupt"].contains(event) {
            identity["matcher"] = matcher
        }
        // serde_json 紧凑输出不转义正斜杠；Foundation 默认会把 "/" 转成 "\/"，必须关闭。
        guard let data = try? JSONSerialization.data(
            withJSONObject: identity,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static let blockStart = "# BEGIN AhaKey Codex Hooks"
    public static let blockEnd = "# END AhaKey Codex Hooks"

    /// The app and integration harness use this same command builder and installer.
    public static func installAgentHooks(in config: String, configPath: String, agentBinaryPath: String) throws -> String {
        let events: [(event: String, timeout: Int)] = [
            ("SessionStart", 10), ("PostToolUse", 10), ("PreToolUse", 20),
            ("PermissionRequest", 20), ("UserPromptSubmit", 10), ("Stop", 10),
        ]
        func shellQuote(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var lines = [blockStart, "# Managed by AhaKey Studio."]
        var hashes: [(event: String, hash: String)] = []
        for item in events {
            let command = "/bin/zsh -lc \(shellQuote("\(shellQuote(agentBinaryPath)) hook Codex\(item.event)"))"
            lines += ["", "[[hooks.\(item.event)]]"]
            if !["UserPromptSubmit", "Stop"].contains(item.event) { lines.append("matcher = \"\"") }
            lines += ["[[hooks.\(item.event).hooks]]", "type = \"command\"",
                      "command = \(quoted(command))", "timeout = \(item.timeout)"]
            guard let hash = trustedHash(event: item.event, matcher: "", command: command, timeout: item.timeout)
            else { throw TomlPolicyLocator.Failure.unsupported("无法计算 hook 信任哈希") }
            hashes.append((item.event, hash))
        }
        lines.append(blockEnd)
        return try install(in: config, configPath: configPath, block: lines.joined(separator: "\n"), hashes: hashes)
    }

    /// Install after removing the previous managed groups. Existing user groups keep
    /// their trust records; AhaKey's keys use the appended groups' actual indices.
    public static func install(in config: String, configPath: String, block: String,
                               hashes: [(event: String, hash: String)]) throws -> String {
        let clean = try removingManagedHooks(in: config, configPath: configPath)
        let layout = try Layout(clean)
        let entries = hashes.compactMap { item -> (key: String, hash: String)? in
            guard let key = stateKey(configPath: configPath, event: item.event,
                                     groupIndex: layout.groupCounts[item.event, default: 0]) else { return nil }
            return (key, item.hash)
        }
        let combined = clean.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block + "\n"
        return try upsertTrustEntries(in: combined, configPath: configPath, entries: entries)
    }

    /// Remove only groups inside our real comment markers. User groups after a
    /// removed group shift index, so rename their state keys without changing hashes/enabled.
    public static func removingManagedHooks(in config: String, configPath: String) throws -> String {
        let layout = try Layout(config)
        guard !layout.managedRanges.isEmpty else { return config }
        var edits = layout.managedRanges.map { Edit(range: $0, replacement: "") }
        var retainedCounts: [String: Int] = [:]
        var mapping: [String: String] = [:]
        var removed = Set<String>()
        for group in layout.groups {
            guard let old = stateKey(configPath: configPath, event: group.event, groupIndex: group.index) else { continue }
            let oldPrefix = String(old.dropLast()) // keep the handler-index separator
            if layout.isManaged(group.offset) {
                removed.insert(oldPrefix)
            } else {
                let index = retainedCounts[group.event, default: 0]
                retainedCounts[group.event] = index + 1
                let new = stateKey(configPath: configPath, event: group.event, groupIndex: index)!
                mapping[oldPrefix] = String(new.dropLast())
            }
        }
        for table in layout.trustTables {
            guard !layout.isManaged(table.header.range.lowerBound) else { continue }
            if removed.contains(where: { table.key.hasPrefix($0) }) {
                edits += table.statements.map { Edit(range: $0.range, replacement: "") }
            } else if let old = mapping.keys.first(where: { table.key.hasPrefix($0) }), let new = mapping[old], old != new {
                let key = new + table.key.dropFirst(old.count)
                edits.append(Edit(range: table.header.range, replacement: "[hooks.state.\(quoted(key))]"))
            }
        }
        return applying(edits, to: config)
    }

    public static func upsertTrustEntries(in config: String, configPath: String,
                                         entries: [(key: String, hash: String)]) throws -> String {
        var result = try removeTrustEntries(in: config, keys: Set(entries.map(\.key)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for entry in entries {
            result += "\n\n[hooks.state.\(quoted(entry.key))]\ntrusted_hash = \(quoted(entry.hash))"
        }
        return result.isEmpty ? "" : result + "\n"
    }

    public static func removeTrustEntries(in config: String, keys: Set<String>) throws -> String {
        let layout = try Layout(config)
        let edits = layout.trustTables.filter { keys.contains($0.key) }.flatMap { table in
            table.statements.map { Edit(range: $0.range, replacement: "") }
        }
        return applying(edits, to: config)
    }

    private static func quoted(_ value: String) -> String {
        // JSON basic-string escaping is also valid TOML escaping.
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private struct Edit {
        let range: Range<Int>
        let replacement: String
    }

    private static func applying(_ edits: [Edit], to config: String) -> String {
        var bytes = Array(config.utf8)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.replacement.utf8)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private struct Layout {
        struct Group {
            let event: String
            let index: Int
            let offset: Int
        }
        struct TrustTable {
            let key: String
            let header: TomlPolicyLocator.Statement
            var statements: [TomlPolicyLocator.Statement]
        }
        var groups: [Group] = []
        var groupCounts: [String: Int] = [:]
        var managedRanges: [Range<Int>] = []
        var trustTables: [TrustTable] = []

        func isManaged(_ offset: Int) -> Bool { managedRanges.contains { $0.contains(offset) } }

        init(_ config: String) throws {
            let bytes = Array(config.utf8)
            let statements = try TomlPolicyLocator.statements(in: config)
            var blockOffset: Int?
            var tablePath: [String] = []
            var activeTrustIndex: Int?
            for statement in statements {
                switch statement.kind {
                case .comment:
                    let comment = String(decoding: bytes[statement.range], as: UTF8.self)
                        .trimmingCharacters(in: .whitespaces)
                    if comment == blockStart {
                        guard blockOffset == nil else { throw TomlPolicyLocator.Failure.unsupported("嵌套的 AhaKey hook 标记") }
                        blockOffset = statement.range.lowerBound
                    } else if comment == blockEnd {
                        guard let start = blockOffset else { throw TomlPolicyLocator.Failure.unsupported("缺少 AhaKey hook 起始标记") }
                        managedRanges.append(start..<statement.range.upperBound)
                        blockOffset = nil
                    }
                case let .table(path, isArray):
                    tablePath = path
                    activeTrustIndex = nil
                    if isArray, path.count == 2, path[0] == "hooks" {
                        let event = path[1]
                        let index = groupCounts[event, default: 0]
                        groups.append(Group(event: event, index: index, offset: statement.range.lowerBound))
                        groupCounts[event] = index + 1
                    }
                    if !isArray, path.count == 3, path[0...1] == ["hooks", "state"] {
                        activeTrustIndex = trustTables.count
                        trustTables.append(TrustTable(key: path[2], header: statement, statements: [statement]))
                    }
                case let .assignment(path):
                    // Alternate inline/dotted hook layouts cannot be safely reindexed here.
                    // Refuse them before writing instead of silently guessing group zero.
                    if (tablePath.isEmpty && path.first == "hooks") || tablePath == ["hooks"] || tablePath == ["hooks", "state"] {
                        throw TomlPolicyLocator.Failure.unsupported("请使用 [[hooks.Event]] 与 [hooks.state.\"key\"] 表形式")
                    }
                    if let index = activeTrustIndex { trustTables[index].statements.append(statement) }
                }
            }
            guard blockOffset == nil else { throw TomlPolicyLocator.Failure.unsupported("AhaKey hook 标记未闭合") }
        }
    }
}
