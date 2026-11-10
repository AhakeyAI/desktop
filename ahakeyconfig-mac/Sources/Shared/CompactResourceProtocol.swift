import Foundation

public enum NegotiatedResourceFormat: UInt8, Sendable { case compact = 3, lossless = 4 }
public protocol NegotiatedResourceObject: Sendable {
    var entry: UInt8 { get }
    var frames: UInt16 { get }
    var bytes: Data { get }
    var expandedBytes: UInt32 { get }
    var expandedCRC: UInt32 { get }
    var format: NegotiatedResourceFormat { get }
}

/// ACR3 RGB565_RAW with automatic spatial compression. All prepared animation
/// frames and their existing 100ms playback timing are retained. Select the
/// highest supported resolution whose *whole object* fits 50,000 bytes.
public struct CompactResourceObject: NegotiatedResourceObject, Equatable {
    public let entry: UInt8
    public let frames: UInt16
    public let bytes: Data
    public let expandedCRC: UInt32
    public let scale: Int
    public let previewPixels: Data
    public var format: NegotiatedResourceFormat { .compact }
    public var expandedBytes: UInt32 { UInt32(frames) * WS3ResourceReadback.frameBytes }
    public var width: Int { 160 / scale }
    public var height: Int { 80 / scale }

    public init(payload: WS3ResourcePayload) {
        let canonical = (0..<Int(payload.frameCount)).map { index in
            payload.bytes.subdata(in: (index * 28672)..<(index * 28672 + 25600))
        }
        self.init(entry: payload.entryID, canonicalFrames: canonical)
    }

    /// Internal input is already validated by WS3ResourcePayload's constructor.
    init(entry: UInt8, canonicalFrames: [Data]) {
        self.entry = entry; frames = UInt16(canonicalFrames.count)
        scale = [1, 2, 4].first { 16 + canonicalFrames.count * (2 + (160 / $0) * (80 / $0) * 2) <= 50_000 }!
        var output = Data("ACR3".utf8)
        output.append(contentsOf: [1, UInt8(scale), UInt8(frames), frames > 1 ? 1 : 0, UInt8(160 / scale), 0, UInt8(80 / scale), 0])
        output.append(ACR4Command.le(UInt32(frames) * WS3ResourceReadback.frameBytes))
        var expandedFrames: [Data] = []
        for source in canonicalFrames {
            let pixels = [UInt8](source)
            var small = Data(), expanded = Data()
            for y in stride(from: 0, to: 80, by: scale) {
                var row = Data()
                for x in stride(from: 0, to: 160, by: scale) {
                    var red = 0, green = 0, blue = 0
                    for dy in 0..<scale { for dx in 0..<scale {
                        let index = ((y+dy)*160+x+dx)*2
                        let color = Int(pixels[index]) << 8 | Int(pixels[index+1])
                        red += (color >> 11) & 31; green += (color >> 5) & 63; blue += color & 31
                    } }
                    let count = scale * scale
                    let color = (red/count) << 11 | (green/count) << 5 | blue/count
                    let pair = [UInt8(color >> 8), UInt8(color & 255)]
                    small.append(contentsOf: pair)
                    for _ in 0..<scale { row.append(contentsOf: pair) }
                }
                for _ in 0..<scale { expanded.append(row) }
            }
            output.append(contentsOf: [100, 0]); output.append(small); expandedFrames.append(expanded)
        }
        bytes = output; previewPixels = expandedFrames[0]
        expandedCRC = ACR4ResourceObject.expandedChecksum(frames: expandedFrames)
    }
}

/// Deliberately separate from ACR4: v3 CHUNK ACK has nine body bytes, v4 five.
public struct CompactResourceCommand: Equatable, Sendable {
    public typealias Operation = ACR4Command.Operation
    public let operation: Operation
    public let token: UInt32
    public let fields: Data
    public init(_ operation: Operation, token: UInt32, fields: Data = Data()) {
        self.operation = operation; self.token = token; self.fields = fields
    }
    public var request: Data {
        var data = Data([0xAA, 0xBB, 0x9E, 3, operation.rawValue, UInt8(clamping: fields.count)])
        data.append(ACR4Command.le(token)); data.append(fields); data.append(contentsOf: [0xCC, 0xDD]); return data
    }
    public init?(request: Data) {
        let b = [UInt8](request)
        guard b.count >= 12, Array(b.prefix(4)) == [0xAA, 0xBB, 0x9E, 3],
              Array(b.suffix(2)) == [0xCC, 0xDD], b.count == 12 + Int(b[5]),
              let operation = Operation(rawValue: b[4]) else { return nil }
        let token = ACR4Command.u32(b, 6); guard token != 0 else { return nil }
        let f = Data(b[10..<(b.count-2)])
        switch operation {
        case .caps, .commit, .cancel, .status: guard f.isEmpty else { return nil }
        case .metadata: guard f.count == 1, f[0] < 19 else { return nil }
        case .chunk:
            guard f.count >= 6, (1...128).contains(Int(f[4])), f.count == 5 + Int(f[4]),
                  ACR4Command.u32([UInt8](f), 0) >= 16,
                  ACR4Command.u32([UInt8](f), 0) <= 50_000 - UInt32(f[4]) else { return nil }
        case .begin:
            let x = [UInt8](f)
            guard x.count == 25, x[0] < 19, Array(x[9..<13]) == Array("ACR3".utf8), x[13] == 1,
                  [UInt8(1), 2, 4].contains(x[14]),
                  (1...Int(WS3ResourceReadback.maximumFrames(x[0]))).contains(Int(x[15])),
                  x[16] == (x[15] > 1 ? 1 : 0), x[18] == 0, x[20] == 0,
                  Int(x[17]) * Int(x[14]) == 160, Int(x[19]) * Int(x[14]) == 80,
                  ACR4Command.u32(x, 21) == UInt32(x[15]) * WS3ResourceReadback.frameBytes else { return nil }
            let size = ACR4Command.u32(x, 1)
            guard size <= 50_000, size == 16 + UInt32(x[15]) * (2 + UInt32(x[17]) * UInt32(x[19]) * 2) else { return nil }
        }
        self.init(operation, token: token, fields: f)
    }
    public var successBodyLength: Int { operation == .chunk ? 9 : ACR4Command(operation, token: token).successBodyLength }
    public func isLegacyUnsupportedReply(_ frame: Data) -> Bool {
        let b = [UInt8](frame), sent = [UInt8](request)
        return operation == .caps && b.count == 12 && Array(b.prefix(6)) == [0xAA, 0xBB, 0x9E, 1, 3, 0x40] &&
            Array(b[6..<10]) == Array(sent[5..<9]) && Array(b.suffix(2)) == [0xCC, 0xDD]
    }
}

public struct CompactResourceReply: Equatable {
    public let status: UInt8
    public let fields: Data
    public init?(frame: Data, command: CompactResourceCommand) {
        let b = [UInt8](frame)
        guard b.count >= 13, Array(b.prefix(3)) == [0xAA, 0xBB, 0x9E], b[3] <= 11,
              b[4] == 3, b[5] == command.operation.rawValue, b.count == 13 + Int(b[6]),
              Int(b[6]) == (b[3] == 0 ? command.successBodyLength : 4),
              ACR4Command.u32(b, 7) == command.token, Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        status = b[3]; fields = Data(b[11..<(b.count-2)])
    }
    public var capabilityChunk: Int? {
        let b = [UInt8](fields)
        guard status == 0, b.count == 14, Array(b.prefix(6)) == Array("ACR3".utf8) + [15, 0],
              ACR4Command.u32(b, 6) == 50_000, [40, 128].contains(b[10]), Array(b[11...13]) == [7, 8, 12] else { return nil }
        return Int(b[10])
    }
}
