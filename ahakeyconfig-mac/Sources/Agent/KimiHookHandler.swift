import Foundation

enum KimiHookHandler {
    static func handlePreToolPermission() {
        let stdinData = HookSupport.readAllStdinSilently()
        let ctx = HookSupport.parseStdinContext(stdinData, label: "Kimi")
        KimiHookDebugLog.append(event: "kimi_PreToolUse_start", details: [
            "stdinBytes": stdinData.count,
            "toolPreview": ctx,
            "hintLogFile": KimiHookDebugLog.logPath,
        ])
        KimiHookDebugLog.stderrLine("PreToolUse hook start bytes=\(stdinData.count); full log=\(KimiHookDebugLog.logPath)")

        let request: [String: Any] = ["cmd": "permission", "value": Int(HookSupport.permissionLedValue)]
        let reply = HookSupport.sendJsonRequest(request, timeout: HookSupport.permissionRequestTimeout)
        let switchState = HookSupport.intValue(reply?["switchState"])
        let isAuto = switchState == 0

        KimiHookDebugLog.append(event: "kimi_PreToolUse_agent_reply", details: [
            "agentReplyNil": reply == nil,
            "switchState": switchState.map { $0 } ?? NSNull(),
            "computedIsAuto": isAuto,
            "replyPreview": kimiReplyPreview(reply),
        ])
        KimiHookDebugLog.stderrLine("agent socket reply: switchState=\(switchState.map { String($0) } ?? "nil") isAuto=\(isAuto)")

        let stdoutPayload: String
        let kimiPreToolDecision: String
        if isAuto {
            stdoutPayload = ""
            kimiPreToolDecision = "auto_no_stdout_no_veto"
        } else {
            stdoutPayload = ""
            kimiPreToolDecision = "manual_lever_no_stdout"
            HookSupport.emitPermissionStderr(
                ide: "Kimi",
                hookName: "PreToolUse",
                reply: reply,
                switchState: switchState
            )
        }

        let kimiProbeInitial = KimiConfigDiagnostic.snapshotForLog()
        KimiHookDebugLog.append(event: "kimi_PreToolUse_probe_before_lever_sync", details: [
            "kimiLeverDebug_preview": kimiProbeInitial,
            "switchStateNil": switchState == nil,
            "kimiRunnerNote": "upstream_kimi_hooks_runner_only_handles_permissionDecision_deny",
        ])
        var leverSnapshotForLog = kimiProbeInitial
        if switchState == nil {
            KimiHookDebugLog.stderrLine("no switchState from agent → skipped Kimi permission sync; kimiPreTool=\(kimiPreToolDecision); check BLE/agent")
        } else {
            KimiConfigLeverSync.apply(switchStateAuto: isAuto)
            leverSnapshotForLog = KimiConfigLeverSync.diagnosticSnapshotForLog()
            KimiHookDebugLog.append(event: "kimi_PreToolUse_after_lever_disk_sync", details: leverSnapshotForLog)
            let path = leverSnapshotForLog["kimiConfigPath"] as? String ?? "?"
            if leverSnapshotForLog["kimiConfigGeneration"] as? String == "kimi_code" {
                let mode = leverSnapshotForLog["default_permission_mode"].flatMap { $0 as? String } ?? "(unset/absent)"
                KimiHookDebugLog.stderrLine(
                    "default_permission_mode=\(mode) in \(path); applies to new Kimi sessions — use /yolo or /permission to switch the current one."
                )
            } else {
                let yoloSnippet = leverSnapshotForLog["default_yolo_valueSnippet"].flatMap { $0 as? String } ?? "(unset/absent)"
                KimiHookDebugLog.stderrLine("default_yolo=\(yoloSnippet) in \(path); run /reload in the running kimi session.")
            }
        }

        if !stdoutPayload.isEmpty {
            FileHandle.standardOutput.write(Data(stdoutPayload.utf8))
        }
        KimiHookDebugLog.append(event: "kimi_PreToolUse_stdout", details: [
            "kimiDecision": kimiPreToolDecision,
            "stdoutChars": stdoutPayload.count,
            "hint": "PreToolUse 仅 deny 会拦工具，放行由权限模式决定：Kimi Code 读 default_permission_mode（新会话生效，当前会话用 /yolo、/permission）；旧版 kimi-cli 读 default_yolo（/reload 生效）。",
        ])
        KimiHookDebugLog.stderrLine("stdout chars=\(stdoutPayload.count) decision=\(kimiPreToolDecision)")

        HookSupport.appendDiagnostic(
            ide: "kimi",
            hookEvent: "PreToolUse",
            toolContext: ctx,
            reply: reply,
            switchState: switchState,
            isAuto: isAuto,
            claudeBehavior: nil,
            cursorPermission: nil,
            cursorDebug: nil,
            kimiPreToolDecision: kimiPreToolDecision,
            kimiLeverDebug: KimiConfigLeverSync.diagnosticSnapshotForLog()
        )
    }

    private static func kimiReplyPreview(_ reply: [String: Any]?) -> [String: Any] {
        guard let reply else {
            return ["nil": true]
        }
        var o: [String: Any] = [:]
        if let sv = reply["switchState"] {
            o["switchState"] = String(String(describing: sv).prefix(48))
        }
        if let ok = reply["ok"] {
            o["ok"] = ok
        }
        if let err = reply["error"] as? String {
            o["error"] = String(err.prefix(160))
        }
        return o
    }
}
