import Foundation

/// Production installer and isolated CLI tests share this lexical edit. Never
/// consume a provider table merely because it follows an owned [[hooks]] entry.
public enum KimiHooksConfiguration {
    public static let blockStart = "# BEGIN AhaKey Kimi Hooks"
    public static let blockEnd = "# END AhaKey Kimi Hooks"
    public static let events = ["Notification", "SessionStart", "SessionEnd", "PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop"]
    public static let nativeEvents = events + ["PermissionRequest", "PermissionResult"]
    public enum Failure: Error { case malformed, unsafePath }

    public static func installing(in text: String, location: KimiConfigPolicySync.Location, agentPath: String) throws -> String {
        guard location.isValid, agentPath.hasPrefix("/"), !agentPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.unsafePath }
        var result = try removing(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty { result += "\n\n" }
        result += blockStart + "\n# Managed by AhaKey Studio. Kimi lifecycle hooks.\n"
        for event in location.layout == .nativeV2 ? nativeEvents : events {
            var call = "/usr/bin/env AHAKEY_KIMI_LAYOUT=\(location.layout.rawValue)"
            if location.layout == .nativeV2 {
                call += " KIMI_CODE_HOME=\(shellQuote(location.root.path)) AHAKEY_KIMI_APPROVAL_OBSERVATIONS=1"
            }
            call += " \(shellQuote(agentPath)) hook Kimi\(event)"
            let command = "/bin/sh -c \(shellQuote(call))"
            result += "\n[[hooks]]\nevent = \"\(event)\"\nmatcher = \"\"\ncommand = \(tomlQuote(command))\ntimeout = \(event == "PreToolUse" ? 20 : 10)\n"
        }
        result += "\n" + blockEnd + "\n"
        _ = try TomlPolicyLocator.statements(in: result)
        return result
    }

    public static func removing(in text: String) throws -> String {
        let bytes = Array(text.utf8)
        let statements = try TomlPolicyLocator.statements(in: text)
        var ranges: [Range<Int>] = []
        var marked = false
        for item in statements {
            guard case .comment = item.kind else { continue }
            let comment = String(decoding: bytes[item.range], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if comment == blockStart {
                guard !marked else { throw Failure.malformed }
                marked = true; ranges.append(item.range)
            } else if comment == blockEnd {
                guard marked else { throw Failure.malformed }
                marked = false; ranges.append(item.range)
            } else if marked && (comment.hasPrefix("# Managed by AhaKey Studio.") || comment.hasPrefix("# Dial integration is managed by AhaKey Studio.")) {
                ranges.append(item.range)
            }
        }
        guard !marked else { throw Failure.malformed }
        for index in statements.indices {
            guard case .table(let path, let array) = statements[index].kind, path == ["hooks"], array else { continue }
            var end = index + 1
            while end < statements.count {
                if case .table = statements[end].kind { break }
                end += 1
            }
            let fields = statements[(index + 1)..<end]
            let owned = fields.contains { item in
                guard case .assignment(let key) = item.kind, key == ["command"] else { return false }
                guard let command = scalarString(bytes: bytes, statement: item) else { return false }
                return owns(command)
            }
            if owned {
                // Delete the owned header and fields, not comments belonging to
                // surrounding configuration or the next unrelated table.
                ranges.append(statements[index].range)
                ranges += fields.compactMap { item in
                    if case .assignment = item.kind { return item.range }
                    return nil
                }
            }
        }
        var result = bytes
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) { result.removeSubrange(range) }
        return String(decoding: result, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    private static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func tomlQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private static func scalarString(bytes: [UInt8], statement: TomlPolicyLocator.Statement) -> String? {
        guard let equal = bytes[statement.range].firstIndex(of: 0x3D) else { return nil }
        // Reuse the actual TOML string decoder, including quotes/unicode, rather
        // than interpreting escaped command text as shell source.
        let scalar = Array("approval_policy ".utf8) + bytes[equal..<statement.range.upperBound]
        if case .existingScalar(_, let value) = TomlPolicyLocator.locate(scalar) { return value }
        return nil
    }
    private static func owns(_ command: String) -> Bool {
        ManagedHookCommand.owns(command, events: nativeEvents.map { "Kimi" + $0 })
    }
}
