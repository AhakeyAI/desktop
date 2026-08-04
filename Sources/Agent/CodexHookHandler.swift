import Foundation

enum CodexHookHandler {
    static func handleState(stateValue: UInt8) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Codex")
        let reply = HookSupport.sendUnifiedLightState(stateValue: stateValue)
        HookSupport.appendCodexHookLog(
            hookEvent: ctx["hook_event_name"] as? String,
            agentEvent: codexAgentEventName(forStateValue: stateValue),
            stateValue: stateValue,
            toolContext: ctx,
            reply: reply,
            switchState: HookSupport.intValue(reply?["switchState"]),
            decision: nil
        )
        print("{}")
    }

    static func handlePermissionRequest() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Codex")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        if !isAuto {
            HookSupport.emitPermissionStderr(
                ide: "Codex",
                hookName: "PermissionRequest",
                reply: reply,
                switchState: switchState
            )
        }

        var hookOut: [String: Any] = ["hookEventName": "PermissionRequest"]
        if isAuto {
            hookOut["decision"] = ["behavior": "allow"]
        }
        HookSupport.appendCodexHookLog(
            hookEvent: "PermissionRequest",
            agentEvent: "CodexPermissionRequest",
            stateValue: HookSupport.permissionLedValue,
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            decision: isAuto ? "allow" : "pass_through"
        )
        let out: [String: Any] = ["hookSpecificOutput": hookOut]
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        HookSupport.appendDiagnostic(
            ide: "codex",
            hookEvent: "PermissionRequest",
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: nil,
            cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: nil
        )
    }

    private static func codexAgentEventName(forStateValue stateValue: UInt8) -> String {
        switch stateValue {
        case 2: return "CodexPostToolUse"
        case 3: return "CodexPreToolUse"
        case 4: return "CodexSessionStart"
        case 5: return "CodexStop"
        case 7: return "CodexUserPromptSubmit"
        default: return "CodexState\(stateValue)"
        }
    }
}
