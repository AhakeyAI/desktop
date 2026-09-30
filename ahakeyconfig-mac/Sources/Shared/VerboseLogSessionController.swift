import Foundation

/// 临时详细日志（TX/RX 抓包）会话：开启后固定时长自动结束。
/// 纯值类型 + 注入时钟（当前时间由调用方传入），不依赖 Timer/@MainActor，方便单元测试。
/// 调用方（BLELogStore）负责在真实时钟下调度 `advance(to:)`。
public struct VerboseLogSessionController: Equatable, Sendable {
    /// 默认会话时长：15 分钟。
    public static let defaultDuration: TimeInterval = 15 * 60

    public let duration: TimeInterval
    /// 到期时间；nil 表示会话未开启。
    public private(set) var endDate: Date?

    public init(duration: TimeInterval = VerboseLogSessionController.defaultDuration) {
        self.duration = duration
    }

    public var isActive: Bool { endDate != nil }

    /// 开启会话；重复开启会顺延到期时间。
    public mutating func start(now: Date) {
        endDate = now.addingTimeInterval(duration)
    }

    /// 手动关闭，立即生效。
    public mutating func stop() {
        endDate = nil
    }

    /// 时钟推进：已到期则自动关闭。返回本次调用是否发生了自动关闭。
    @discardableResult
    public mutating func advance(to now: Date) -> Bool {
        guard let end = endDate, now >= end else { return false }
        endDate = nil
        return true
    }
}
