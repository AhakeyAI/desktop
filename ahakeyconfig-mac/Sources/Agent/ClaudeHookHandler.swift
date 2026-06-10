import Foundation

enum ClaudeHookHandler {
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
