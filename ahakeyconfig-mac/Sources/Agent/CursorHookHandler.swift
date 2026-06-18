import Foundation

enum CursorHookHandler {
    static func handleToolPermission(hookEvent: String) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Cursor")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        if isAuto {
            // 自动模式：返回 allow，让操作直接执行
            let out: [String: Any] = ["permission": "allow"]
            if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            // 手动模式：返回 deny，阻止操作（Cursor 不支持询问模式）
            let out: [String: Any] = ["permission": "deny"]
            if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
            HookSupport.emitPermissionStderr(
                ide: "Cursor",
                hookName: hookEvent,
                reply: reply,
                switchState: switchState
            )
        }

        if let s = switchState {
            let auto = s == 0
            CursorCliLeverSync.apply(switchStateAuto: auto)
            CursorPermissionsJsonLeverSync.apply(switchStateAuto: auto)
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
            cursorPermission: isAuto ? "allow" : "deny",
            cursorDebug: cursorDebug,
            kimiPreToolDecision: nil
        )
    }
}
