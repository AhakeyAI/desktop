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
        let bytes = target.serialized
        let checksum = WS3ResourcePayload.checksum(bytes)
        let token = nonce()
        writeStarted()
        let begin = try await perform(.begin(nonce: token, selector: mode, length: 102, checksum: checksum),
                                      checkSession: checkSession, exchange: exchange)
        guard case .begun(nextOffset: 0) = begin else { throw Failure.invalidReply }
        var offset = 0
        let chunkSize = min(47, maximumRequestBytes - 15)
        while offset < bytes.count {
            let end = min(bytes.count, offset + chunkSize)
            let reply = try await perform(.chunk(token: token, selector: mode, offset: UInt16(offset), bytes: bytes.subdata(in: offset..<end)),
                                          checkSession: checkSession, exchange: exchange)
            guard case .chunkAccepted(let next) = reply, Int(next) == end else { throw Failure.invalidReply }
            offset = end
        }
        // Only COMMIT can publish the new route. If its acknowledgement is
        // lost, independently read facts once; never replay a commit or begin.
        do {
            let reply = try await perform(.commit(token: token, selector: mode), checkSession: checkSession, exchange: exchange)
            guard reply == .committed(checksum: checksum) else { throw Failure.invalidReply }
        } catch {
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

    @MainActor
    private static func verifyCapability(checkSession: () throws -> Void,
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
    private static func readVerified(checkSession: () throws -> Void,
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
