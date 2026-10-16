import Foundation

enum ClaudeHookHandler {
    static func handlePreToolUse() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        // Desktop hosts permission prompts through canUseTool. Decide before that callback runs.
        let request: [String: Any] = ["cmd": "permission", "value": 3]
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

    static func preToolUseOutput(reply: [String: Any]?) -> [String: Any]? {
        guard effectiveSwitchState(reply) == 0 else { return nil }
        return [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            ],
        ]
    }

    private static func effectiveSwitchState(_ reply: [String: Any]?) -> Int? {
        HookSupport.approvalSwitchState(reply, client: .claude)
    }

    static func handlePermissionRequest() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
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

    static func permissionRequestOutput(reply: [String: Any]?) -> [String: Any] {
        [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": effectiveSwitchState(reply) == 0 ? "allow" : "ask"],
            ],
        ]
    }
}
