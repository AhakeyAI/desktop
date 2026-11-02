import Foundation

/// opencode v2 的拨杆审批 handler。
///
/// 与 Claude / Cursor / Codex / Kimi 不同，opencode **没有**「hook 配置文件」这种东西：
/// 它是 TS/JS plugin 模型。由 AhaKey 安装的 plugin 在
/// `ctx.permission.hook("evaluate")` 里同步执行本进程：
///
///     ahakeyconfig-agent hook OpenCodePermissionEvaluate     (stdin = JSON, stdout = 决策 JSON)
///
/// 这个调用发生在 opencode「规则判定完成之后、动作执行或权限提示发布之前」，
/// 是唯一能在弹窗前就用实体拨杆决定的位置。
///
/// 时间预算跟 Claude 的 PermissionRequest 不一样：opencode 的 TUI 会同步等我们，
/// 所以这里用更短的上限，而且**任何异常都回 `ask`**（把决定权交回 opencode 自己问人），
/// 绝不因为超时/断连而误放行 —— 与 upstream `docs/architecture.md` 的 fail-safe 原则一致。
enum OpenCodeHookHandler {
    /// 决策结果。`deny` 目前保留：AhaKey 的实体键没有「单次拒绝」通道，
    /// 拨杆只有自动/手动两档，所以正常路径只会产出 `allow` 或 `ask`。
    enum Decision: String {
        case allow
        case ask
        case deny
    }

    /// 比 Claude 的 `permissionRequestTimeout`（5s）更短：opencode 端 plugin 自己的
    /// 硬上限是 3s，这里 2s 保证「agent 一定先回」，不会与 plugin 的 timeout 抢跑。
    static let evaluateRequestTimeout: Double = HookSupport.stateRequestTimeout

    static func handlePermissionEvaluate() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "OpenCode")

        // `cmd: permission` 同时做两件事：点亮键盘的审批灯，并回传拨杆状态。
        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: evaluateRequestTimeout)

        // 与 Claude 同一条严格校验：只认「本次」Agent 明确验证过的物理自动档。
        let switchState = HookSupport.verifiedSwitchState(reply)
        let isAuto = switchState == 0
        let decision: Decision = isAuto ? .allow : .ask

        if !isAuto {
            HookSupport.emitPermissionStderr(
                ide: "OpenCode",
                hookName: "PermissionEvaluate",
                reply: reply,
                switchState: switchState,
                timeout: evaluateRequestTimeout
            )
        }

        emit(decision: decision, switchState: switchState, toolContext: ctx)

        HookSupport.appendDiagnostic(
            ide: "opencode",
            hookEvent: "OpenCodePermissionEvaluate",
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: decision.rawValue,
            cursorPermission: nil
        )
    }

    /// 决策回包。拆出来是为了能单测（`emit` 只负责写到 stdout）。
    static func decisionPayload(
        decision: Decision,
        switchState: Int?,
        toolContext: [String: Any]
    ) -> [String: Any] {
        var out: [String: Any] = [
            "decision": decision.rawValue,
            "ide": "opencode",
        ]
        if let switchState {
            out["switchState"] = switchState
        } else {
            out["switchState"] = NSNull()
            out["failSafe"] = true
        }
        if let action = toolContext["tool_name"] as? String {
            out["action"] = action
        }
        return out
    }

    /// **永远输出一个决策。** 没有 stdout 的话，plugin 只能等自己的 timeout，
    /// 使用者会看到「按了没反应」而不是「交回 TUI 自己问」。
    static func emit(decision: Decision, switchState: Int?, toolContext: [String: Any]) {
        let out = decisionPayload(decision: decision, switchState: switchState, toolContext: toolContext)
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: []),
              let json = String(data: data, encoding: .utf8) else {
            // 连 JSON 都组不出来时也要给一个能解析的回包，避免 plugin 落到 timeout。
            print(#"{"decision":"ask","ide":"opencode","failSafe":true}"#)
            return
        }
        print(json)
    }
}
