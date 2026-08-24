import Foundation

/// 将动态灯效（`sendState` 发送能力）接入 `RuntimeModule` 生命周期的门控模块。
///
/// 职责边界（Codex 13:52 裁决）：本模块只表达「灯效发送能力已启用/已停用」，
/// `sendState`、0x90 数据包、`lastSentState`、自动回落（`pendingStateReset`）
/// 与 live-state 文件写入全部留在 Agent——看门狗仍读 Agent 的 `lastSentState`。
/// 模块 `.running` 时 Agent 才执行发送；非 `.running` 时发送被门控抑制。
public final class LightingRuntimeModule: RuntimeModule, @unchecked Sendable {
    public let id: RuntimeModuleID = .dynamicLighting
    public private(set) var status: RuntimeModuleStatus = .idle

    /// 启用/停用时的副作用钩子（装配方注入；当前为空操作，供策略化装配使用）。
    private let onStart: () -> Void
    private let onStop: () -> Void

    public init(onStart: @escaping () -> Void = {}, onStop: @escaping () -> Void = {}) {
        self.onStart = onStart
        self.onStop = onStop
    }

    public func start() async throws {
        onStart()
        status = .running
    }

    public func stop() async {
        onStop()
        status = .idle
    }
}
