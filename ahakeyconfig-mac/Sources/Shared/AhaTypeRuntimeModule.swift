import Foundation

/// AhaType 生命周期 seam（WBS 5.3 切片 6，Codex 11:52/11:56 裁决）：
/// **只做生命周期 seam，不迁实体**——转写/优化器/HUD 仍在 `Sources/Utilities`，
/// 由 Studio 进程承载，本卡不得改动。
///
/// 本模块提供编排侧的统一生命周期锚点：
/// - `RuntimeOrchestratorCore.plan(for:)` 已把 `ahaType.enabled` 映射为 `.ahaType`；
/// - 本模块经 `RuntimeModuleRegistry` 启停，状态进入模块 Snapshot；
/// - 对真实引擎的控制通过 `onStart/onStop` 注入。当前 Agent 进程内无 AhaType
///   资源，注入为空操作 + 日志；Studio 侧引擎接管（WBS 5.7 Runtime client）
///   落地后，由 orchestrator 装配把策略变化桥接到 Studio，无需改本契约。
public final class AhaTypeRuntimeModule: RuntimeModule, @unchecked Sendable {
    public let id: RuntimeModuleID = .ahaType
    public private(set) var status: RuntimeModuleStatus = .idle

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
