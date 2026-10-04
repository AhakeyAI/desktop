import Foundation

enum CursorHookHandler {
    static func standardOutput(for switchState: Int?) -> String? {
        switchState == 0 ? #"{"permission":"allow"}"# : nil
    }

    static func handleToolPermission(hookEvent: String) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Cursor")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        if let output = standardOutput(for: switchState) {
            print(output)
        }
        // 手动/离线/超时均不覆盖 Cursor 的原生批准流程；Hook 也不再改写全局权限文件。

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
            cursorPermission: isAuto ? "allow" : "defer_to_native",
            cursorDebug: cursorDebug,
            kimiPreToolDecision: nil
        )
    }
}
