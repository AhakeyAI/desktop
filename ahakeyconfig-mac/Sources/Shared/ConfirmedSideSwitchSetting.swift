import Foundation

/// WS2 0x97 always replaces both positions; the physical position is read-only.
public enum SideSwitchBindingConfiguration {
    public static let maximumCombinedActionBytes = 52

    public static func validAction(_ action: Data, maximumBytes: Int = maximumCombinedActionBytes) -> Bool {
        let b = [UInt8](action)
        guard b.count >= 3, b.count <= maximumBytes,
              Int(b[1]) + 2 == b.count else { return false }
        switch b[0] {
        case 0x73:
            let keys = Array(b.dropFirst(2))
            return keys.count <= 6 && Set(keys).count == keys.count && keys.allSatisfy(validKey)
        case 0x74:
            guard b[1] % 2 == 0 else { return false }
            var held = Set<UInt8>()
            for offset in stride(from: 2, to: b.count, by: 2) {
                let param = b[offset + 1]
                switch b[offset] {
                case 0: guard param == 0 else { return false }
                case 1: guard validKey(param), held.insert(param).inserted else { return false }
                case 2: guard held.remove(param) != nil else { return false }
                case 3: break
                case 4: guard param == 0 else { return false }; held.removeAll()
                default: return false
                }
            }
            return held.isEmpty
        default: return false
        }
    }

    private static func validKey(_ key: UInt8) -> Bool { (4...0xA4).contains(key) || (0xE0...0xE7).contains(key) }

    public static func request(positions: [SideSwitchReadback.Position]) -> Data? {
        guard positions.count == 2,
              positions.reduce(0, { $0 + $1.action.count }) <= maximumCombinedActionBytes else { return nil }
        var result = Data([0xAA, 0xBB, 0x97, 1])
        for position in positions {
            guard position.bindType <= 3,
                  position.bindType == 3 ? validAction(position.action) : position.action.isEmpty else { return nil }
            result.append(position.bindType)
            result.append(UInt8(position.action.count))
            result.append(position.action)
        }
        result.append(contentsOf: [0xCC, 0xDD])
        return result
    }

    /// Reconstructing the canonical frame also checks lengths, trailing bytes and actions.
    public static func validRequest(_ data: Data) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 10, b.count <= 62, Array(b.prefix(4)) == [0xAA, 0xBB, 0x97, 1],
              Array(b.suffix(2)) == [0xCC, 0xDD] else { return false }
        var offset = 4, positions: [SideSwitchReadback.Position] = []
        for _ in 0..<2 {
            guard offset + 2 <= b.count - 2 else { return false }
            let kind = b[offset], count = Int(b[offset + 1]); offset += 2
            guard offset + count <= b.count - 2 else { return false }
            positions.append(.init(bindType: kind, action: Data(b[offset..<(offset + count)])))
            offset += count
        }
        return offset == b.count - 2 && request(positions: positions) == data
    }
}

public struct SideSwitchBindingDraft: Codable {
    public private(set) var positions: [SideSwitchReadback.Position]
    private var explicitlyEdited: Set<Int> = []
    public init(readback: SideSwitchReadback) { positions = readback.positions }

    /// A single-side customization defaults the untouched peer to Disabled.
    /// An explicit choice on the peer is preserved, including a factory choice.
    public mutating func set(_ position: SideSwitchReadback.Position, at index: Int) {
        guard positions.count == 2, (0..<2).contains(index) else { return }
        positions[index] = position
        explicitlyEdited.insert(index)
        if position.bindType == 3, !explicitlyEdited.contains(1 - index) {
            positions[1 - index] = .init(bindType: 2, action: Data())
        }
    }
}

public enum ConfirmedSideSwitchSetting {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidBindings, changedSinceRead, mismatch
        case transportLimit(maximum: Int)
        public var errorDescription: String? {
            switch self {
            case .invalidBindings: return NSLocalizedString("拨杆绑定无效：两档动作合计最多 52 字节，宏必须松开所有按键。", comment: "")
            case .changedSinceRead: return NSLocalizedString("键盘绑定已变化，请重新读取后编辑。", comment: "")
            case .mismatch: return NSLocalizedString("保存后读回的绑定不一致，设置未确认。", comment: "")
            case .transportLimit(let maximum): return String(format: NSLocalizedString("当前蓝牙命令最多发送 %@ 字节，请缩短动作或重新连接。", comment: ""), String(describing: maximum))
            }
        }
    }

    @MainActor
    public static func run(baseline: [SideSwitchReadback.Position], target: [SideSwitchReadback.Position],
                           checkSession: () throws -> Void, read: () async throws -> SideSwitchReadback,
                           write: (Data) async throws -> Void) async throws -> SideSwitchReadback {
        guard let request = SideSwitchBindingConfiguration.request(positions: target) else { throw Failure.invalidBindings }
        try Task.checkCancellation()
        try checkSession()
        let current = try await read()
        try Task.checkCancellation()
        try checkSession()
        guard current.positions == baseline else { throw Failure.changedSinceRead }
        if current.positions == target { return current }
        try await write(request)
        try Task.checkCancellation()
        try checkSession()
        let actual = try await read()
        try Task.checkCancellation()
        try checkSession()
        guard actual.positions == target else { throw Failure.mismatch }
        return actual
    }
}
