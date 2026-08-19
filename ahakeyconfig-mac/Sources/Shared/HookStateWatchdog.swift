import Foundation

/// Hook 看门狗归位决策（纯函数，可测）。
///
/// 背景：Agent 每 10s 检查一次「最近一次 hook 状态命令」至今的活跃态是否超时
/// （PermissionRequest / UserPromptSubmit 30s，其余工具执行态 60s），超时就把
/// 键盘 LED 归位（发 Stop）。但「长时间无新 hook 事件」有两种完全不同的含义：
///
/// - CLI 崩溃/退出：end 类 hook 永远丢失，灯必须归位 —— 这是看门狗的正当职责；
/// - 长思考 / 长工具执行中：进程活着，只是没有新事件 —— PreToolUse 等执行态不能归位；
/// - Codex Desktop 的 PostToolUse：工具已经结束，但当前版本可能不再触发 Stop，
///   此时进程会一直活着，必须允许 PostToolUse 超时后归位。
///
/// 因此一般执行态仍要求「已超时且目标进程退出」；PostToolUse 是唯一例外。
public enum HookStateWatchdog {

    /// 一次看门狗检查的输入快照。
    public struct Input: Equatable, Sendable {
        /// 最近一次发给键盘的 LED 状态
        public var lastSentState: UInt8
        /// 距最近一次 hook 状态命令的秒数
        public var elapsedSinceLastHook: TimeInterval
        /// 该状态对应的超时阈值（秒）
        public var timeout: TimeInterval
        /// 目标 CLI/IDE 进程是否仍有存活（ProcessDetector 判定）
        public var isTargetProcessRunning: Bool

        public init(lastSentState: UInt8,
                    elapsedSinceLastHook: TimeInterval,
                    timeout: TimeInterval,
                    isTargetProcessRunning: Bool) {
            self.lastSentState = lastSentState
            self.elapsedSinceLastHook = elapsedSinceLastHook
            self.timeout = timeout
            self.isTargetProcessRunning = isTargetProcessRunning
        }
    }

    /// 看门狗决策结果。
    public enum Decision: Equatable, Sendable {
        /// 当前 LED 不是活跃态，看门狗无需介入
        case notActiveState
        /// 活跃态但未超时：保持灯效
        case withinTimeout
        /// 已超时但目标进程仍存活（长思考/长执行中无新 hook）：保持灯效，不得归位
        case heldProcessAlive
        /// 已超时且目标进程全部退出（end 类 hook 永远丢失）：归位到 Stop
        case resetToIdle
    }

    /// 会点亮灯条、需要看门狗盯防的活跃 hook 状态（与 Agent 侧 activeStates 一致）：
    /// 1=PermissionRequest 2=PostToolUse 3=PreToolUse 4=SessionStart 6/7=提交/等待类，
    /// 5=Stop 与 0=Notification 不属于活跃态。
    public static func isActiveState(_ state: UInt8) -> Bool {
        [1, 2, 3, 4, 6, 7].contains(state)
    }

    /// 纯决策：超时 + 进程存活 → 是否归位。PostToolUse(2) 已表示工具结束，
    /// 因而在缺少 Stop hook 时可作为任务结束兜底。
    public static func decide(_ input: Input) -> Decision {
        guard isActiveState(input.lastSentState) else { return .notActiveState }
        guard input.elapsedSinceLastHook >= input.timeout else { return .withinTimeout }
        if input.lastSentState == 2 { return .resetToIdle }
        return input.isTargetProcessRunning ? .heldProcessAlive : .resetToIdle
    }
}
