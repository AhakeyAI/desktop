import Foundation

/// Reacquire a short lease and compare device facts before a component write.
enum StudioConfirmedEdit {
    enum Failure: Error, LocalizedError {
        case verificationMismatch
        var errorDescription: String? { NSLocalizedString("写入后读回值不一致，请重新读取后核对。", comment: "") }
    }
    struct Fact<Value: Equatable>: Equatable {
        let deviceID: String
        let value: Value
    }
    enum Result<Value: Equatable>: Equatable {
        case conflict(Fact<Value>)
        case saved(Fact<Value>, wrote: Bool)
        case unconfirmed(Fact<Value>)
    }

    @MainActor
    static func run<Value: Equatable>(baseline: Fact<Value>, desired: Value, requiresPersistence: Bool = false,
        session: StudioInspectorSession,
        read: (StudioInspectorSession.Context) async throws -> Value,
        write: (Value, StudioInspectorSession.Context) async throws -> Value
    ) async throws -> Result<Value> {
        try await session.withConnection(expectedDeviceID: baseline.deviceID) { context in
            let actual = try await read(context)
            try session.validate(context)
            let fact = Fact(deviceID: context.deviceID, value: actual)
            guard actual == baseline.value else { return .conflict(fact) }
            guard actual != desired else {
                return requiresPersistence ? .unconfirmed(fact) : .saved(fact, wrote: false)
            }
            try Task.checkCancellation()
            let confirmed = try await write(actual, context)
            guard confirmed == desired else { throw Failure.verificationMismatch }
            return .saved(Fact(deviceID: context.deviceID, value: confirmed), wrote: true)
        }
    }
}
