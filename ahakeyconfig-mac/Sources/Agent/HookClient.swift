import Foundation
import AhaKeyConfigShared

/// 仅负责事件路由；各 IDE 的具体逻辑已拆到独立 handler，避免互相影响。
enum HookClient {
    private enum EventRoute {
        case sharedState(UInt8)
        case claudePreToolUse
        case claudePermissionRequest
        case cursorToolPermission
        case codexState(UInt8)
        case codexPermissionRequest
        case kimiPreToolPermission
    }

    private static let eventMap: [String: EventRoute] = [
        "Notification": .sharedState(0),
        "PermissionRequest": .claudePermissionRequest,
        "PostToolUse": .sharedState(2),
        "PreToolUse": .claudePreToolUse,
        "SessionStart": .sharedState(4),
        "Stop": .sharedState(5),
        // SubagentStop：Claude Code 将原 Stop 拆分后，手动终止任务时触发此事件而非 Stop
        "SubagentStop": .sharedState(5),
        "TaskCompleted": .sharedState(6),
        "UserPromptSubmit": .sharedState(7),
        "SessionEnd": .sharedState(8),
        "PreCompact": .sharedState(0),

        "sessionStart": .sharedState(4),
        "sessionEnd": .sharedState(8),
        "postToolUse": .sharedState(2),
        "beforeSubmitPrompt": .sharedState(7),
        "beforeReadFile": .sharedState(3),
        "stop": .sharedState(5),
        "preToolUse": .cursorToolPermission,
        "beforeShellExecution": .cursorToolPermission,
        "beforeMCPExecution": .cursorToolPermission,

        "CodexSessionStart": .codexState(4),
        "CodexPostToolUse": .codexState(2),
        "CodexPreToolUse": .codexState(3),
        "CodexUserPromptSubmit": .codexState(7),
        "CodexStop": .codexState(5),
        "CodexPermissionRequest": .codexPermissionRequest,

        "KimiNotification": .sharedState(0),
        "KimiSessionStart": .sharedState(4),
        "KimiSessionEnd": .sharedState(8),
        "KimiPreToolUse": .kimiPreToolPermission,
        "KimiPermissionRequest": .sharedState(1),
        "KimiPermissionResult": .sharedState(2),
        "KimiPostToolUse": .sharedState(2),
        "KimiUserPromptSubmit": .sharedState(7),
        "KimiStop": .sharedState(5),

        "WorkBuddyUserPromptSubmit": .sharedState(7),
        "WorkBuddyStop": .sharedState(5),
        "WorkBuddySessionEnd": .sharedState(8),
    ]

    /// Shared-state routes use the same builder in production and focused tests.
    /// No tool content or command text is forwarded to the task registry.
    static func stateRequest(event: String, stdin: Data) -> [String: Any]? {
        if let event = ClineStatusHooks.Event(hookArgument: event) {
            return event.stateRequest(from: stdin)
        }
        if let event = PassiveStatusHook(rawValue: event) {
            return event.stateRequest(from: stdin)
        }
        if event == OpenCodeStatusHooks.hookArgument {
            return OpenCodeStatusHooks.stateRequest(from: stdin)
        }
        if let antigravity = AntigravityStatusHooks.Event(hookArgument: event) {
            return antigravity.stateRequest(from: stdin)
        }
        if let copilot = CopilotStatusHooks.Event(hookArgument: event) {
            return copilot.stateRequest(from: stdin)
        }
        guard case .sharedState(let value) = eventMap[event] else { return nil }
        let request: [String: Any] = ["cmd": "state", "value": Int(value)]
        guard let client = WS3TaskMetadata.client(for: event) else { return request }
        if client == .workBuddy {
            let enriched = WS3TaskMetadata.enrich(request, client: client, event: event,
                                                 stdin: stdin, expectedEvent: String(event.dropFirst("WorkBuddy".count)))
            return enriched["task"] == nil ? nil : enriched
        }
        return WS3TaskMetadata.enrich(request, client: client, event: event, stdin: stdin)
    }

    static func verifiedLifecycleClient(event: String, stdin: Data) -> StatusHookReceipts.Client? {
        let client: WS3TaskClient
        switch event {
        case "SessionStart", "SessionEnd", "UserPromptSubmit": client = .claude
        case "sessionStart", "sessionEnd", "beforeSubmitPrompt": client = .cursor
        case "KimiSessionStart", "KimiSessionEnd", "KimiUserPromptSubmit": client = .kimi
        default: return nil
        }
        let expected = client == .kimi ? String(event.dropFirst("Kimi".count)) : event
        let evidence = WS3TaskMetadata.enrich([:], client: client, event: event, stdin: stdin, expectedEvent: expected)
        let receiptClient = StatusHookReceipts.Client(rawValue: client.rawValue)
        return evidence["task"] == nil ? nil : receiptClient
    }

    static func run(event: String) -> Int32 {
        signal(SIGPIPE, SIG_IGN)

        let receiptClient: StatusHookReceipts.Client?
        let antigravity = AntigravityStatusHooks.Event(hookArgument: event)
        let cline = ClineStatusHooks.Event(hookArgument: event)
        if cline != nil {
            receiptClient = .cline
        } else if let passive = PassiveStatusHook(rawValue: event) {
            receiptClient = passive.receiptClient
        } else if event == OpenCodeStatusHooks.hookArgument {
            receiptClient = .openCode
        } else if antigravity != nil {
            receiptClient = .antigravity
        } else if CopilotStatusHooks.Event(hookArgument: event) != nil {
            receiptClient = .copilot
        } else if WS3TaskMetadata.client(for: event) == .workBuddy {
            receiptClient = .workBuddy
        } else {
            receiptClient = nil
        }
        if let receiptClient {
            let confirm = StatusHookReceipts().eventRecorder(client: receiptClient,
                                                             executablePath: CommandLine.arguments[0])
            if let request = stateRequest(event: event, stdin: HookSupport.readAllStdinSilently()) {
                confirm()
                _ = HookSupport.sendJsonRequest(request, timeout: HookSupport.stateRequestTimeout)
            }
            if let antigravity { print(antigravity.response) }
            if cline != nil { print(ClineStatusHooks.Event.response) }
            return 0
        }

        // 调试日志：记录所有收到的事件
        FileHandle.standardError.write(Data("[ahakey-hook] DEBUG: received event: '\(event)'\n".utf8))
        
        guard let route = eventMap[event] else {
            FileHandle.standardError.write(Data("[ahakey-hook] unknown event: \(event)\n".utf8))
            return 0
        }

        switch route {
        case .sharedState:
            let stdin = HookSupport.readAllStdinSilently()
            if let request = stateRequest(event: event, stdin: stdin) {
                if let client = verifiedLifecycleClient(event: event, stdin: stdin) {
                    StatusHookReceipts().eventRecorder(client: client, executablePath: CommandLine.arguments[0])()
                }
                _ = HookSupport.sendJsonRequest(request, timeout: HookSupport.stateRequestTimeout)
            }
        case .claudePreToolUse:
            ClaudeHookHandler.handlePreToolUse()
        case .claudePermissionRequest:
            ClaudeHookHandler.handlePermissionRequest()
        case .cursorToolPermission:
            CursorHookHandler.handleToolPermission(hookEvent: event)
        case .codexState(let value):
            CodexHookHandler.handleState(stateValue: value)
        case .codexPermissionRequest:
            CodexHookHandler.handlePermissionRequest()
        case .kimiPreToolPermission:
            KimiHookHandler.handlePreToolPermission()
        }
        return 0
    }
}
