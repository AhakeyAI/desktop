import Foundation

/// Restore is a whole-device mutation, separate from a repeatable per-mode K1 edit.
public enum RestoreInitializationTransaction {
    public struct Snapshot: Equatable, Sendable {
        public let handled: Bool
        public let state: K1RestoreState
        public let attempt: UInt32
        public init?(handled: Bool, state: K1RestoreState, attempt: UInt32) {
            switch state {
            case .never: guard attempt == 0 else { return nil }
            case .inProgress, .incomplete, .complete: guard attempt > 0 else { return nil }
            case .storageUnavailable, .unsupported: break
            }
            self.handled = handled; self.state = state; self.attempt = attempt
        }
        public var canStart: Bool { handled && [.never, .incomplete, .complete].contains(state) && attempt < UInt32.max }
    }
    public enum Result: Equatable, Sendable {
        case verified(Snapshot)
        case needsReadback(Snapshot)
        case unfinished(Snapshot)
        case refused(Snapshot)
    }
    public enum Failure: Error, Equatable {
        case unsupported, invalidReply, confirmationRequired, externalPowerRequired
        case changedSinceRead, unavailable, writeUnconfirmed
    }

    @MainActor
    public static func read(checkSession: () throws -> Void,
                            exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> Snapshot {
        try await perform(.restoreStatus(nonce: nonce()), checkSession: checkSession, exchange: exchange)
    }

    @MainActor
    public static func start(baseline: Snapshot, userConfirmed: Bool, usbPowerConfirmed: Bool,
                             checkSession: () throws -> Void,
                             exchange: (K1OutputRouteCommand) async throws -> Data,
                             writeStarted: () -> Void,
                             verifyDefaults: () async throws -> Bool) async throws -> Result {
        guard userConfirmed else { throw Failure.confirmationRequired }
        guard usbPowerConfirmed else { throw Failure.externalPowerRequired }
        let before = try await read(checkSession: checkSession, exchange: exchange)
        guard before == baseline else { throw Failure.changedSinceRead }
        guard before.canStart else { throw Failure.unavailable }
        try checked(checkSession)
        writeStarted()
        let started: Snapshot
        do {
            // Exactly one mutation attempt. A lost response never schedules a retry.
            // Preserve v1 first/retry behavior on older firmware. Only an explicit
            // repeat from COMPLETE uses the additive v2 exact-next-attempt contract.
            // A status/catalog read does not prove v2 support; never downgrade on failure.
            let command: K1OutputRouteCommand = before.state == .complete
                ? .startRestoreV2(nonce: nonce(), expectedNextAttempt: before.attempt + 1)
                : .startRestore(nonce: nonce())
            started = try await perform(command, checkSession: checkSession, exchange: exchange)
        } catch {
            throw Failure.writeUnconfirmed
        }
        if !started.handled {
            if started.attempt == before.attempt, started.state == before.state { return .refused(started) }
            if started.attempt == before.attempt + 1 { return .unfinished(started) }
            throw Failure.writeUnconfirmed
        }
        guard started.attempt == before.attempt + 1 else { throw Failure.writeUnconfirmed }
        guard started.state == .complete else { return .unfinished(started) }
        return try await verify(baseline: started, checkSession: checkSession,
                                exchange: exchange, verifyDefaults: verifyDefaults)
    }

    /// Reconnect recovery is read-only, even when the last start result was lost.
    @MainActor
    public static func verify(baseline: Snapshot, checkSession: () throws -> Void,
                              exchange: (K1OutputRouteCommand) async throws -> Data,
                              verifyDefaults: () async throws -> Bool) async throws -> Result {
        let before = try await read(checkSession: checkSession, exchange: exchange)
        guard before == baseline else { throw Failure.changedSinceRead }
        guard before.handled, before.state == .complete else { return .unfinished(before) }
        try checked(checkSession)
        let matches = try await verifyDefaults()
        try checked(checkSession)
        let after = try await read(checkSession: checkSession, exchange: exchange)
        guard after == before else { throw Failure.changedSinceRead }
        return matches ? .verified(after) : .needsReadback(after)
    }

    @MainActor
    private static func perform(_ command: K1OutputRouteCommand,
                                checkSession: () throws -> Void,
                                exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> Snapshot {
        try checked(checkSession)
        let frame = try await exchange(command)
        try checked(checkSession)
        if frame == Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]) ||
            frame == Data([0xAA, 0xBB, 0x9E, 1, 0xCC, 0xDD]) { throw Failure.unsupported }
        guard case .restore(let handled, let state, let attempt) = K1OutputRouteReply.parse(frame, for: command),
              let value = Snapshot(handled: handled, state: state, attempt: attempt) else { throw Failure.invalidReply }
        guard state != .unsupported else { throw Failure.unsupported }
        return value
    }
    private static func nonce() -> UInt32 { UInt32.random(in: 1...UInt32.max) }
    private static func checked(_ checkSession: () throws -> Void) throws {
        try Task.checkCancellation()
        try checkSession()
    }
}

extension RestoreInitializationTransaction.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported: return NSLocalizedString("当前固件不支持恢复初始化。", comment: "")
        case .invalidReply: return NSLocalizedString("恢复状态读回无效，请重新连接后核对。", comment: "")
        case .confirmationRequired: return NSLocalizedString("请先确认恢复影响范围，本次尚未执行。", comment: "")
        case .externalPowerRequired: return NSLocalizedString("请连接键盘 USB 供电并确认后再恢复。", comment: "")
        case .changedSinceRead: return NSLocalizedString("恢复状态已变化，请重新读取后确认。", comment: "")
        case .unavailable: return NSLocalizedString("当前状态无法开始恢复，请读取并处理未完成提示。", comment: "")
        case .writeUnconfirmed: return NSLocalizedString("恢复结果未确认，可能已执行；请重新连接并读取状态，不要重复恢复。", comment: "")
        }
    }
}
