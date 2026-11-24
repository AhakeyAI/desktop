import Foundation

/// Where the app runs from decides whether its agent path may be written into
/// hook configs and the LaunchAgent plist.
///
/// macOS runs a quarantined app that was opened straight from Downloads or a
/// DMG from a random App Translocation folder. That folder disappears when the
/// app quits, so any hook pointing into it fails afterwards (`/bin/sh: … exit
/// 127` on every Claude Code tool call). The same happens for a mounted DMG
/// once it is ejected.
public enum AgentInstallLocation {
    public static let agentExecutableName = "ahakeyconfig-agent"

    /// True when the bundle path will not survive the app quitting or the DMG
    /// being ejected.
    public static func isEphemeral(bundlePath: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        if path.contains("/AppTranslocation/") { return true }
        if path.hasPrefix("/Volumes/") { return true }
        return false
    }

    /// Agent binary paths referenced by a hook config, a JSON or TOML file the
    /// app wrote. JSON escapes `/` as `\/`, so that is undone first.
    public static func referencedAgentPaths(in configText: String) -> [String] {
        let text = configText.replacingOccurrences(of: "\\/", with: "/")
        let pattern = "/[^'\"\\n\\\\]*?/" + NSRegularExpression.escapedPattern(for: agentExecutableName)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var paths: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let path = String(text[r])
            if seen.insert(path).inserted { paths.append(path) }
        }
        return paths
    }

    /// True when the config points at an agent binary other than `currentAgentPath`
    /// that no longer exists, so its hooks should be rewritten.
    public static func hasStaleAgentPath(
        in configText: String,
        currentAgentPath: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        referencedAgentPaths(in: configText).contains { path in
            path != currentAgentPath && !isExecutable(path)
        }
    }

    /// Claude Code runs hook commands through `/bin/sh`. Guarding the call keeps
    /// a moved or deleted app from turning every hook into an error: when the
    /// binary is gone the hook exits 0 and does nothing.
    public static func guardedShellCommand(quotedBinary: String, arguments: String) -> String {
        "[ -x \(quotedBinary) ] || exit 0; exec \(quotedBinary) \(arguments)"
    }
}
