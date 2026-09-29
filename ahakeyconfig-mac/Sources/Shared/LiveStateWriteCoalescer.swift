import Foundation

/// 跨进程状态通道的写前去重（阶段 4）。
///
/// Agent 占用 BLE 时每 1.5s 轮询键盘状态并发布到 `current-ide-state.json` 供 GUI 读取；
/// 键盘连着但状态静止时（绝大多数时间）内容完全相同，重复落盘只会白白唤醒 GUI 的目录监听。
/// 本类型在写前与「最后已发布快照」比较，输出三种决策：
/// - `.write`：字段真实变化（或首次发布），需要重写文件；
/// - `.touchOnly`：内容没变，但距上次任何写入已达 `touchInterval`，只更新文件 mtime
///   （GUI 侧把 mtime 当作「状态最后确认时间」；事件性写入也会刷新 mtime，见 `noteEventWrite`）；
/// - `.skip`：内容没变且 mtime 仍新鲜，什么都不做。
///
/// 事件性写入（hook stateValue / 虚拟拨杆覆盖）不走去重、每次必写，但写完后必须调
/// `noteEventWrite` 同步基准：既合并事件改动的字段，又重置 touch 计时（文件 mtime 已被刷新），
/// 避免下一次轮询回包因基准过期而误判变化。
/// 纯值类型，时钟以时间戳注入，便于单测。
public struct LiveStateWriteCoalescer: Equatable, Sendable {
    /// 发布决策。
    public enum Decision: Equatable, Sendable {
        case write
        case skip
        case touchOnly
    }

    /// 参与去重比较的字段集合（即 GUI 从共享文件消费的 agent* 字段）。
    /// 事件性写入只知道自己改动的字段；`noteEventWrite` 合并时未提供的字段保留旧值。
    public struct Snapshot: Equatable, Sendable {
        public var lightMode: Int?
        public var switchState: Int?
        public var workMode: Int?

        public init(lightMode: Int? = nil, switchState: Int? = nil, workMode: Int? = nil) {
            self.lightMode = lightMode
            self.switchState = switchState
            self.workMode = workMode
        }
    }

    /// 距上次任何写入（含事件性写入）超过该间隔且内容无变化时，输出 `.touchOnly`。
    public let touchInterval: TimeInterval
    /// 最后一次发布到文件的快照（含事件性写入合并后的结果）。
    public private(set) var lastPublished: Snapshot?
    /// 最后一次写入或 touch 文件的时间戳。
    public private(set) var lastWriteAt: TimeInterval?

    public init(touchInterval: TimeInterval = 30) {
        self.touchInterval = touchInterval
    }

    /// 轮询路径：与最后已发布快照比较，完全相同不重复落盘。
    public mutating func decision(for snapshot: Snapshot, at now: TimeInterval) -> Decision {
        guard let last = lastPublished, last == snapshot else {
            lastPublished = snapshot
            lastWriteAt = now
            return .write
        }
        guard let lastWriteAt, now - lastWriteAt < touchInterval else {
            self.lastWriteAt = now
            return .touchOnly
        }
        return .skip
    }

    /// 事件性写入已完成（文件已重写，mtime 已刷新）：合并非 nil 字段到基准，并重置 touch 计时。
    public mutating func noteEventWrite(_ partial: Snapshot, at now: TimeInterval) {
        var merged = lastPublished ?? Snapshot()
        if let v = partial.lightMode { merged.lightMode = v }
        if let v = partial.switchState { merged.switchState = v }
        if let v = partial.workMode { merged.workMode = v }
        lastPublished = merged
        lastWriteAt = now
    }
}
