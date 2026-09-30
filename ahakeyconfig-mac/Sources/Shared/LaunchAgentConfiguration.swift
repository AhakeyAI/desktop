import Foundation

public enum LaunchAgentConfiguration {
    /// Upgrades can keep the same binary path but change socket arguments. Compare
    /// the complete launch contract, not just the executable or an existing plist.
    public static func needsRewrite(plistURL: URL, expectedArguments: [String]) -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return true }
        return arguments != expectedArguments
    }
}
