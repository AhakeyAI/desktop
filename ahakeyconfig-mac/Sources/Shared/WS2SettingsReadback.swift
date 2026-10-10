import Foundation

/// A read response is distinct from the six-byte ACK returned by a write.
public enum WS2SettingsReadback {
    public static func standbyMinutes(_ frame: Data) -> UInt16? {
        let bytes = [UInt8](frame)
        guard bytes.count == 8, isSuccessFrame(bytes, command: 0x95),
              bytes[6] == 0xCC, bytes[7] == 0xDD else { return nil }
        let minutes = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
        return [0, 30, 60, 120].contains(minutes) ? minutes : nil
    }

    public static func voiceOnboardingState(_ frame: Data) -> UInt8? {
        let bytes = [UInt8](frame)
        guard bytes.count == 7, isSuccessFrame(bytes, command: 0x96),
              bytes[4] <= 4, bytes[5] == 0xCC, bytes[6] == 0xDD else { return nil }
        return bytes[4]
    }

    public static func sideSwitch(_ frame: Data) -> SideSwitchReadback? {
        let bytes = [UInt8](frame)
        guard bytes.count >= 12, bytes.count <= 64,
              isSuccessFrame(bytes, command: 0x97),
              bytes[5] == 2, bytes[bytes.count - 2] == 0xCC,
              bytes[bytes.count - 1] == 0xDD else { return nil }

        var offset = 6
        var positions: [SideSwitchReadback.Position] = []
        for _ in 0..<2 {
            guard offset + 2 <= bytes.count - 2 else { return nil }
            let bindType = bytes[offset]
            let actionLength = Int(bytes[offset + 1])
            offset += 2
            guard bindType <= 3, offset + actionLength <= bytes.count - 2,
                  (bindType == 3 || actionLength == 0) else { return nil }
            positions.append(.init(bindType: bindType, action: Data(bytes[offset..<(offset + actionLength)])))
            offset += actionLength
        }
        guard offset == bytes.count - 2 else { return nil }
        return .init(physicalState: bytes[4], positions: positions)
    }

    private static func isSuccessFrame(_ bytes: [UInt8], command: UInt8) -> Bool {
        bytes.count >= 6 && bytes[0] == 0xAA && bytes[1] == 0xBB &&
            bytes[2] == command && bytes[3] == 0
    }
}

public struct SideSwitchReadback: Equatable {
    public struct Position: Equatable {
        public let bindType: UInt8
        public let action: Data

        public init(bindType: UInt8, action: Data) {
            self.bindType = bindType
            self.action = action
        }
    }

    public let physicalState: UInt8
    public let positions: [Position]

    public init(physicalState: UInt8, positions: [Position]) {
        self.physicalState = physicalState
        self.positions = positions
    }
}
