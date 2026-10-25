import Foundation

/// CP2.6 at firmware 0a055ba. This value is the keyboard's route, not the
/// application's speech preference. Consumer bypasses ordinary K1 bindings.
public struct K1OutputRoute: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case ordinary = 0, consumer = 1 }
    public let kind: Kind
    public let action: Data
    public init?(kind: Kind, action: Data) {
        let bytes = [UInt8](action)
        switch kind {
        case .ordinary:
            guard bytes.isEmpty || (bytes.count >= 2 && bytes.count <= 100 &&
                [0x73, 0x74].contains(bytes[0]) && Int(bytes[1]) + 2 == bytes.count) else { return nil }
        case .consumer:
            guard bytes.count == 2, (1...0x03FF).contains(Int(bytes[0]) | Int(bytes[1]) << 8) else { return nil }
        }
        self.kind = kind; self.action = action
    }
    public init?(serialized: Data) {
        let bytes = [UInt8](serialized)
        guard bytes.count == 102, let kind = Kind(rawValue: bytes[0]), bytes[1] <= 100 else { return nil }
        let end = 2 + Int(bytes[1])
        guard bytes[end...].allSatisfy({ $0 == 0 }) else { return nil }
        self.init(kind: kind, action: Data(bytes[2..<end]))
    }
    public var serialized: Data {
        Data([kind.rawValue, UInt8(action.count)]) + action + Data(repeating: 0, count: 100 - action.count)
    }
}

/// Commands must use the existing exclusive connection transaction. In
/// particular, a lost commit/start reply requires readback, never blind retry.
/// A generic legacy ACK or a catalog string alone is not capability proof.
public enum K1OutputRouteCommand: Equatable, Sendable {
    case capability(nonce: UInt32)
    case read(nonce: UInt32, mode: UInt8, offset: UInt8, count: UInt8)
    case begin(nonce: UInt32, selector: UInt8, length: UInt16, checksum: UInt32)
    case chunk(token: UInt32, selector: UInt8, offset: UInt16, bytes: Data)
    case commit(token: UInt32, selector: UInt8)
    case restoreStatus(nonce: UInt32)
    case startRestore(nonce: UInt32)

    public init?(request: Data) {
        let b = [UInt8](request)
        guard (11...62).contains(b.count), Array(b.prefix(4)) == [0xAA, 0xBB, 0x9E, 1],
              Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        func u32(_ i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[i + $1]) << ($1 * 8) } }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        switch b[4] {
        case 0x00 where b.count == 11: self = .capability(nonce: u32(5))
        case 0x10 where b.count == 14: self = .read(nonce: u32(5), mode: b[9], offset: b[10], count: b[11])
        case 0x20 where b.count == 18: self = .begin(nonce: u32(12), selector: b[5], length: u16(6), checksum: u32(8))
        case 0x21 where b.count >= 16 && b.count == 15 + Int(b[12]):
            self = .chunk(token: u32(5), selector: b[9], offset: u16(10), bytes: Data(b[13..<(b.count - 2)]))
        case 0x22 where b.count == 12: self = .commit(token: u32(5), selector: b[9])
        case 0x30 where b.count == 11: self = .restoreStatus(nonce: u32(5))
        case 0x31 where b.count == 11: self = .startRestore(nonce: u32(5))
        default: return nil
        }
        guard self.request == request else { return nil }
    }

    public var successReplyLength: Int {
        switch self {
        case .capability: return 14
        case .read(_, _, _, let count): return 20 + Int(count)
        case .begin: return 18
        case .chunk: return 16
        case .commit, .restoreStatus, .startRestore: return 17
        }
    }

    public var subcommand: UInt8 {
        switch self {
        case .capability: return 0x00
        case .read: return 0x10
        case .begin: return 0x20
        case .chunk: return 0x21
        case .commit: return 0x22
        case .restoreStatus: return 0x30
        case .startRestore: return 0x31
        }
    }
    public var correlation: UInt32 {
        switch self {
        case .capability(let nonce), .read(let nonce, _, _, _), .begin(let nonce, _, _, _),
             .restoreStatus(let nonce), .startRestore(let nonce): return nonce
        case .chunk(let token, _, _, _), .commit(let token, _): return token
        }
    }
    public var request: Data? {
        guard correlation != 0 else { return nil }
        var fields = Self.le(correlation, 4)
        switch self {
        case .read(_, let mode, let offset, let count):
            guard mode < 4, count > 0, count <= 42, Int(offset) + Int(count) <= 102 else { return nil }
            fields += [mode, offset, count]
        case .begin(let nonce, let selector, let length, let checksum):
            guard selector < 4 || selector == 0xFF, length == (selector == 0xFF ? 408 : 102) else { return nil }
            fields = [selector] + Self.le(UInt32(length), 2) + Self.le(checksum, 4) + Self.le(nonce, 4)
        case .chunk(_, let selector, let offset, let bytes):
            guard selector < 4 || selector == 0xFF, !bytes.isEmpty, bytes.count <= 47,
                  Int(offset) + bytes.count <= (selector == 0xFF ? 408 : 102) else { return nil }
            fields += [selector] + Self.le(UInt32(offset), 2) + [UInt8(bytes.count)] + Array(bytes)
        case .commit(_, let selector):
            guard selector < 4 || selector == 0xFF else { return nil }; fields += [selector]
        default: break
        }
        return Data([0xAA, 0xBB, 0x9E, 1, subcommand] + fields + [0xCC, 0xDD])
    }
    fileprivate static func le(_ value: UInt32, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
}

public enum K1RestoreState: UInt8, Sendable {
    case never = 0, inProgress = 1, incomplete = 2, complete = 3, storageUnavailable = 4, unsupported = 5
}

public enum K1OutputRouteReply: Equatable, Sendable {
    case capability
    case slice(checksum: UInt32, bytes: Data)
    case begun(nextOffset: UInt16)
    case chunkAccepted(nextOffset: UInt16)
    case committed(checksum: UInt32)
    case restore(handled: Bool, state: K1RestoreState, attempt: UInt32)
    case rejected

    public static func parse(_ data: Data, for command: K1OutputRouteCommand) -> Self? {
        let b = [UInt8](data)
        guard command.request != nil, (12...62).contains(b.count),
              Array(b.prefix(3)) == [0xAA, 0xBB, 0x9E], Array(b.suffix(2)) == [0xCC, 0xDD],
              b[3] <= 1, b[4] == 1, b[5] == command.subcommand,
              u32(b, 6) == command.correlation else { return nil }
        if command.subcommand == 0x30 || command.subcommand == 0x31 {
            guard b.count == 17, let state = K1RestoreState(rawValue: b[10]) else { return nil }
            return .restore(handled: b[3] == 0, state: state, attempt: u32(b, 11))
        }
        if b[3] == 1 { return b.count == 12 ? .rejected : nil }
        switch command {
        case .capability:
            guard b.count == 14, b[10] == 3, b[11] == 4 else { return nil }
            return .capability
        case .read(_, let mode, let offset, let count):
            guard b.count == 20 + Int(count), b[10] == mode, b[11] == offset, u16(b, 12) == 102 else { return nil }
            return .slice(checksum: u32(b, 14), bytes: Data(b[18..<(b.count - 2)]))
        case .begin(let nonce, _, let length, _):
            guard b.count == 18, u32(b, 10) == nonce, u16(b, 14) <= length else { return nil }
            return .begun(nextOffset: u16(b, 14))
        case .chunk(_, let selector, let offset, let bytes):
            guard b.count == 16, b[10] == selector, b[13] == bytes.count,
                  Int(u16(b, 11)) == Int(offset) + bytes.count else { return nil }
            return .chunkAccepted(nextOffset: u16(b, 11))
        case .commit(_, let selector):
            guard b.count == 17, b[10] == selector else { return nil }
            return .committed(checksum: u32(b, 11))
        default: return nil
        }
    }
    private static func u16(_ b: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(b[offset]) | UInt16(b[offset + 1]) << 8
    }
    private static func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[offset + $1]) << ($1 * 8) }
    }
}
