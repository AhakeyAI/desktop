import Foundation

/// 将 AI 集成（Hook 状态链、看门狗、拨杆/批准查询驱动）接入 `RuntimeModule`
/// 生命周期的适配模块。
///
/// 与 `PowerProtectionRuntimeModule` 同为闭包委托：不直接持有 Agent 内部
/// 非 Sendable 资源，由装配方注入具体启停行为。wire 协议（socket 命令与
/// 回包格式）不属于本模块职责，保持在传输层逐字不变。
public final class AIIntegrationRuntimeModule: RuntimeModule, @unchecked Sendable {
    public let id: RuntimeModuleID = .aiIntegration
    public private(set) var status: RuntimeModuleStatus = .idle

    private let onStart: () -> Void
    private let onStop: () -> Void

    public init(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
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
