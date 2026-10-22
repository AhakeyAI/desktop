import Foundation

/// Shared by Studio and isolated CLI lifecycle fixtures. Only managed command
/// entries change; user hooks and unrelated settings survive install/removal.
public enum JSONHooksConfiguration {
    public enum Client { case claude, cursor }
    public enum Failure: Error { case malformed, unsafePath }
    public static let claudeEvents = ["Notification", "PermissionRequest", "PreToolUse", "PostToolUse", "Stop", "SubagentStop", "SessionStart", "SessionEnd", "UserPromptSubmit", "TaskCompleted", "PreCompact"]
    public static let cursorEvents = ["sessionStart", "sessionEnd", "preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "beforeSubmitPrompt", "postToolUse", "stop"]

    public static func installing(in settings: [String: Any], client: Client, agentPath: String) throws -> [String: Any] {
        guard agentPath.hasPrefix("/"), !agentPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.unsafePath }
        var result = try removing(in: settings, client: client)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in client == .claude ? claudeEvents : cursorEvents {
            let command = "'" + agentPath.replacingOccurrences(of: "'", with: "'\\''") + "' hook " + event
            var entries = hooks[event] as? [[String: Any]] ?? []
            if client == .claude {
                entries.append(["matcher": "", "hooks": [["type": "command", "command": command]]])
            } else {
                let timeout = event == "beforeSubmitPrompt" ? 30 : (["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "sessionStart"].contains(event) ? 20 : 10)
                entries.append(["command": command, "timeout": timeout])
            }
            hooks[event] = entries
        }
        result["hooks"] = hooks
        if client == .cursor, result["version"] == nil { result["version"] = 1 }
        return result
    }

    public static func removing(in settings: [String: Any], client: Client) throws -> [String: Any] {
        var result = settings
        guard let value = settings["hooks"] else { return result }
        guard var hooks = value as? [String: Any] else { throw Failure.malformed }
        var changed = false
        for event in Array(hooks.keys) {
            guard var entries = hooks[event] as? [[String: Any]] else { throw Failure.malformed }
            let before = entries as NSArray
            if client == .claude {
                var retained: [[String: Any]] = []
                for var entry in entries {
                    guard let commands = entry["hooks"] as? [[String: Any]] else { throw Failure.malformed }
                    let remaining = commands.filter { !owns(($0["command"] as? String) ?? "") }
                    if remaining.count == commands.count { retained.append(entry) }
                    else if !remaining.isEmpty { entry["hooks"] = remaining; retained.append(entry) }
                }
                entries = retained
            } else { entries.removeAll { owns(($0["command"] as? String) ?? "") } }
            guard !before.isEqual(to: entries) else { continue }
            changed = true
            if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
        }
        guard changed else { return settings }
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }

    public static func owns(_ command: String) -> Bool {
        ManagedHookCommand.owns(command, events: claudeEvents + cursorEvents, legacyScript: true)
    }
}

/// Recognizes literal argv only. Mentions in echo, shell pipelines and command
/// substitution never confer ownership of a user's hook.
enum ManagedHookCommand {
    static func owns(_ command: String, events: [String], legacyScript: Bool = false, depth: Int = 0) -> Bool {
        guard depth < 4, command.utf8.count <= 32_768, !command.contains("\n"), !command.contains("\r"), var words = arguments(command), !words.isEmpty else { return false }
        if ["/bin/sh", "/bin/zsh", "/bin/bash"].contains(words[0]) {
            if words.count == 3, ["-c", "-lc", "-fc"].contains(words[1]) {
                return owns(words[2], events: events, legacyScript: legacyScript, depth: depth + 1)
            }
            if legacyScript, words.count == 3, URL(fileURLWithPath: words[1]).lastPathComponent == "ahakey-state.sh", events.contains(words[2]) { return true }
            return false
        }
        if words[0] == "/usr/bin/env" {
            words.removeFirst()
            while words.first?.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil { words.removeFirst() }
        }
        guard let executable = words.first else { return false }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        if legacyScript, name == "ahakey-state.sh", words.count == 2, events.contains(words[1]) { return true }
        return words.count == 3 && words[1] == "hook" && events.contains(words[2]) && ["ahakeyconfig-agent", "ahakey-state"].contains(name)
    }
    /// A bounded recognizer for our literal argv/wrappers, not a shell evaluator.
    /// Substitution, pipelines and redirection never grant removal ownership.
    private static func arguments(_ text: String) -> [String]? {
        var words: [String] = [], word = "", quote: Character?, escaped = false, started = false
        for character in text {
            if escaped { word.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; started = true; continue }
            if let active = quote {
                if character == active { quote = nil }
                else {
                    if active == "\"", character == "$" || character == "`" { return nil }
                    word.append(character)
                }
            } else if character == "'" || character == "\"" { quote = character; started = true }
            else if character.isWhitespace {
                if started { words.append(word); word = ""; started = false }
                if words.count > 128 { return nil }
            } else {
                guard !"$`;|&<>()".contains(character) else { return nil }
                word.append(character); started = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if started { words.append(word) }
        return words
    }
}
