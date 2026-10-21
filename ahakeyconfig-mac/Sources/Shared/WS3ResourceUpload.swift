import Foundation

public enum WS3ResourceUploadError: Error, LocalizedError, Equatable {
    case uploadInProgress
    case invalidPayload, tooManyFrames(Int), invalidMTU, unverifiedConnection, conflict, rejected(UInt8, UInt8), invalidReply, verificationMismatch
    public var errorDescription: String? {
        switch self {
        case .uploadInProgress: return NSLocalizedString("键盘仍有未完成的素材上传。请正常重启键盘，重新连接并读取显示信息后再试。", comment: "")
        case .invalidPayload: return NSLocalizedString("素材格式无效，请重新选择图片或 GIF。", comment: "")
        case .tooManyFrames(let max): return String(format: NSLocalizedString("此素材位置最多支持 %d 帧，请缩短动画后重试。", comment: ""), max)
        case .invalidMTU: return NSLocalizedString("当前蓝牙通道不能发送素材分块，请重新连接。", comment: "")
        case .unverifiedConnection: return NSLocalizedString("请在当前连接重新读取显示信息，再上传素材。", comment: "")
        case .conflict: return NSLocalizedString("键盘素材已变化，请重新读取后再上传。", comment: "")
        case .rejected: return NSLocalizedString("键盘拒绝了素材请求，上传未完成。", comment: "")
        case .invalidReply: return NSLocalizedString("素材上传回复无效，上传未确认。", comment: "")
        case .verificationMismatch: return NSLocalizedString("上传后素材元数据不一致，未确认成功，请重新连接并读取。", comment: "")
        }
    }
}

/// CP2 wire payload: each 160x80 RGB565-BE image occupies seven 4K sectors.
/// Padding is part of the transmitted bytes and CRC, never silently omitted.
public struct WS3ResourcePayload: Equatable, Sendable {
    public let entryID: UInt8
    public let frameCount: UInt16
    public let bytes: Data
    public let crc32: UInt32
    public init(entryID: UInt8, frames: [Data]) throws {
        guard entryID < 19, !frames.isEmpty, frames.allSatisfy({ $0.count == 25_600 }) else {
            throw WS3ResourceUploadError.invalidPayload
        }
        let maximum = Int(WS3ResourceReadback.maximumFrames(entryID))
        guard frames.count <= maximum else { throw WS3ResourceUploadError.tooManyFrames(maximum) }
        self.entryID = entryID; frameCount = UInt16(frames.count)
        var payload = Data(capacity: frames.count * Int(WS3ResourceReadback.frameBytes))
        for frame in frames {
            payload.append(frame)
            payload.append(Data(repeating: 0xFF, count: Int(WS3ResourceReadback.frameBytes) - frame.count))
        }
        bytes = payload; crc32 = Self.checksum(payload)
    }
    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB88320) }
        }
        return ~crc
    }
}

public enum WS3ResourceUploadCommand {
    case begin(WS3ResourcePayload)
    case chunk(entry: UInt8, offset: UInt32, bytes: Data)
    case commit(entry: UInt8)

    public var request: Data {
        var result = Data([0xAA, 0xBB])
        switch self {
        case .begin(let payload):
            result.append(contentsOf: [0x8A, payload.entryID])
            result.append(Self.le(UInt32(payload.bytes.count), count: 4))
            result.append(Self.le(UInt32(payload.frameCount), count: 2))
            result.append(Self.le(payload.crc32, count: 4))
        case .chunk(let entry, let offset, let bytes):
            result.append(contentsOf: [0x8B, entry]); result.append(Self.le(offset, count: 4))
            result.append(UInt8(clamping: bytes.count)); result.append(bytes)
        case .commit(let entry): result.append(contentsOf: [0x8C, entry])
        }
        result.append(contentsOf: [0xCC, 0xDD]); return result
    }
    private static func le(_ value: UInt32, count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    public static func validRequest(_ request: Data) -> Bool {
        let b = [UInt8](request)
        guard b.count >= 6, b[0...1] == [0xAA, 0xBB], b.suffix(2) == [0xCC, 0xDD], b[3] < 19 else { return false }
        func u32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[offset + $1]) << ($1 * 8) } }
        switch b[2] {
        case 0x8A:
            guard b.count == 16 else { return false }
            let frames = UInt16(b[8]) | UInt16(b[9]) << 8
            return frames > 0 && frames <= WS3ResourceReadback.maximumFrames(b[3]) && u32(4) == UInt32(frames) * WS3ResourceReadback.frameBytes
        case 0x8B:
            guard b.count >= 12, (1...48).contains(Int(b[8])), b.count == Int(b[8]) + 11 else { return false }
            let maxBytes = UInt32(WS3ResourceReadback.maximumFrames(b[3])) * WS3ResourceReadback.frameBytes
            return u32(4) < maxBytes && UInt32(b[8]) <= maxBytes - u32(4)
        case 0x8C: return b.count == 6
        default: return false // 8D clears a resource; it is never upload cancellation.
        }
    }
}

@MainActor
public enum ConfirmedWS3ResourceUpload {
    public static func run(payload: WS3ResourcePayload, baseline: WS3DisplaySnapshot,
                           generation: UInt64, maximumWriteLength: Int,
                           checkSession: () throws -> Void,
                           exchange: (Data) async throws -> Data,
                           progress: (Int, Int) -> Void = { _, _ in }) async throws -> WS3ResourceReadback {
        guard baseline.verifiesDisplaySettings(in: generation),
              let previous = baseline.resources.first(where: { $0.id == payload.entryID }) else {
            throw WS3ResourceUploadError.unverifiedConnection
        }
        guard !baseline.resources.contains(where: { $0.writeState == .writing }) else {
            throw WS3ResourceUploadError.uploadInProgress
        }
        // BEGIN is 16B. A CHUNK has 11B framing/selector/offset overhead.
        guard maximumWriteLength >= 16 else { throw WS3ResourceUploadError.invalidMTU }
        let chunkSize = min(48, maximumWriteLength - 11)
        func checked(_ request: Data) async throws -> Data {
            try Task.checkCancellation(); try checkSession()
            let reply = try await exchange(request)
            try Task.checkCancellation(); try checkSession()
            return reply
        }
        func read() async throws -> WS3ResourceReadback {
            let basic = WS3DisplayItem.resourceBasic(payload.entryID), integrity = WS3DisplayItem.resourceIntegrity(payload.entryID)
            let basicReply = try await checked(basic.request!)
            let integrityReply = try await checked(integrity.request!)
            guard let value = WS3ResourceReadback(id: payload.entryID,
                basic: WS3DisplayValue.parse(basicReply, for: basic) ?? .unsupported,
                integrity: WS3DisplayValue.parse(integrityReply, for: integrity) ?? .unsupported) else {
                throw WS3ResourceUploadError.invalidReply
            }
            return value
        }
        func send(_ command: WS3ResourceUploadCommand) async throws {
            let request = command.request
            guard WS3ResourceUploadCommand.validRequest(request), request.count <= maximumWriteLength else {
                throw WS3ResourceUploadError.invalidPayload
            }
            let reply = [UInt8](try await checked(request))
            guard reply.count == 6, reply[0...2] == [0xAA, 0xBB, request[2]], reply.suffix(2) == [0xCC, 0xDD] else {
                throw WS3ResourceUploadError.invalidReply
            }
            guard reply[3] == 0 else { throw WS3ResourceUploadError.rejected(request[2], reply[3]) }
        }
        let fresh = try await read()
        guard fresh.writeState != .writing else { throw WS3ResourceUploadError.uploadInProgress }
        guard fresh == previous else { throw WS3ResourceUploadError.conflict }
        try await send(.begin(payload))
        progress(0, payload.bytes.count)
        for offset in stride(from: 0, to: payload.bytes.count, by: chunkSize) {
            let end = min(payload.bytes.count, offset + chunkSize)
            try await send(.chunk(entry: payload.entryID, offset: UInt32(offset), bytes: payload.bytes.subdata(in: offset..<end)))
            progress(end, payload.bytes.count)
        }
        try await send(.commit(entry: payload.entryID))
        let actual = try await read()
        guard actual.reportsValidUserResource, actual.frames == payload.frameCount,
              actual.payloadBytes == UInt32(payload.bytes.count), actual.crc32 == payload.crc32 else {
            throw WS3ResourceUploadError.verificationMismatch
        }
        return actual
    }
}
