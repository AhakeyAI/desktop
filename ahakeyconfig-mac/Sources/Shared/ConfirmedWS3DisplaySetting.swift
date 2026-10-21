import Foundation

/// CP2 0x89/0x8E contract pinned to firmware 70ca334. Reads prove only the
/// selected setting; they do not prove resource bytes or power-cycle persistence.
public enum WS3DisplaySetting: Equatable {
    case brightness(UInt8)
    case singleLight(mode: UInt8, state: UInt8, effect: UInt8)

    public var readItem: WS3DisplayItem {
        switch self {
        case .brightness: return .brightness
        case .singleLight(let mode, let state, _): return .singleLight(mode: mode, state: state)
        }
    }
    public var value: UInt8 {
        switch self {
        case .brightness(let value), .singleLight(_, _, let value): return value
        }
    }
    public var saveRequest: Data? {
        let payload: [UInt8]
        switch self {
        case .brightness(let value):
            guard (1...100).contains(value) else { return nil }
            payload = [0, value]
        case .singleLight(let mode, let state, let effect):
            guard mode < 4, state < 9, effect <= 16 else { return nil }
            payload = [1, mode, state, effect]
        }
        return Data([0xAA, 0xBB, 0x8E] + payload + [0xCC, 0xDD])
    }
    public static func validSaveRequest(_ data: Data) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 7 else { return false }
        let setting: Self
        if b.count == 7, b[3] == 0 { setting = .brightness(b[4]) }
        else if b.count == 9, b[3] == 1 { setting = .singleLight(mode: b[4], state: b[5], effect: b[6]) }
        else { return false }
        return setting.saveRequest == data
    }
}

public enum WS3DisplayPreview: Equatable {
    case brightness(UInt8)
    case light(effect: UInt8, brightness: UInt8)
    case stop
    public var request: Data? {
        let payload: [UInt8]
        switch self {
        case .brightness(let brightness):
            guard (1...100).contains(brightness) else { return nil }; payload = [0, brightness]
        case .light(let effect, let brightness):
            guard (1...16).contains(effect), (1...100).contains(brightness) else { return nil }
            payload = [1, effect, brightness]
        case .stop: payload = [2]
        }
        return Data([0xAA, 0xBB, 0x89] + payload + [0xCC, 0xDD])
    }
    public static func validRequest(_ data: Data) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 6 else { return false }
        let preview: Self
        if b.count == 6, b[3] == 2 { preview = .stop }
        else if b.count == 7, b[3] == 0 { preview = .brightness(b[4]) }
        else if b.count == 8, b[3] == 1 { preview = .light(effect: b[4], brightness: b[5]) }
        else { return false }
        return preview.request == data
    }
}

@MainActor
public enum ConfirmedWS3DisplaySetting {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidValue, changedBaseline, mismatch
        public var errorDescription: String? {
            switch self {
            case .invalidValue: return NSLocalizedString("显示设置超出当前固件支持范围。", comment: "")
            case .changedBaseline: return NSLocalizedString("键盘当前显示设置已变化，请重新读取后再应用。", comment: "")
            case .mismatch: return NSLocalizedString("显示设置读回不一致，未确认保存；已发出的更改可能已生效。", comment: "")
            }
        }
    }
    public static func run(target: WS3DisplaySetting, baseline: UInt8,
                           checkSession: () throws -> Void,
                           read: (WS3DisplayItem) async throws -> UInt8,
                           write: (Data) async throws -> Void) async throws -> UInt8 {
        guard let request = target.saveRequest else { throw Failure.invalidValue }
        switch target {
        case .brightness: guard (1...100).contains(baseline) else { throw Failure.invalidValue }
        case .singleLight: guard baseline <= 16 else { throw Failure.invalidValue }
        }
        try Task.checkCancellation(); try checkSession()
        let before = try await read(target.readItem)
        try Task.checkCancellation(); try checkSession()
        guard before == baseline else { throw Failure.changedBaseline }
        // 0x8E persists this item itself; never append a broad 0x04 save.
        try await write(request)
        try Task.checkCancellation(); try checkSession()
        let after = try await read(target.readItem)
        try Task.checkCancellation(); try checkSession()
        guard after == target.value else { throw Failure.mismatch }
        return after
    }
}

public struct WS3SingleLightSnapshot: Equatable {
    public let generation: UInt64
    public let mode: UInt8
    public let state: UInt8
    public let effect: UInt8
    public init(generation: UInt64, mode: UInt8, state: UInt8, effect: UInt8) {
        self.generation = generation; self.mode = mode; self.state = state; self.effect = effect
    }
}
