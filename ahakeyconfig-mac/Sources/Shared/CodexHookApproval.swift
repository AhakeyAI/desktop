import Foundation

/// Codex snapshots a thread's approval policy. Keep new sessions native and
/// grant only the current PermissionRequest; never persist a bypass for a dial.
public enum CodexHookApproval {
    public static func requiresPreToolVerification(permissionMode: String?) -> Bool {
        permissionMode != "default"
    }

    /// Only called for an old bypass session or an unknown permission mode.
    /// Native PreToolUse cannot request an approval dialog; deny is supported.
    public static func bypassPreToolOutput(verifiedAuto: Bool) -> [String: Any]? {
        guard !verifiedAuto else { return nil }
        return ["hookSpecificOutput": [
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": "Enable native approvals in Codex, or start a session with native approvals. AhaKey did not authorize this tool.",
        ]]
    }

    public static func permissionRequestOutput(verifiedAuto: Bool) -> [String: Any] {
        var output: [String: Any] = ["hookEventName": "PermissionRequest"]
        if verifiedAuto { output["decision"] = ["behavior": "allow"] }
        return ["hookSpecificOutput": output]
    }
}
