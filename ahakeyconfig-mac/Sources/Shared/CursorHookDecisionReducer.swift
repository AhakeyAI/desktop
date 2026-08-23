/// Cursor Hook 的三态决定。只有 `allow` 会覆盖 Cursor 原生权限流。
public enum CursorHookDecision: Equatable, Sendable {
    case allow
    case deferToNative
    case unavailable
}

public enum CursorHookQueryFailure: String, Equatable, Sendable {
    case timeout
    case offline
    case invalidResponse = "invalid_response"
}

/// Hook handler 可直接消费的纯结果。
public struct CursorHookDecisionResult: Equatable, Sendable {
    public let decision: CursorHookDecision
    /// `nil` 表示 stdout 必须为空，由 Cursor 原生 Run Mode / 批准流继续决定。
    public let standardOutput: String?
    public let queryFailure: CursorHookQueryFailure?

    public init(
        decision: CursorHookDecision,
        standardOutput: String?,
        queryFailure: CursorHookQueryFailure? = nil
    ) {
        self.decision = decision
        self.standardOutput = standardOutput
        self.queryFailure = queryFailure
    }
}

/// 将 Runtime 三态收敛为 Cursor 的显式 allow 或中性委托。
public enum CursorHookDecisionReducer {
    public static func reduce(
        _ runtimeDecision: AhaKeyRuntimeHookApprovalDecision?
    ) -> CursorHookDecisionResult {
        switch runtimeDecision {
        case .automatic:
            return CursorHookDecisionResult(
                decision: .allow,
                standardOutput: #"{"permission":"allow"}"#
            )
        case .manual:
            return CursorHookDecisionResult(decision: .deferToNative, standardOutput: nil)
        case .unavailable, .none:
            return CursorHookDecisionResult(decision: .unavailable, standardOutput: nil)
        }
    }
}
