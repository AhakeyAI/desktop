import Foundation

/// 模块生命周期状态。
public enum RuntimeModuleStatus: Equatable, Sendable {
    case idle
    case running
    case failed(RuntimeModuleError)
    case stopping
}

/// 模块级错误类型，隔离于系统错误之上。
public enum RuntimeModuleError: Error, Equatable, Sendable {
    case startFailed(module: RuntimeModuleID, underlying: String)
    case stopFailed(module: RuntimeModuleID, underlying: String)
    case transitionRejected(module: RuntimeModuleID, reason: String)
}

/// RuntimeOrchestrator 管辖的后台模块契约。
///
/// 实现者负责自身的线程模型；Registry 通过 actor 隔离保证并发安全。
public protocol RuntimeModule: Sendable {
    var id: RuntimeModuleID { get }
    var status: RuntimeModuleStatus { get }

    /// 启动模块。失败时抛出 `RuntimeModuleError`。
    func start() async throws

    /// 停止模块。不应抛出——失败时通过状态报告。
    func stop() async
}
