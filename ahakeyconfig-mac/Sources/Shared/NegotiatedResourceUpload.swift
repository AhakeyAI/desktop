import Foundation

public enum NegotiatedResourceUploadFailure: Error, LocalizedError, Equatable {
    case timeout, invalidReply, rejected(UInt8), unsupported, uncertain, recoveryExpired
    public var errorDescription: String? {
        switch self {
        case .timeout: return NSLocalizedString("素材请求超时，正在核对键盘接收状态。", comment: "")
        case .unsupported: return NSLocalizedString("键盘未确认支持快速素材上传。", comment: "")
        case .uncertain, .recoveryExpired: return NSLocalizedString("素材事务未确认。请重新连接并读取画面信息后重试；不要直接重复写入。", comment: "")
        case .invalidReply: return NSLocalizedString("素材回复与本次上传不一致，未确认成功。", comment: "")
        case .rejected: return NSLocalizedString("键盘拒绝了素材请求，上传未完成。", comment: "")
        }
    }
}

/// ACR3 and ACR4 retain separate wire validators and share only the verified
/// transaction state machine. One owner holds the *whole* command session, not just individual exchanges.
/// A timeout with a correlated response is resolved by STATUS; BEGIN is never
/// blindly retried, and COMMIT needs persisted metadata, not merely its ACK.
@MainActor
public enum ConfirmedNegotiatedResourceUpload {
    public typealias Exchange = (Data) async throws -> Data
    public struct Selection {
        public let object: any NegotiatedResourceObject
        public let chunkSize: Int
    }

    /// Preserve original pixels whenever lossless encoding meets the budget;
    /// otherwise negotiate explicit spatial compression. Unsupported firmware
    /// returns nil for the existing CP2 compatibility path, never a false CAPS.
    public static func prepare(payload: WS3ResourcePayload, exchange: Exchange) async throws -> Selection? {
        let lossless = ACR4ResourceObject(payload: payload)
        if lossless.bytes.count <= 50_000, let chunk = try await capability(exchange: exchange) {
            return Selection(object: lossless, chunkSize: chunk)
        }
        if let chunk = try await compactCapability(exchange: exchange) {
            return Selection(object: CompactResourceObject(payload: payload), chunkSize: chunk)
        }
        return nil
    }

    public static func capability(exchange: Exchange) async throws -> Int? {
        let command = ACR4Command(.caps, token: nonce())
        let raw = try await exchange(command.request)
        if command.isLegacyUnsupportedReply(raw) { return nil }
        // A legacy untagged ACK is negative capability evidence only.
        if raw.count == 6, Array(raw.prefix(3)) == [0xAA, 0xBB, 0x9E],
           raw[3] <= 1, Array(raw.suffix(2)) == [0xCC, 0xDD] { return nil }
        guard let reply = ACR4Reply(frame: raw, command: command) else { throw NegotiatedResourceUploadFailure.invalidReply }
        if reply.status == 2 { return nil }
        guard reply.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(reply.status) }
        guard let size = reply.capabilityChunk else { throw NegotiatedResourceUploadFailure.unsupported }
        return size
    }

    public static func compactCapability(exchange: Exchange) async throws -> Int? {
        let command = CompactResourceCommand(.caps, token: nonce())
        let raw = try await exchange(command.request)
        if command.isLegacyUnsupportedReply(raw) { return nil }
        if raw.count == 6, Array(raw.prefix(3)) == [0xAA, 0xBB, 0x9E], raw[3] <= 1,
           Array(raw.suffix(2)) == [0xCC, 0xDD] { return nil }
        guard let reply = CompactResourceReply(frame: raw, command: command) else { throw NegotiatedResourceUploadFailure.invalidReply }
        if reply.status == 2 { return nil }
        guard reply.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(reply.status) }
        guard let size = reply.capabilityChunk else { throw NegotiatedResourceUploadFailure.unsupported }
        return size
    }

    public static func run(object: any NegotiatedResourceObject, baseline: WS3DisplaySnapshot,
                           generation: UInt64, chunkSize: Int,
                           checkSession: @escaping () throws -> Void,
                           exchange: @escaping Exchange,
                           progress: (Int, Int) -> Void = { _, _ in }) async throws -> WS3ResourceReadback {
        guard object.entry < 19, (1...WS3ResourceReadback.maximumFrames(object.entry)).contains(object.frames),
              object.bytes.count >= 16, object.bytes.count <= (object.format == .compact ? 50_000 : 307_240),
              object.bytes[6] == UInt8(object.frames), object.expandedBytes == UInt32(object.frames) * WS3ResourceReadback.frameBytes else {
            throw WS3ResourceUploadError.invalidPayload
        }
        guard baseline.verifiesDisplaySettings(in: generation),
              let previous = baseline.resources.first(where: { $0.id == object.entry }),
              !baseline.resources.contains(where: { $0.writeState == .writing }) else {
            throw WS3ResourceUploadError.unverifiedConnection
        }
        guard (1...128).contains(chunkSize) else { throw WS3ResourceUploadError.invalidMTU }
        let transaction = Transaction(object: object, checkSession: checkSession, exchange: exchange)
        // The old 0x88 metadata and ACR4 metadata describe the same physical
        // slots, so this also detects changes made after the UI readback.
        guard try await transaction.metadata() == previous else { throw WS3ResourceUploadError.conflict }
        do {
            try Task.checkCancellation(); try checkSession()
            try await transaction.begin()
            var offset = 16
            progress(offset, object.bytes.count)
            while offset < object.bytes.count {
                try Task.checkCancellation(); try checkSession()
                let end = min(offset + chunkSize, object.bytes.count)
                try await transaction.chunk(start: offset, end: end)
                offset = end; progress(offset, object.bytes.count)
            }
            return try await transaction.commit()
        } catch {
            guard transaction.beginAttempted else { throw error }
            // Unstructured cleanup deliberately does not inherit cancellation.
            // Still requires the same live connection generation and token.
            let cleanup = Task { @MainActor in try await transaction.cancel() }
            do { try await cleanup.value }
            catch { throw NegotiatedResourceUploadFailure.uncertain }
            throw error
        }
    }

    private static func nonce() -> UInt32 { UInt32.random(in: 1...UInt32.max) }

    @MainActor
    private final class Transaction {
        let object: any NegotiatedResourceObject
        let token = ConfirmedNegotiatedResourceUpload.nonce()
        let checkSession: () throws -> Void
        let exchange: Exchange
        var beginAttempted = false
        var verified: UInt32 = 0
        init(object: any NegotiatedResourceObject, checkSession: @escaping () throws -> Void, exchange: @escaping Exchange) {
            self.object = object; self.checkSession = checkSession; self.exchange = exchange
        }
        func ask(_ operation: ACR4Command.Operation, fields: Data = Data(), fresh: Bool = false) async throws -> ACR4Reply {
            try checkSession()
            let correlation = fresh ? ConfirmedNegotiatedResourceUpload.nonce() : token
            switch object.format {
            case .lossless:
                let command = ACR4Command(operation, token: correlation, fields: fields)
                guard ACR4Command(request: command.request) != nil else { throw WS3ResourceUploadError.invalidPayload }
                let raw = try await exchange(command.request); try checkSession()
                guard let value = ACR4Reply(frame: raw, command: command) else { throw NegotiatedResourceUploadFailure.invalidReply }
                return value
            case .compact:
                let command = CompactResourceCommand(operation, token: correlation, fields: fields)
                guard CompactResourceCommand(request: command.request) != nil else { throw WS3ResourceUploadError.invalidPayload }
                let raw = try await exchange(command.request); try checkSession()
                guard let value = CompactResourceReply(frame: raw, command: command) else { throw NegotiatedResourceUploadFailure.invalidReply }
                if operation == .chunk && value.status == 0 {
                    let done = ACR4Command.u32([UInt8](value.fields), 5)
                    guard done >= verified, done <= object.expandedBytes else { throw NegotiatedResourceUploadFailure.invalidReply }
                    verified = done
                    return ACR4Reply(status: 0, fields: Data(value.fields.prefix(5)))
                }
                return ACR4Reply(status: value.status, fields: value.fields)
            }
        }
        func metadata() async throws -> WS3ResourceReadback {
            let value = try await ask(.metadata, fields: Data([object.entry]), fresh: true)
            guard value.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(value.status) }
            guard let resource = value.resource(entry: object.entry) else { throw NegotiatedResourceUploadFailure.invalidReply }
            return resource
        }
        func settled() async throws -> (state: UInt8, offset: UInt32)? {
            let deadline = ProcessInfo.processInfo.systemUptime + 90
            while ProcessInfo.processInfo.systemUptime < deadline {
                let value: ACR4Reply
                do { value = try await ask(.status) }
                catch NegotiatedResourceUploadFailure.timeout { continue }
                if value.status == 11 { return nil }
                guard value.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(value.status) }
                let b = [UInt8](value.fields), next = ACR4Command.u32(b, 2), done = ACR4Command.u32(b, 6)
                guard b[0] <= 4, b[1] == object.entry, next <= object.bytes.count,
                      done >= verified, done <= object.expandedBytes, b[10] <= 11 else { throw NegotiatedResourceUploadFailure.invalidReply }
                verified = done
                if b[0] != 2 && b[0] != 3 { return (b[0], next) }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw NegotiatedResourceUploadFailure.recoveryExpired
        }
        func begin() async throws {
            let fields = Data([object.entry]) + ACR4Command.le(UInt32(object.bytes.count)) +
                ACR4Command.le(WS3ResourcePayload.checksum(object.bytes)) + object.bytes.prefix(16)
            beginAttempted = true
            do {
                let value = try await ask(.begin, fields: fields)
                guard value.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(value.status) }
                guard value.fields == ACR4Command.le(16) + ACR4Command.le(object.expandedBytes) else { throw NegotiatedResourceUploadFailure.invalidReply }
            } catch NegotiatedResourceUploadFailure.timeout {
                guard let state = try await settled(), state.state == 1, state.offset == 16 else { throw NegotiatedResourceUploadFailure.uncertain }
            }
        }
        func chunk(start: Int, end: Int) async throws {
            let fields = ACR4Command.le(UInt32(start)) + Data([UInt8(end-start)]) + object.bytes.subdata(in: start..<end)
            for _ in 0..<5 {
                do {
                    let value = try await ask(.chunk, fields: fields)
                    if value.status == 0 && value.fields == ACR4Command.le(UInt32(end)) + Data([UInt8(end-start)]) { return }
                    guard value.status == 0 || value.status == 7 else { throw NegotiatedResourceUploadFailure.rejected(value.status) }
                } catch NegotiatedResourceUploadFailure.timeout { /* Resolve the ambiguous ACK with STATUS. */ }
                guard let state = try await settled(), state.state == 1 else { throw NegotiatedResourceUploadFailure.uncertain }
                if state.offset == end { return }
                guard state.offset == start else { throw NegotiatedResourceUploadFailure.uncertain }
                try Task.checkCancellation()
            }
            throw NegotiatedResourceUploadFailure.recoveryExpired
        }
        func commit() async throws -> WS3ResourceReadback {
            try Task.checkCancellation()
            do {
                let value = try await ask(.commit)
                guard value.status == 0 else { throw NegotiatedResourceUploadFailure.rejected(value.status) }
                let expected = Data([object.entry, UInt8(object.frames)]) + ACR4Command.le(object.expandedBytes) + ACR4Command.le(object.expandedCRC)
                guard value.fields == expected else { throw NegotiatedResourceUploadFailure.invalidReply }
            } catch NegotiatedResourceUploadFailure.timeout { /* A valid durable metadata response can settle COMMIT. */ }
            let resource = try await metadata()
            guard resource.reportsValidUserResource, resource.frames == object.frames,
                  resource.payloadBytes == object.expandedBytes, resource.crc32 == object.expandedCRC else {
                throw WS3ResourceUploadError.verificationMismatch
            }
            return resource
        }
        func cancel() async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 90
            while ProcessInfo.processInfo.systemUptime < deadline {
                do {
                    let value = try await ask(.cancel)
                    if value.status == 0 {
                        let b = [UInt8](value.fields)
                        guard b[0] == 0, b[1] == object.entry, ACR4Command.u32(b, 2) <= object.expandedBytes else { throw NegotiatedResourceUploadFailure.invalidReply }
                        return
                    }
                } catch NegotiatedResourceUploadFailure.timeout { /* Check transaction and metadata before retrying CANCEL. */ }
                if let state = try await settled() {
                    guard state.state != 4 else { throw NegotiatedResourceUploadFailure.uncertain }
                } else {
                    let resource = try await metadata()
                    guard resource.writeState == .empty || resource.writeState == .invalid else { throw NegotiatedResourceUploadFailure.uncertain }
                    return
                }
            }
            throw NegotiatedResourceUploadFailure.recoveryExpired
        }
    }
}
