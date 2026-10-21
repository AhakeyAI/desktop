import Foundation

/// CP1 wire contract, retained in CP2 accepted source 70ca334. This codec
/// grants no device capability and does not send or replay runtime state.
public enum WS3PresentationMode: UInt8 { case single = 0, multi = 1 }
public enum WS3TaskState: UInt8, Codable, Sendable { case running = 1, waiting = 2, done = 3 }

public struct WS3TaskSlot: Equatable {
    public let state: WS3TaskState
    public let foreground: Bool
    public init(state: WS3TaskState, foreground: Bool = false) {
        self.state = state
        self.foreground = foreground
    }
}

/// Exactly four slots, including explicit empty slots. Slot indices are not
/// assigned to IDE names here; that mapping belongs to the host task model.
public struct WS3TaskSnapshot: Equatable {
    public let slots: [WS3TaskSlot?]

    public init?(slots: [WS3TaskSlot?]) {
        guard slots.count == 4 else { return nil }
        self.slots = slots
    }

    public init?(request: Data) {
        let b = [UInt8](request)
        guard b.count == 18, Array(b.prefix(4)) == [0xAA, 0xBB, 0x99, 1],
              Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        var slots: [WS3TaskSlot?] = []
        for offset in stride(from: 4, through: 13, by: 3) {
            switch b[offset] {
            case 0: slots.append(nil) // Firmware ignores state/foreground for empty slots.
            case 1:
                guard let state = WS3TaskState(rawValue: b[offset + 1]), b[offset + 2] <= 1 else { return nil }
                slots.append(WS3TaskSlot(state: state, foreground: b[offset + 2] == 1))
            default: return nil
            }
        }
        self.slots = slots
    }

    fileprivate var payload: [UInt8] {
        [1] + slots.flatMap { slot -> [UInt8] in
            guard let slot else { return [0, 0, 0] }
            return [1, slot.state.rawValue, slot.foreground ? 1 : 0]
        }
    }
}

public enum WS3PresentationCommand: Equatable {
    case setMode(WS3PresentationMode)
    case single(state: UInt8)
    case multi(WS3TaskSnapshot)
    case heartbeat

    fileprivate var opcode: UInt8 {
        switch self {
        case .setMode: return 0x98
        case .single: return 0x90
        case .multi: return 0x99
        case .heartbeat: return 0x9A
        }
    }

    public var request: Data? {
        let payload: [UInt8]
        switch self {
        case .setMode(let mode): payload = [mode.rawValue]
        case .single(let state):
            guard state < 9 else { return nil }; payload = [state]
        case .multi(let snapshot): payload = snapshot.payload
        case .heartbeat: payload = []
        }
        return Data([0xAA, 0xBB, opcode] + payload + [0xCC, 0xDD])
    }
}

/// A zero status proves only command receipt. Wrong-mode 0x90/0x99 also
/// return OK; 0x9A neither queries mode nor renews display freshness.
public enum WS3PresentationAcknowledgement: Equatable {
    case received
    case rejected(UInt8)

    public static func parse(_ frame: Data, for command: WS3PresentationCommand) -> Self? {
        let b = [UInt8](frame)
        guard command.request != nil, b.count == 6,
              Array(b.prefix(3)) == [0xAA, 0xBB, command.opcode],
              Array(b.suffix(2)) == [0xCC, 0xDD] else { return nil }
        return b[3] == 0 ? .received : .rejected(b[3])
    }
}
