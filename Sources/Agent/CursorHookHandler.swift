import Foundation

enum CursorHookHandler {
    static func handleToolPermission(hookEvent: String) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Cursor")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0
        let permission: String

        if isAuto {
            permission = "allow"
        } else {
            HookSupport.emitPermissionStderr(
                ide: "Cursor",
                hookName: hookEvent,
                reply: reply,
                switchState: switchState
            )
            permission = "ask"
        }

        if let s = switchState {
            let auto = s == 0
            CursorCliLeverSync.apply(switchStateAuto: auto)
            CursorPermissionsJsonLeverSync.apply(switchStateAuto: auto)
        }

        let out: [String: Any] = ["permission": permission]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        let cursorDebug = HookSupport.buildCursorHookDebug(
            stdinData: stdinData,
            commandPreview: ctx["commandPreview"] as? String
        )
        HookSupport.appendDiagnostic(
            ide: "cursor",
            hookEvent: hookEvent,
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: nil,
            cursorPermission: permission,
            cursorDebug: cursorDebug,
            kimiPreToolDecision: nil
        )
    }
}
