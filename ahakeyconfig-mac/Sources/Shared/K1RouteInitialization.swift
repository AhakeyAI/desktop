import Foundation

/// Explicit bootstrap for an unavailable CP2.6 route record. Firmware remains
/// responsible for rejecting committed-corrupt storage; unavailable is not proof of blank flash.
public enum K1RouteInitialization {
    public struct Inputs: Equatable {
        public let voiceState: UInt8
        public let keys: [OrdinaryKeyReadback]
        public let routes: K1OutputRouteTransaction.Snapshot

        public init?(voiceState: UInt8, keys: [OrdinaryKeyReadback]) {
            guard voiceState <= 4 else { return nil }
            let routes: [K1OutputRoute]
            if voiceState == 2 {
                // The pre-CP2.6 Mac preset used Consumer Voice globally, including mode 4.
                // Do not replace that intent with inactive ordinary F18 bindings.
                guard keys.isEmpty || (keys.count == 4 && Set(keys.map(\.mode)) == Set(UInt8(0)..<4) &&
                    keys.allSatisfy({ $0.keyIndex == 0 })) else { return nil }
                routes = Array(repeating: K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))!, count: 4)
            } else {
                guard keys.count == 4, Set(keys.map(\.mode)) == Set(UInt8(0)..<4),
                      keys.allSatisfy({ $0.keyIndex == 0 && $0.isKnownEditableAction && $0.action.count <= 98 }) else {
                    return nil
                }
                var values: [K1OutputRoute] = []
                for key in keys.sorted(by: { $0.mode < $1.mode }) {
                    let action: Data
                    if key.actionType == 0 {
                        guard key.action.isEmpty else { return nil }
                        action = Data()
                    } else {
                        action = Data([key.actionType, UInt8(key.action.count)]) + key.action
                    }
                    guard let route = K1OutputRoute(kind: .ordinary, action: action) else { return nil }
                    values.append(route)
                }
                routes = values
            }
            guard let snapshot = K1OutputRouteTransaction.Snapshot(routes: routes) else { return nil }
            self.voiceState = voiceState; self.keys = keys; self.routes = snapshot
        }
    }
    public struct Preparation: Equatable {
        public let inputs: Inputs
        public var routes: K1OutputRouteTransaction.Snapshot { inputs.routes }
        fileprivate init(inputs: Inputs) { self.inputs = inputs }
    }
    public enum Failure: Error, Equatable {
        case confirmationRequired, alreadyAvailable, restoreUnfinished, unsafeRecordState
        case sourceUnavailable, changedSinceRead, writeUnconfirmed, verificationMismatch
        case hostBusy
    }

    @MainActor
    public static func prepare(checkSession: () throws -> Void,
                               exchange: (K1OutputRouteCommand) async throws -> Data,
                               readInputs: () async throws -> Inputs) async throws -> Preparation {
        try await requireUnavailableRecord(checkSession: checkSession, exchange: exchange)
        try await K1OutputRouteTransaction.verifyCapability(checkSession: checkSession, exchange: exchange)
        try checked(checkSession)
        let inputs = try await readInputs()
        try checked(checkSession)
        return Preparation(inputs: inputs)
    }

    @MainActor
    public static func initialize(baseline: Preparation, userConfirmed: Bool,
        maximumRequestBytes: Int, checkSession: () throws -> Void,
        exchange: (K1OutputRouteCommand) async throws -> Data,
        readInputs: () async throws -> Inputs,
        prepareHost: () throws -> Void = {},
        writeStarted: () -> Void = {}) async throws -> K1OutputRouteTransaction.Snapshot {
        guard userConfirmed else { throw Failure.confirmationRequired }
        guard maximumRequestBytes >= 18 else { throw K1OutputRouteTransaction.Failure.transportLimit }
        let before = try await prepare(checkSession: checkSession, exchange: exchange, readInputs: readInputs)
        guard before.routes == baseline.routes else { throw Failure.changedSinceRead }
        let payload = before.routes.routes.reduce(into: Data()) { $0.append($1.serialized) }
        try prepareHost()
        try checked(checkSession)
        writeStarted()
        do {
            try await K1OutputRouteTransaction.publish(selector: 0xFF, bytes: payload,
                maximumRequestBytes: maximumRequestBytes, checkSession: checkSession, exchange: exchange,
                beforeCommit: {
                    try await requireUnavailableRecord(checkSession: checkSession, exchange: exchange)
                    let latest = try await readInputs()
                    try checked(checkSession)
                    guard latest.routes == before.routes else { throw Failure.changedSinceRead }
                })
        } catch K1OutputRouteTransaction.PublicationFailure.commitUnconfirmed {
            if Task.isCancelled { throw CancellationError() }
            do {
                let actual = try await K1OutputRouteTransaction.readVerified(checkSession: checkSession, exchange: exchange)
                guard actual == before.routes else { throw Failure.verificationMismatch }
                return actual
            } catch { throw Failure.writeUnconfirmed }
        }
        do {
            let actual = try await K1OutputRouteTransaction.readVerified(checkSession: checkSession, exchange: exchange)
            guard actual == before.routes else { throw Failure.verificationMismatch }
            return actual
        } catch Failure.verificationMismatch { throw Failure.verificationMismatch }
        catch { throw Failure.writeUnconfirmed }
    }

    @MainActor
    private static func requireUnavailableRecord(checkSession: () throws -> Void,
                                                exchange: (K1OutputRouteCommand) async throws -> Data) async throws {
        let snapshot = try await RestoreInitializationTransaction.read(checkSession: checkSession, exchange: exchange)
        switch snapshot.state {
        case .never, .complete: throw Failure.alreadyAvailable
        case .inProgress, .incomplete: throw Failure.restoreUnfinished
        case .storageUnavailable:
            guard !snapshot.handled, snapshot.attempt == 0 else { throw Failure.unsafeRecordState }
        case .unsupported: throw K1OutputRouteTransaction.Failure.unsupported
        }
    }
    private static func checked(_ checkSession: () throws -> Void) throws {
        try Task.checkCancellation(); try checkSession()
    }
}

extension K1RouteInitialization.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .confirmationRequired: return NSLocalizedString("请先确认四个模式的语音初始化方案，本次尚未写入。", comment: "")
        case .alreadyAvailable: return NSLocalizedString("键盘已有分模式语音记录，请重新读取后按模式修改，不要初始化覆盖。", comment: "")
        case .restoreUnfinished: return NSLocalizedString("键盘的恢复尚未完成，请先在模式按钮的恢复区域处理。", comment: "")
        case .unsafeRecordState: return NSLocalizedString("语音记录状态无法确认，本次未初始化。", comment: "")
        case .sourceUnavailable: return NSLocalizedString("无法完整读取现有语音键位，保持原设置，不使用默认值覆盖。", comment: "")
        case .changedSinceRead: return NSLocalizedString("四模式语音设置已变化，请重新读取方案后确认。", comment: "")
        case .writeUnconfirmed: return NSLocalizedString("语音初始化结果未确认，可能已生效；请重新连接后读取，不要重复提交。", comment: "")
        case .verificationMismatch: return NSLocalizedString("初始化后的四模式语音读回不一致，尚未确认成功。", comment: "")
        case .hostBusy: return NSLocalizedString("请先停止录音或松开语音键，再初始化语音设置。本次尚未写入。", comment: "")
        }
    }
}
