import Foundation

/// HW1 ACR4 revision 1, frozen at firmware source 0471372. This is a separate
/// 0x9E version; it must never be interpreted as K1/v1, Restore/v2 or ACR3/v3.
public struct ACR4ResourceObject: Equatable, Sendable {
    public let entry: UInt8
    public let frames: UInt16
    public let bytes: Data
    public let expandedCRC: UInt32
    public var expandedBytes: UInt32 { UInt32(frames) * WS3ResourceReadback.frameBytes }

    public init(payload: WS3ResourcePayload, forceRaw: Bool = false) {
        entry = payload.entryID; frames = payload.frameCount
        var raw = Data(), packed = Data()
        for index in 0..<Int(frames) {
            let start = index * Int(WS3ResourceReadback.frameBytes)
            let pixels = payload.bytes.subdata(in: start..<(start + 25_600))
            raw.append(contentsOf: [100, 0]); raw.append(pixels)
            packed.append(contentsOf: [100, 0]); packed.append(Self.rle(pixels))
        }
        let compressed = !forceRaw && packed.count < raw.count
        var object = Data("ACR4".utf8)
        object.append(contentsOf: [compressed ? 3 : 1, 1, UInt8(frames), frames > 1 ? 1 : 0, 160, 0, 80, 0])
        object.append(ACR4Command.le(UInt32(frames) * WS3ResourceReadback.frameBytes))
        object.append(compressed ? packed : raw)
        bytes = object; expandedCRC = payload.losslessCRC32
    }

    /// Compute once while preparing a draft, never inside SwiftUI comparisons.
    static func expandedChecksum(frames: [Data]) -> UInt32 {
        var expanded = Data(capacity: frames.count * Int(WS3ResourceReadback.frameBytes))
        for (index, pixels) in frames.enumerated() {
            var descriptor = Data("AT03".utf8)
            descriptor.append(contentsOf: [1, UInt8(index), UInt8(frames.count), 0, 100, 0, 0, 0])
            descriptor.append(ACR4Command.le(WS3ResourcePayload.checksum(descriptor)))
            expanded.append(pixels); expanded.append(descriptor)
            expanded.append(Data(repeating: 0xFF, count: 3056))
        }
        return WS3ResourcePayload.checksum(expanded)
    }

    /// Literal/repeat RGB565 pairs. Tokens cannot cross a frame boundary.
    private static func rle(_ pixels: Data) -> Data {
        let b = [UInt8](pixels); let count = b.count / 2
        func equal(_ a: Int, _ c: Int) -> Bool { b[2*a] == b[2*c] && b[2*a+1] == b[2*c+1] }
        var out = Data(), i = 0
        while i < count {
            var run = 1
            while run < 128 && i + run < count && equal(i, i + run) { run += 1 }
            if run >= 2 {
                out.append(UInt8(127 + run)); out.append(contentsOf: b[(2*i)..<(2*i+2)]); i += run
            } else {
                let start = i; i += 1
                while i - start < 128 && i < count {
                    if i + 1 < count && equal(i, i + 1) { break }
                    i += 1
                }
                out.append(UInt8(i - start - 1)); out.append(contentsOf: b[(2*start)..<(2*i)])
            }
        }
        return out
    }
}

public struct ACR4Command: Equatable, Sendable {
    public enum Operation: UInt8, Sendable { case caps = 0x40, begin, chunk, commit, cancel, status, metadata }
    public let operation: Operation
    public let token: UInt32
    public let fields: Data
    public init(_ operation: Operation, token: UInt32, fields: Data = Data()) {
        self.operation = operation; self.token = token; self.fields = fields
    }
    public var request: Data {
        var data = Data([0xAA, 0xBB, 0x9E, 4, operation.rawValue, UInt8(clamping: fields.count)])
        data.append(Self.le(token)); data.append(fields); data.append(contentsOf: [0xCC, 0xDD]); return data
    }
    public init?(request: Data) {
        let b = [UInt8](request)
        guard b.count >= 12, Array(b.prefix(4)) == [0xAA, 0xBB, 0x9E, 4],
              Array(b.suffix(2)) == [0xCC, 0xDD], b.count == 12 + Int(b[5]),
              let operation = Operation(rawValue: b[4]) else { return nil }
        let token = Self.u32(b, 6); guard token != 0 else { return nil }
        let f = Data(b[10..<(b.count-2)])
        switch operation {
        case .caps, .commit, .cancel, .status: guard f.isEmpty else { return nil }
        case .metadata: guard f.count == 1, f[0] < 19 else { return nil }
        case .chunk:
            guard f.count >= 6, (1...128).contains(Int(f[4])), f.count == 5 + Int(f[4]),
                  Self.u32([UInt8](f), 0) >= 16,
                  Self.u32([UInt8](f), 0) <= 307_240 - UInt32(f[4]) else { return nil }
        case .begin:
            let x = [UInt8](f)
            guard x.count == 25, x[0] < 19, Array(x[9..<13]) == Array("ACR4".utf8),
                  [UInt8(1), 3].contains(x[13]), x[14] == 1,
                  (1...Int(WS3ResourceReadback.maximumFrames(x[0]))).contains(Int(x[15])),
                  x[16] == (x[15] > 1 ? 1 : 0), Array(x[17..<21]) == [160, 0, 80, 0],
                  Self.u32(x, 21) == UInt32(x[15]) * WS3ResourceReadback.frameBytes else { return nil }
            let size = Self.u32(x, 1), raw = 16 + UInt32(x[15]) * 25_602
            guard size <= 307_240, x[13] == 1 ? size == raw : (size >= 16 + UInt32(x[15]) * 302 && size <= raw) else { return nil }
        }
        self.init(operation, token: token, fields: f)
    }
    public var successBodyLength: Int {
        switch operation { case .caps: return 14; case .begin: return 8; case .chunk: return 5
        case .commit, .metadata: return 10; case .cancel: return 6; case .status: return 11 }
    }
    /// F99D's v1 dispatcher rejects unknown versions with its original 12-byte
    /// error envelope. It reads correlation at the v1 offset (including our
    /// body-length byte). Recognize only this exact negative CAPS shape; never
    /// treat it as ACR4 data or loosen v1/v4 successful response parsing.
    public func isLegacyUnsupportedReply(_ frame: Data) -> Bool {
        let b = [UInt8](frame), sent = [UInt8](request)
        return operation == .caps && b.count == 12 && Array(b.prefix(6)) == [0xAA, 0xBB, 0x9E, 1, 4, 0x40] &&
            Array(b[6..<10]) == Array(sent[5..<9]) && Array(b.suffix(2)) == [0xCC, 0xDD]
    }
    public static func le(_ value: UInt32) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0*8)) }) }
    public static func u32(_ b: [UInt8], _ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[at+$1]) << ($1*8) } }
}

public struct ACR4Reply: Equatable, Sendable {
    public let status: UInt8
    public let fields: Data
    public init?(frame: Data, command: ACR4Command) {
        let b = [UInt8](frame)
        guard b.count >= 13, Array(b.prefix(3)) == [0xAA, 0xBB, 0x9E], b[3] <= 11,
              b[4] == 4, b[5] == command.operation.rawValue, b.count == 13 + Int(b[6]),
              Int(b[6]) == (b[3] == 0 ? command.successBodyLength : 4),
              ACR4Command.u32(b, 7) == command.token, Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        status = b[3]; fields = Data(b[11..<(b.count-2)])
    }
    public var capabilityChunk: Int? {
        let b = [UInt8](fields)
        guard status == 0, b.count == 14, Array(b.prefix(6)) == Array("ACR4".utf8) + [15, 0],
              ACR4Command.u32(b, 6) == 307_240, [40, 128].contains(b[10]),
              Array(b[11...13]) == [1, 8, 12] else { return nil }
        return Int(b[10])
    }
    public func resource(entry: UInt8) -> WS3ResourceReadback? {
        let b = [UInt8](fields)
        guard status == 0, b.count == 10, let state = WS3ResourceWriteState(rawValue: b[0]) else { return nil }
        return WS3ResourceReadback(id: entry, basic: .resourceBasic(userValid: state == .valid, writeState: state),
            integrity: .resourceIntegrity(frames: UInt16(b[1]), bytes: ACR4Command.u32(b, 2), crc32: ACR4Command.u32(b, 6)))
    }
}
