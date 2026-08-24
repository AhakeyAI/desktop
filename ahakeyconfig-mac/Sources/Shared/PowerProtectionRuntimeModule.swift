import Foundation

/// 将 `PowerProtectionManager` 接入 `RuntimeModule` 生命周期的适配模块。
///
/// 不直接持有 `PowerProtectionManager`（非 `Sendable`），而是通过闭包委托，
/// 由装配方注入具体的 begin/end 行为。这样 Registry 的 actor 隔离与
/// `PowerProtectionManager` 的 `DispatchQueue` 隔离互不侵犯。
public final class PowerProtectionRuntimeModule: RuntimeModule, @unchecked Sendable {
    public let id: RuntimeModuleID = .powerProtection
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
