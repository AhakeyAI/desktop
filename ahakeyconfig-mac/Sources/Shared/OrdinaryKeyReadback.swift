import Foundation

public struct OrdinaryKeyReadback: Equatable {
    public let mode: UInt8
    public let keyIndex: UInt8
    public let actionType: UInt8
    public let action: Data
    public let description: Data

    public init(mode: UInt8, keyIndex: UInt8, actionType: UInt8, action: Data, description: Data) {
        self.mode = mode
        self.keyIndex = keyIndex
        self.actionType = actionType
        self.action = action
        self.description = description
    }

    public var isKnownEditableAction: Bool {
        actionType == 0x00 || actionType == 0x73 || actionType == 0x74
    }
}

public enum OrdinaryKeyReadbackResult: Equatable {
    case value(OrdinaryKeyReadback)
    case tooLarge
    case rejected(UInt8)
    case malformed

    public static func parse(_ frame: Data, requestedMode: UInt8, requestedKeyIndex: UInt8) -> Self {
        let bytes = [UInt8](frame)
        guard bytes.count >= 6, bytes.count <= 64,
              bytes[0] == 0xAA, bytes[1] == 0xBB, bytes[2] == 0x87,
              bytes[bytes.count - 2] == 0xCC, bytes[bytes.count - 1] == 0xDD else {
            return .malformed
        }

        let status = bytes[3]
        if status != 0 {
            guard bytes.count == 6 else { return .malformed }
            return status == 0x03 ? .tooLarge : .rejected(status)
        }

        guard bytes.count >= 11,
              bytes[4] == requestedMode, bytes[5] == requestedKeyIndex,
              requestedMode < 4, requestedKeyIndex < 4 else {
            return .malformed
        }
        let actionLength = Int(bytes[7])
        let descriptionLengthIndex = 8 + actionLength
        guard descriptionLengthIndex < bytes.count - 2 else { return .malformed }
        let descriptionLength = Int(bytes[descriptionLengthIndex])
        guard descriptionLengthIndex + 1 + descriptionLength + 2 == bytes.count else {
            return .malformed
        }
        if bytes[6] == 0x00 && actionLength != 0 { return .malformed }

        return .value(OrdinaryKeyReadback(
            mode: bytes[4], keyIndex: bytes[5], actionType: bytes[6],
            action: Data(bytes[8..<descriptionLengthIndex]),
            description: Data(bytes[(descriptionLengthIndex + 1)..<(bytes.count - 2)])
        ))
    }
}
