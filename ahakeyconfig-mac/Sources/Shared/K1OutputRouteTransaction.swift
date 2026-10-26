import Foundation

/// One identified connection owns this transaction. Callers must not substitute
/// a reconnected device for checkSession, or reuse facts across devices.
public enum K1OutputRouteTransaction {
    public enum Failure: Error, Equatable {
        case unsupported, invalidReply, rejected, invalidTarget, transportLimit
        case changedSinceRead(K1OutputRoute), verificationMismatch, writeUnconfirmed
    }
    public struct Snapshot: Equatable, Sendable {
        public let routes: [K1OutputRoute]
        public init?(routes: [K1OutputRoute]) {
            guard routes.count == 4 else { return nil }; self.routes = routes
        }
    }
    @MainActor
    public static func read(checkSession: () throws -> Void,
                            exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> Snapshot {
        try await verifyCapability(checkSession: checkSession, exchange: exchange)
        return try await readVerified(checkSession: checkSession, exchange: exchange)
    }

    @MainActor
    public static func save(mode: UInt8, baseline: K1OutputRoute, target: K1OutputRoute,
                            maximumRequestBytes: Int, checkSession: () throws -> Void,
                            prepareHost: () throws -> Void = {}, writeStarted: () -> Void = {},
                            exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> Snapshot {
        guard mode < 4 else { throw Failure.invalidTarget }
        // BEGIN is 18 bytes; CHUNK has a 15-byte envelope. Do not open a
        // firmware transaction before discovering that this transport fits.
        guard maximumRequestBytes >= 18 else { throw Failure.transportLimit }
        try await verifyCapability(checkSession: checkSession, exchange: exchange)
        let before = try await readVerified(checkSession: checkSession, exchange: exchange)
        guard before.routes[Int(mode)] == baseline else { throw Failure.changedSinceRead(before.routes[Int(mode)]) }
        try prepareHost(); try checked(checkSession)
        guard baseline != target else { return before }
        writeStarted()
        do {
            try await publish(selector: mode, bytes: target.serialized, maximumRequestBytes: maximumRequestBytes,
                              checkSession: checkSession, exchange: exchange)
        } catch PublicationFailure.commitUnconfirmed {
            if Task.isCancelled { throw CancellationError() }
            do {
                let actual = try await readVerified(checkSession: checkSession, exchange: exchange)
                try verify(actual, before: before, mode: mode, target: target)
                return actual
            } catch { throw Failure.writeUnconfirmed }
        }
        let actual = try await readVerified(checkSession: checkSession, exchange: exchange)
        try verify(actual, before: before, mode: mode, target: target)
        return actual
    }

    enum PublicationFailure: Error { case commitUnconfirmed }

    @MainActor
    static func publish(selector: UInt8, bytes: Data, maximumRequestBytes: Int,
                        checkSession: () throws -> Void,
                        exchange: (K1OutputRouteCommand) async throws -> Data,
                        beforeCommit: () async throws -> Void = {}) async throws {
        guard maximumRequestBytes >= 18 else { throw Failure.transportLimit }
        guard bytes.count == (selector == 0xFF ? 408 : 102) else { throw Failure.invalidTarget }
        let checksum = WS3ResourcePayload.checksum(bytes), token = nonce()
        let begin = try await perform(.begin(nonce: token, selector: selector, length: UInt16(bytes.count), checksum: checksum),
                                      checkSession: checkSession, exchange: exchange)
        guard case .begun(nextOffset: 0) = begin else { throw Failure.invalidReply }
        var offset = 0
        let chunkSize = min(47, maximumRequestBytes - 15)
        while offset < bytes.count {
            let end = min(bytes.count, offset + chunkSize)
            let reply = try await perform(.chunk(token: token, selector: selector, offset: UInt16(offset), bytes: bytes.subdata(in: offset..<end)),
                                          checkSession: checkSession, exchange: exchange)
            guard case .chunkAccepted(let next) = reply, Int(next) == end else { throw Failure.invalidReply }
            offset = end
        }
        try await beforeCommit()
        do {
            let reply = try await perform(.commit(token: token, selector: selector), checkSession: checkSession, exchange: exchange)
            guard reply == .committed(checksum: checksum) else { throw Failure.invalidReply }
        } catch { throw PublicationFailure.commitUnconfirmed }
    }

    @MainActor
    static func verifyCapability(checkSession: () throws -> Void,
                                         exchange: (K1OutputRouteCommand) async throws -> Data) async throws {
        try checked(checkSession)
        let command = K1OutputRouteCommand.capability(nonce: nonce())
        let frame = try await exchange(command)
        try checked(checkSession)
        if frame == Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]) || frame == Data([0xAA, 0xBB, 0x9E, 1, 0xCC, 0xDD]) {
            throw Failure.unsupported // Receipt of an unknown command is not support.
        }
        guard let reply = K1OutputRouteReply.parse(frame, for: command) else { throw Failure.invalidReply }
        if reply == .rejected { throw Failure.rejected }
        guard reply == .capability else { throw Failure.invalidReply }
    }

    @MainActor
    static func readVerified(checkSession: () throws -> Void,
                                      exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> Snapshot {
        var routes: [K1OutputRoute] = []
        for mode: UInt8 in 0..<4 {
            var bytes = Data(), checksum: UInt32?
            while bytes.count < 102 {
                let command = K1OutputRouteCommand.read(nonce: nonce(), mode: mode, offset: UInt8(bytes.count), count: UInt8(min(42, 102 - bytes.count)))
                let reply = try await perform(command, checkSession: checkSession, exchange: exchange)
                guard case .slice(let receivedCRC, let slice) = reply,
                      checksum == nil || checksum == receivedCRC else { throw Failure.invalidReply }
                checksum = receivedCRC; bytes.append(slice)
            }
            guard WS3ResourcePayload.checksum(bytes) == checksum, let route = K1OutputRoute(serialized: bytes) else { throw Failure.invalidReply }
            routes.append(route)
        }
        return Snapshot(routes: routes)!
    }

    @MainActor
    private static func perform(_ command: K1OutputRouteCommand, checkSession: () throws -> Void,
                                 exchange: (K1OutputRouteCommand) async throws -> Data) async throws -> K1OutputRouteReply {
        try checked(checkSession)
        let frame = try await exchange(command)
        try checked(checkSession)
        guard let reply = K1OutputRouteReply.parse(frame, for: command) else { throw Failure.invalidReply }
        if reply == .rejected { throw Failure.rejected }
        return reply
    }
    private static func verify(_ actual: Snapshot, before: Snapshot, mode: UInt8, target: K1OutputRoute) throws {
        var expected = before.routes; expected[Int(mode)] = target
        guard actual.routes == expected else { throw Failure.verificationMismatch }
    }
    private static func nonce() -> UInt32 { UInt32.random(in: 1...UInt32.max) }
    private static func checked(_ checkSession: () throws -> Void) throws {
        try Task.checkCancellation(); try checkSession()
    }
}

extension K1OutputRouteTransaction.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupported: return NSLocalizedString("当前固件不支持分模式语音设置，请重新读取后使用兼容方案。", comment: "")
        case .invalidReply: return NSLocalizedString("语音设置读回无效，请重新连接后核对。", comment: "")
        case .rejected: return NSLocalizedString("键盘未能处理语音设置，请读取设备状态后再试。", comment: "")
        case .invalidTarget: return NSLocalizedString("语音设置目标无效，请重新选择模式。", comment: "")
        case .transportLimit: return NSLocalizedString("当前连接无法发送语音设置，请重新连接后再试。", comment: "")
        case .changedSinceRead: return NSLocalizedString("键盘该键已变化，请重新读取后编辑。", comment: "")
        case .verificationMismatch: return NSLocalizedString("保存后键位读回不一致，设置未确认。", comment: "")
        case .writeUnconfirmed: return NSLocalizedString("语音设置写入未确认，可能已生效；请重新连接并读取，不要反复写入。", comment: "")
        }
    }
}
