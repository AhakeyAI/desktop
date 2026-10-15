import Foundation

enum CursorHookHandler {
    static func handleToolPermission(hookEvent: String) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Cursor")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        let permission = permissionForEvent(hookEvent, isAuto: isAuto)
        if !isAuto {
            HookSupport.emitPermissionStderr(
                ide: "Cursor",
                hookName: hookEvent,
                reply: reply,
                switchState: switchState
            )
        }

        // 拨杆状态未知时也撤销此前的宽松配置，避免 Agent/BLE 失联后继续自动执行。
        CursorCliLeverSync.apply(switchStateAuto: isAuto)
        CursorPermissionsJsonLeverSync.apply(switchStateAuto: isAuto)

        // preToolUse 不执行 ask；交回 Cursor 自身权限层。beforeShellExecution / beforeMCPExecution 支持 ask。
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

    static func permissionForEvent(_ hookEvent: String, isAuto: Bool) -> String {
        if isAuto { return "allow" }
        return hookEvent == "beforeShellExecution" || hookEvent == "beforeMCPExecution" ? "ask" : "allow"
    }
}
