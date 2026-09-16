import Foundation
import AhaKeyConfigShared

enum CodexHookHandler {
    /// 事件级依赖（测试注入点）。生产默认全部转发 `HookSupport`；测试可替换为 fake/recording
    /// 实现，从而真实驱动 `CodexSessionStart` 与 `CodexPermissionRequest` 两条事件路径，
    /// 而不触碰用户 socket、诊断日志或真实 `~/.codex/config.toml`。Hook 协议语义不变。
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
        /// 唯一 policy seam：值为「拨杆是否自动档」。
        var policySink: (Bool) -> Void

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
            policySink: { CodexConfigLeverSync.apply(switchStateAuto: $0) }
        )
    }

    /// 测试可整体替换；生产为 `Dependencies.production`。
    static var dependencies = Dependencies.production

    /// 两个 Hook 事件共用的唯一接线：把观测到的拨杆状态交给 typed policy seam。
    /// 返回是否观测到状态（与旧语义一致：nil 时不触碰 config）。
    @discardableResult
    private static func syncPolicy(switchState: Int?) -> Bool {
        guard let switchState else { return false }
        dependencies.policySink(switchState == 0)
        return true
    }
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
        let reply = dependencies.sendRequest(request, HookSupport.stateRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])

        // SessionStart 时把拨杆状态写入顶层 approval_policy：
        // Codex 在会话开始即读取审批策略，之后才会决定是否触发 PermissionRequest，
        // 必须在这里同步才能让"自动/手动"在本次会话生效。
        // 注意：`cmd: "state"` 的回包不带 switchState（见 AhaKeyAgent.handleJsonCommand），
        // 必须单独发 `status` 查询拨杆的真实状态。
        if stateValue == 4 {
            let statusReply = dependencies.sendRequest(["cmd": "status"], HookSupport.stateRequestTimeout)
            syncPolicy(switchState: HookSupport.intValue(statusReply?["switchState"]))
        }

        dependencies.appendHookLog(
            ctx["hook_event_name"] as? String,
            codexAgentEventName(forStateValue: stateValue),
            stateValue,
            ctx,
            reply,
            switchState,
            nil
        )
        dependencies.writeStdout("{}")
    }

    static func handlePermissionRequest() {
        let stdinData = dependencies.readStdin()
        let ctx = dependencies.parseContext(stdinData, "Codex")
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = dependencies.sendRequest(request, HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        syncPolicy(switchState: switchState)

        if !isAuto {
            dependencies.emitPermissionStderr("Codex", "PermissionRequest", reply, switchState)
        }

        var hookOut: [String: Any] = ["hookEventName": "PermissionRequest"]
        if isAuto {
            hookOut["decision"] = ["behavior": "allow"]
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
        let out: [String: Any] = ["hookSpecificOutput": hookOut]
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
