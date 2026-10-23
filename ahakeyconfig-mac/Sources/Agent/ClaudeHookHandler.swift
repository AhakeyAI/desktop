import Foundation
import AhaKeyConfigShared

enum ClaudeHookHandler {
    static func handlePreToolUse() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        // Desktop hosts permission prompts through canUseTool. Decide before that callback runs.
        let request = WS3TaskMetadata.enrich(["cmd": "permission", "value": 3],
            client: .claude, event: "PreToolUse", stdin: stdinData)
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = effectiveSwitchState(reply)
        let isAuto = switchState == 0

        if let output = preToolUseOutput(reply: reply),
           let data = try? JSONSerialization.data(withJSONObject: output),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }

        HookSupport.appendDiagnostic(
            ide: "claude",
            hookEvent: "PreToolUse",
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: isAuto ? "allow" : "ask",
            cursorPermission: nil
        )
    }

    static func preToolUseOutput(reply: [String: Any]?, controlDirectory: URL = ApprovalAutomationControl.productionDirectory) -> [String: Any]? {
        guard effectiveSwitchState(reply, controlDirectory: controlDirectory) == 0 else { return nil }
        return [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            ],
        ]
    }

    private static func effectiveSwitchState(_ reply: [String: Any]?, controlDirectory: URL = ApprovalAutomationControl.productionDirectory) -> Int? {
        HookSupport.approvalSwitchState(reply, client: .claude, controlDirectory: controlDirectory)
    }

    static func handlePermissionRequest() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        let request = WS3TaskMetadata.enrich(["cmd": "permission", "value": Int(HookSupport.permissionLedValue)],
            client: .claude, event: "PermissionRequest", stdin: stdinData)
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = effectiveSwitchState(reply)
        let isAuto = switchState == 0
        let behavior: String

        if isAuto {
            behavior = "allow"
        } else {
            HookSupport.emitPermissionStderr(
                ide: "Claude",
                hookName: "PermissionRequest",
                reply: reply,
                switchState: switchState
            )
            behavior = "ask"
        }

        let out = permissionRequestOutput(reply: reply)
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        HookSupport.appendDiagnostic(
            ide: "claude",
            hookEvent: "PermissionRequest",
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: behavior,
            cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: nil
        )
    }

    static func permissionRequestOutput(reply: [String: Any]?, controlDirectory: URL = ApprovalAutomationControl.productionDirectory) -> [String: Any] {
        // PermissionRequest supports allow/deny only. No decision preserves
        // Claude's own approval flow for manual, paused or unverified states.
        guard effectiveSwitchState(reply, controlDirectory: controlDirectory) == 0 else { return [:] }
        return [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "allow"],
            ],
        ]
    }
}
