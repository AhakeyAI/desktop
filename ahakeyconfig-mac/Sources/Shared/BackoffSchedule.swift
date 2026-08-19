import Foundation

/// 自动重连退避序列（阶段 3）：按给定间隔逐级拉长，到达末值后保持。
/// 默认 4s → 8s → 15s → 30s 封顶；用户显式操作或检测到目标设备广播时 `reset()` 回第一级。
/// 纯值类型，间隔序列可注入，便于单测。
public struct BackoffSchedule: Equatable, Sendable {
    /// 退避间隔序列（秒），末值为封顶值。
    public let intervals: [TimeInterval]
    private var step: Int

    public init(intervals: [TimeInterval] = [4, 8, 15, 30]) {
        self.intervals = intervals.isEmpty ? [4, 8, 15, 30] : intervals
        self.step = 0
    }

    /// 当前应等待的间隔（不推进）。
    public var currentInterval: TimeInterval {
        intervals[min(step, intervals.count - 1)]
    }

    /// 返回当前间隔并推进到下一级；到达末值后保持不变。
    @discardableResult
    public mutating func next() -> TimeInterval {
        let value = currentInterval
        step = min(step + 1, intervals.count - 1)
        return value
    }

    /// 回到第一级。
    public mutating func reset() {
        step = 0
    }
}
