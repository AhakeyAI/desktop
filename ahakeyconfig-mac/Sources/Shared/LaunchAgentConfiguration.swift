import Foundation

public enum LaunchAgentConfiguration {
    /// A failed query or a missing/ambiguous row is not evidence of a system
    /// override. Match the exact label, never a substring of another service.
    public static func systemDisabledOverride(in output: String, commandSucceeded: Bool, label: String) -> Bool? {
        guard commandSucceeded, !label.isEmpty else { return nil }
        let pattern = #"(?m)^\s*""# + NSRegularExpression.escapedPattern(for: label) + #""\s*=>\s*(disabled|enabled|true|false)\s*,?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: output) else { return nil }
        return ["disabled", "true"].contains(String(output[range]))
    }

    /// Upgrades can keep the same binary path but change socket arguments. Compare
    /// the complete launch contract, not just the executable or an existing plist.
    public static func needsRewrite(plistURL: URL, expectedArguments: [String]) -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return true }
        return arguments != expectedArguments
    }
}
