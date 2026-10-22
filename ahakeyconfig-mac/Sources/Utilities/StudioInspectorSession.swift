import Combine
import Foundation

/// One short configuration operation. Draft editing does not hold this lease.
/// The production adapter retains the existing App/Agent owner machinery.
@MainActor
final class StudioInspectorSession: ObservableObject {
    struct Access {
        let begin: () throws -> UInt64
        let isCurrent: (UInt64) -> Bool
        let isReady: () -> Bool
        let generation: () -> UInt64
        let deviceID: () -> String
        let release: (UInt64) -> Void
        let pause: () async throws -> Void
    }

    enum Failure: Error, LocalizedError, Equatable {
        case busy, connectionTimeout, ownershipChanged, deviceChanged, sessionChanged
        var errorDescription: String? {
            switch self {
            case .busy: return NSLocalizedString("正在处理当前组件，请完成或取消后再操作。", comment: "")
            case .connectionTimeout: return NSLocalizedString("未能取得键盘配置连接；未开始本次操作，已尝试交还后台。", comment: "")
            case .ownershipChanged: return NSLocalizedString("连接归属已改变，本次操作未确认。", comment: "")
            case .deviceChanged: return NSLocalizedString("连接的键盘已改变，请重新读取后操作。", comment: "")
            case .sessionChanged: return NSLocalizedString("键盘连接已更新，本次操作未确认；已发出的修改可能生效。", comment: "")
            }
        }
    }

    struct Context: Equatable {
        let deviceID: String
        let generation: UInt64
    }

    @Published private(set) var isBusy = false
    private let access: Access
    private let timeout: Duration

    init(access: Access, timeout: Duration = .seconds(15)) {
        self.access = access
        self.timeout = timeout
    }

    /// The caller captures a component target before entering. `Context` is
    /// usable only inside the operation, never as authorization for a later save.
    func withConnection<Value>(expectedDeviceID: String? = nil,
                               operation: (Context) async throws -> Value) async throws -> Value {
        guard !isBusy else { throw Failure.busy }
        try Task.checkCancellation()
        isBusy = true
        defer { isBusy = false }
        let lease = try access.begin()
        // Check ownership before releasing: an old finally must not change a
        // user's newer App/Agent choice, even if it selected App again.
        defer { if access.isCurrent(lease) { access.release(lease) } }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            guard access.isCurrent(lease) else { throw Failure.ownershipChanged }
            if access.isReady() { break }
            guard ContinuousClock.now < deadline else { throw Failure.connectionTimeout }
            try await access.pause()
        }
        let context = Context(deviceID: access.deviceID(), generation: access.generation())
        guard !context.deviceID.isEmpty,
              expectedDeviceID.map({ $0 == context.deviceID }) ?? true else { throw Failure.deviceChanged }
        let result = try await operation(context)
        try Task.checkCancellation()
        guard access.isCurrent(lease) else { throw Failure.ownershipChanged }
        guard access.isReady(), access.generation() == context.generation else { throw Failure.sessionChanged }
        guard access.deviceID() == context.deviceID else { throw Failure.deviceChanged }
        return result
    }
}
