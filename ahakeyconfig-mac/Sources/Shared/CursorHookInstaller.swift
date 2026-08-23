import Foundation

/// Cursor hooks.json 的结构化安装/迁移 seam。
public enum CursorHookInstaller {
    public static let marker = "--ahakey-cursor-hook-v1"
    public static let installedEvents = [
        "sessionStart",
        "sessionEnd",
        "preToolUse",
        "postToolUse",
        "stop",
    ]

    public static func install(
        in settings: [String: Any],
        agentCommand: String
    ) -> [String: Any] {
        var result = uninstall(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for event in installedEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            let timeout = event == "preToolUse" ? 20 : 10
            entries.append([
                "command": "\(agentCommand) hook \(event) \(marker)",
                "timeout": timeout,
                "failClosed": false,
            ])
            hooks[event] = entries
        }

        result["version"] = result["version"] ?? 1
        result["hooks"] = hooks
        return result
    }

    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for event in Array(hooks.keys) {
            guard let entries = hooks[event] as? [[String: Any]] else { continue }
            let remaining = entries.filter {
                !isManagedCommand(($0["command"] as? String) ?? "")
            }
            if remaining.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = remaining
            }
        }

        result["hooks"] = hooks
        return result
    }

    public static func isManagedCommand(_ command: String) -> Bool {
        if command.contains(marker) { return true }
        let executablePattern = #"(^|[/\s'"])ahakeyconfig-agent(?=$|[\s'"])|(^|[/\s'"])ahakey-state(?=$|[\s'"])"#
        return command.range(of: executablePattern, options: .regularExpression) != nil
    }
}
