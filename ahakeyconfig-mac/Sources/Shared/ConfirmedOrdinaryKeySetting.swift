import Foundation

/// A WS2 ordinary-key edit is separate from lighting, OLED and voice ownership.
public enum OrdinaryKeyConfiguration {
    public static func valid(_ key: OrdinaryKeyReadback) -> Bool {
        guard key.mode < 4, key.keyIndex < 4, key.description.count <= 20,
              11 + key.action.count + key.description.count <= 64 else { return false }
        switch key.actionType {
        case 0: return key.action.isEmpty
        case 0x73 where key.action.isEmpty: return true
        case 0x73, 0x74:
            guard key.action.count <= 53 else { return false }
            return SideSwitchBindingConfiguration.validAction(Data([key.actionType, UInt8(key.action.count)]) + key.action, maximumBytes: 55)
        default: return false
        }
    }

    public static func actionRequest(_ key: OrdinaryKeyReadback) -> Data? {
        guard valid(key), key.actionType != 0 else { return nil }
        return Data([0xAA, 0xBB, 0x73, key.actionType, key.mode, key.keyIndex]) + key.action + Data([0xCC, 0xDD])
    }
    public static func descriptionRequest(_ key: OrdinaryKeyReadback) -> Data? {
        guard valid(key), key.description.allSatisfy({ (0x20...0x7E).contains($0) }),
              key.description.last != 0x20 else { return nil }
        return Data([0xAA, 0xBB, 0x73, 0x75, key.mode, key.keyIndex]) + key.description + Data([0xCC, 0xDD])
    }
    public static func validWriteRequest(_ frame: Data) -> Bool {
        let b = [UInt8](frame)
        guard b.count >= 8, b.count <= 61, Array(b.prefix(3)) == [0xAA, 0xBB, 0x73],
              Array(b.suffix(2)) == [0xCC, 0xDD] else { return false }
        let payload = Data(b[6..<(b.count - 2)])
        let key = OrdinaryKeyReadback(mode: b[4], keyIndex: b[5], actionType: b[3], action: payload, description: Data())
        if b[3] == 0x75 {
            return descriptionRequest(.init(mode: b[4], keyIndex: b[5], actionType: 0x73, action: Data(), description: payload)) == frame
        }
        return actionRequest(key) == frame
    }
}

public enum ConfirmedOrdinaryKeySetting {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidValue, changedSinceRead, mismatch, voicePresetOwnsKey
        public var errorDescription: String? {
            switch self {
            case .invalidValue: return NSLocalizedString("键位无法安全保存：请检查动作、宏释放、20 字节英文描述及读回容量。", comment: "")
            case .changedSinceRead: return NSLocalizedString("键盘该键已变化，请重新读取后编辑。", comment: "")
            case .mismatch: return NSLocalizedString("保存后键位读回不一致，设置未确认。", comment: "")
            case .voicePresetOwnsKey: return NSLocalizedString("Voice 键仍由固件平台预设接管；完成语音接管前不能修改其动作。", comment: "")
            }
        }
    }
    @MainActor
    public static func run(baseline: OrdinaryKeyReadback, target: OrdinaryKeyReadback,
                           checkSession: () throws -> Void, read: () async throws -> OrdinaryKeyReadback,
                           voiceState: () async throws -> UInt8, write: (Data) async throws -> Void) async throws -> OrdinaryKeyReadback {
        guard baseline.mode == target.mode, baseline.keyIndex == target.keyIndex,
              baseline.isKnownEditableAction, OrdinaryKeyConfiguration.valid(target) else { throw Failure.invalidValue }
        let actionChanged = baseline.actionType != target.actionType || baseline.action != target.action
        let descriptionChanged = baseline.description != target.description
        guard !actionChanged || OrdinaryKeyConfiguration.actionRequest(target) != nil,
              !descriptionChanged || OrdinaryKeyConfiguration.descriptionRequest(target) != nil else { throw Failure.invalidValue }
        try checkSession()
        let current = try await read()
        try checkSession()
        guard current == baseline else { throw Failure.changedSinceRead }
        if !actionChanged && !descriptionChanged { return current }
        if actionChanged && target.keyIndex == 0 {
            let state = try await voiceState()
            try checkSession()
            guard state == 3 || state == 4 else { throw Failure.voicePresetOwnsKey }
        }
        if actionChanged {
            try await write(OrdinaryKeyConfiguration.actionRequest(target)!)
            try checkSession()
        }
        if descriptionChanged {
            try await write(OrdinaryKeyConfiguration.descriptionRequest(target)!)
            try checkSession()
        }
        // Existing firmware persists its configuration with 0x04; ACK is not
        // EEPROM verification. A failure may leave changed RAM; never claim rollback.
        try await write(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]))
        try checkSession()
        let actual = try await read()
        try checkSession()
        guard actual == target else { throw Failure.mismatch }
        return actual
    }
}
