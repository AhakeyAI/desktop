import Foundation

enum ClaudeHookHandler {
    static func handlePreToolUse() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        // Desktop hosts permission prompts through canUseTool. Decide before that callback runs.
        let request: [String: Any] = ["cmd": "permission", "value": 3]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        if let output = preToolUseOutput(switchState: switchState),
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

    static func preToolUseOutput(switchState: Int?) -> [String: Any]? {
        guard switchState == 0 else { return nil }
        return [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            ],
        ]
    }

    static func handlePermissionRequest() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Claude")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
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

        let out: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": behavior],
            ],
        ]
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
}
