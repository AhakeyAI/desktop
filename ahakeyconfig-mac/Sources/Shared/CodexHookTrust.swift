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
        let identity: [String: Any] = [
            "event_name": label,
            "matcher": matcher,
            "hooks": [handler],
        ]
        // serde_json 紧凑输出不转义正斜杠；Foundation 默认会把 "/" 转成 "\/"，必须关闭。
        guard let data = try? JSONSerialization.data(
            withJSONObject: identity,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 把 AhaKey 管理的 trusted_hash 写入 config 文本；先移除同一 configPath 下的旧条目保证幂等。
    /// 其它来源（项目 hooks.json、插件）的 hooks.state 条目不受影响。
    public static func upsertTrustEntries(in config: String, configPath: String, entries: [(key: String, hash: String)]) -> String {
        var result = removeTrustEntries(in: config, configPath: configPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty else { return result.isEmpty ? "" : result + "\n" }
        for entry in entries {
            if !result.isEmpty { result += "\n" }
            result += "\n[hooks.state.\"\(entry.key)\"]\ntrusted_hash = \"\(entry.hash)\"\n"
        }
        return result
    }

    /// 移除 `[hooks.state."<configPath>:..."]` 表（含表体内容）。
    public static func removeTrustEntries(in config: String, configPath: String) -> String {
        let headerPrefix = "[hooks.state.\"\(configPath):"
        var out: [String] = []
        var skipping = false
        for line in config.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                skipping = trimmed.hasPrefix(headerPrefix)
            }
            if !skipping { out.append(line) }
        }
        return out.joined(separator: "\n")
    }
}
