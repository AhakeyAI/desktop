import Foundation

/// Hooks only add a verified per-request grant. Absence of a grant always
/// preserves Codex's own permission policy, including the user's Full Access.
public enum CodexHookApproval {
    // Compatibility for older local verification callers; PreToolUse is status-only.
    public static func requiresPreToolVerification(permissionMode: String?) -> Bool { false }
    public static func bypassPreToolOutput(verifiedAuto: Bool) -> [String: Any]? { nil }

    public static func permissionRequestOutput(verifiedAuto: Bool) -> [String: Any] {
        var output: [String: Any] = ["hookEventName": "PermissionRequest"]
        if verifiedAuto { output["decision"] = ["behavior": "allow"] }
        return ["hookSpecificOutput": output]
    }
}
