import Foundation
import AhaKeyConfigShared

enum CodexHookHandler {
    /// 事件级依赖（测试注入点）。生产默认全部转发 `HookSupport`；测试可替换为 fake/recording
    /// 实现，从而真实驱动 `CodexSessionStart` 与 `CodexPermissionRequest` 两条事件路径，
    /// 而不触碰用户 socket、诊断日志或真实配置。PreToolUse 仅同步任务状态，不改动用户审批链路。
    struct Dependencies {
        var readStdin: () -> Data
        var parseContext: (Data, String) -> [String: Any]
        var sendRequest: ([String: Any], Double) -> [String: Any]?
        var appendHookLog: (String?, String, UInt8, [String: Any], [String: Any]?, Int?, String?) -> Void
        var emitPermissionStderr: (String, String, [String: Any]?, Int?) -> Void
        var appendDiagnostic: (
            String, String, [String: Any], [String: Any]?, Int?, Bool, String?, String?, [String: Any]?, String?, [String: Any]?
        ) -> Void
        var writeStdout: (String) -> Void
        /// Regression seam: Hook events must never invoke a policy writer.
        var preparePolicy: () -> Void
        var approvalControlDirectory: URL = ApprovalAutomationControl.productionDirectory

        static let production = Dependencies(
            readStdin: { HookSupport.readAllStdinSilently() },
            parseContext: { HookSupport.parseStdinContext($0, label: $1) },
            sendRequest: { HookSupport.sendJsonRequest($0, timeout: $1) },
            appendHookLog: { hookEvent, agentEvent, stateValue, toolContext, reply, switchState, decision in
                HookSupport.appendCodexHookLog(
                    hookEvent: hookEvent, agentEvent: agentEvent, stateValue: stateValue,
                    toolContext: toolContext, reply: reply, switchState: switchState, decision: decision
                )
            },
            emitPermissionStderr: { ide, hookName, reply, switchState in
                HookSupport.emitPermissionStderr(ide: ide, hookName: hookName, reply: reply, switchState: switchState)
            },
            appendDiagnostic: { ide, hookEvent, toolContext, reply, switchState, isAuto,
                                claudeBehavior, cursorPermission, cursorDebug, kimiPreToolDecision, kimiLeverDebug in
                HookSupport.appendDiagnostic(
                    ide: ide, hookEvent: hookEvent, toolContext: toolContext, reply: reply,
                    switchState: switchState, isAuto: isAuto, claudeBehavior: claudeBehavior,
                    cursorPermission: cursorPermission, cursorDebug: cursorDebug,
                    kimiPreToolDecision: kimiPreToolDecision, kimiLeverDebug: kimiLeverDebug
                )
            },
            writeStdout: { print($0) },
            preparePolicy: {}
        )
    }

    /// 测试可整体替换；生产为 `Dependencies.production`。
    static var dependencies = Dependencies.production

    static func handleState(stateValue: UInt8) {
        let stdinData = dependencies.readStdin()
        let ctx = dependencies.parseContext(stdinData, "Codex")
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
        request = WS3TaskMetadata.enrich(request, client: .codex,
            event: codexAgentEventName(forStateValue: stateValue), stdin: stdinData)
        let reply = dependencies.sendRequest(request, HookSupport.stateRequestTimeout)
        let switchState = HookSupport.switchStateValue(reply?["switchState"])

        let output: [String: Any] = [:]
        // A missing AhaKey grant is not a denial. Codex retains its original
        // approval policy; only a real PermissionRequest can receive our grant.

        dependencies.appendHookLog(
            ctx["hook_event_name"] as? String,
            codexAgentEventName(forStateValue: stateValue),
            stateValue,
            ctx,
            reply,
            switchState,
            "pass_through"
        )
        if let data = try? JSONSerialization.data(withJSONObject: output),
           let json = String(data: data, encoding: .utf8) {
            dependencies.writeStdout(json)
        }
    }

    static func handlePermissionRequest() {
        let stdinData = dependencies.readStdin()
        let ctx = dependencies.parseContext(stdinData, "Codex")
        let request = WS3TaskMetadata.enrich(["cmd": "permission", "value": Int(HookSupport.permissionLedValue)],
            client: .codex, event: "PermissionRequest", stdin: stdinData)
        let reply = dependencies.sendRequest(request, HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.approvalSwitchState(reply, client: .codex, controlDirectory: dependencies.approvalControlDirectory)
        let isAuto = switchState == 0

        if !isAuto {
            dependencies.emitPermissionStderr("Codex", "PermissionRequest", reply, switchState)
        }

        dependencies.appendHookLog(
            "PermissionRequest",
            "CodexPermissionRequest",
            HookSupport.permissionLedValue,
            ctx,
            reply,
            switchState,
            isAuto ? "allow" : "pass_through"
        )
        let out = CodexHookApproval.permissionRequestOutput(verifiedAuto: isAuto)
        if let data = try? JSONSerialization.data(withJSONObject: out, options: []),
           let str = String(data: data, encoding: .utf8) {
            dependencies.writeStdout(str)
        }

        dependencies.appendDiagnostic(
            "codex",
            "PermissionRequest",
            ctx,
            reply,
            switchState,
            isAuto,
            nil,
            nil,
            nil,
            nil,
            nil
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
