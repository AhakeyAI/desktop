import Foundation
import AhaKeyConfigShared

enum CodexHookHandler {
    static func handleState(stateValue: UInt8) {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Codex")
        let plan = CodexHookStatePlan.make(stateValue: stateValue)
        var request: [String: Any] = [
            "cmd": plan.command == .state ? "state" : "state_with_reset",
            "value": Int(plan.stateValue),
        ]
        if let resetValue = plan.resetValue {
            request["resetValue"] = Int(resetValue)
        }
        if let delayMilliseconds = plan.delayMilliseconds {
            request["delayMs"] = delayMilliseconds
        }
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.stateRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])

        // SessionStart 时把拨杆状态写入顶层 approval_policy：
        // Codex 在会话开始即读取审批策略，之后才会决定是否触发 PermissionRequest，
        // 必须在这里同步才能让"自动/手动"在本次会话生效。
        // 注意：`cmd: "state"` 的回包不带 switchState（见 AhaKeyAgent.handleJsonCommand），
        // 必须单独发 `status` 查询拨杆的真实状态。
        if stateValue == 4 {
            let statusReply = HookSupport.sendJsonRequest(["cmd": "status"], timeout: HookSupport.stateRequestTimeout)
            if let s = HookSupport.intValue(statusReply?["switchState"]) {
                CodexConfigLeverSync.apply(switchStateAuto: s == 0)
            }
        }

        HookSupport.appendCodexHookLog(
            hookEvent: ctx["hook_event_name"] as? String,
            agentEvent: codexAgentEventName(forStateValue: stateValue),
            stateValue: stateValue,
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
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

        if let s = switchState {
            CodexConfigLeverSync.apply(switchStateAuto: s == 0)
        }

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
