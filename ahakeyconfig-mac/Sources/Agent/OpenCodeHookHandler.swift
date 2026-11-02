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
/// **重要：`ctx.permission.hook("evaluate")` 不属于 opencode 的公开 API。**
/// 官方文件（<https://opencode.ai/docs/plugins/>）只列出 `event`、`"tool.execute.before"`、
/// `"shell.env"` 这类 plugin 挂钩；`/docs/permissions` 描述的是 config 的**静态**规则，
/// 没有「由外部程序动态决定放行」的接口。这个 evaluate 挂钩是 opencode 2.2.5 实测可用的内部 API。
///
/// 之所以仍然采用它：opencode 的 config 规则只能把动作固定成 allow/ask/deny，`ask` 只会回到
/// TUI 等人工点击，AhaKey 的实体拨杆就失去了意义。要在「弹窗之前」用拨杆决定，只有这个位置。
///
/// 退路（fail-safe）：plugin 安装/加载时若找不到 `permission.hook`，会打印
/// `permission.hook unavailable: approval is NOT bridged in this opencode build` 并**不介入**，
/// opencode 回到自己的默认审批流程 —— AhaKey 不会挡住它，只是拨杆不再代答。
/// 若未来 opencode 移除该挂钩，同样走这条退路，不会造成「无法审批」。
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
