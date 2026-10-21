import Foundation

/// Read-only 0x88 contract from firmware 70ca334. A successful probe grants no writes.
public enum WS3DisplayItem: Equatable {
    case brightness
    case singleLight(mode: UInt8, state: UInt8)
    case resourceBasic(UInt8)
    case resourceIntegrity(UInt8)

    public var request: Data? {
        let payload: [UInt8]
        switch self {
        case .brightness: payload = [0]
        case .singleLight(let mode, let state):
            guard mode < 4, state < 9 else { return nil }; payload = [1, mode, state]
        case .resourceBasic(let id): guard id < 19 else { return nil }; payload = [2, id]
        case .resourceIntegrity(let id): guard id < 19 else { return nil }; payload = [3, id]
        }
        return Data([0xAA, 0xBB, 0x88] + payload + [0xCC, 0xDD])
    }
    public static func from(request: Data) -> Self? {
        let b = [UInt8](request)
        guard b.count >= 6, Array(b.prefix(3)) == [0xAA, 0xBB, 0x88], Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        let item: Self
        switch b[3] {
        case 0 where b.count == 6: item = .brightness
        case 1 where b.count == 8: item = .singleLight(mode: b[4], state: b[5])
        case 2 where b.count == 7: item = .resourceBasic(b[4])
        case 3 where b.count == 7: item = .resourceIntegrity(b[4])
        default: return nil
        }
        return item.request == request ? item : nil
    }
}

public enum WS3ResourceWriteState: UInt8 { case empty, writing, valid, invalid }
public enum WS3DisplayValue: Equatable {
    case unsupported, rejected(UInt8)
    case brightness(UInt8), singleLight(UInt8)
    case resourceBasic(userValid: Bool, writeState: WS3ResourceWriteState)
    case resourceIntegrity(frames: UInt16, bytes: UInt32, crc32: UInt32)

    public static func parse(_ frame: Data, for item: WS3DisplayItem) -> Self? {
        let b = [UInt8](frame)
        guard item.request != nil, b.count >= 6,
              Array(b.prefix(3)) == [0xAA, 0xBB, 0x88], Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        if b[3] != 0 { return b.count == 6 ? .rejected(b[3]) : nil }
        // CP4D may acknowledge an unknown opcode without returning any data.
        if b.count == 6 { return .unsupported }
        switch item {
        case .brightness:
            guard b.count == 8, b[4] == 0, b[5] <= 100 else { return nil }
            return .brightness(b[5])
        case .singleLight(let mode, let state):
            guard b.count == 10, Array(b[4...6]) == [1, mode, state] else { return nil }
            return .singleLight(b[7]) // Unknown effect IDs remain read-only values.
        case .resourceBasic(let id):
            guard b.count == 10, b[4] == 2, b[5] == id, b[6] <= 1,
                  let state = WS3ResourceWriteState(rawValue: b[7]) else { return nil }
            return .resourceBasic(userValid: b[6] == 1, writeState: state)
        case .resourceIntegrity(let id):
            guard b.count == 18, b[4] == 3, b[5] == id else { return nil }
            let frames = UInt16(b[6]) | UInt16(b[7]) << 8
            func u32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[offset + $1]) << ($1 * 8) } }
            let bytes = u32(8), crc = u32(12)
            guard frames <= WS3ResourceReadback.maximumFrames(id),
                  bytes == UInt32(frames) * WS3ResourceReadback.frameBytes,
                  frames != 0 || crc == 0 else { return nil }
            return .resourceIntegrity(frames: frames, bytes: bytes, crc32: crc)
        }
    }
}

public struct WS3ResourceReadback: Equatable {
    static let frameBytes: UInt32 = 7 * 4096
    static func maximumFrames(_ id: UInt8) -> UInt16 { [UInt8(0), 4, 8, 12].contains(id) ? 8 : 12 }
    public let id: UInt8
    public let userValid: Bool
    public let writeState: WS3ResourceWriteState
    public let frames: UInt16
    public let payloadBytes: UInt32
    public let crc32: UInt32
    public var reportsValidUserResource: Bool { userValid && writeState == .valid }
    public init?(id: UInt8, basic: WS3DisplayValue, integrity: WS3DisplayValue) {
        guard id < 19, case .resourceBasic(let valid, let state) = basic,
              case .resourceIntegrity(let frames, let bytes, let crc) = integrity else { return nil }
        guard frames <= Self.maximumFrames(id), bytes == UInt32(frames) * Self.frameBytes else { return nil }
        if valid && state == .valid {
            guard frames > 0 else { return nil }
        } else { guard frames == 0, bytes == 0, crc == 0 else { return nil } }
        self.id = id; userValid = valid; writeState = state
        self.frames = frames; payloadBytes = bytes; crc32 = crc
    }
}
public struct WS3DisplaySnapshot: Equatable {
    public let generation: UInt64
    public let brightness: UInt8
    public let resources: [WS3ResourceReadback]
    public init(generation: UInt64, brightness: UInt8, resources: [WS3ResourceReadback]) {
        self.generation = generation; self.brightness = brightness; self.resources = resources
    }
    public func verifiesDisplaySettings(in currentGeneration: UInt64) -> Bool {
        generation == currentGeneration && (1...100).contains(brightness) && resources.count == 19 &&
            Set(resources.map(\.id)) == Set(UInt8(0)..<19)
    }
}
