import Foundation

public enum StateCommandWriteKind: Equatable {
    case withResponse
    case withoutResponse
    case unavailable
}

public enum StateCommandWritePolicy {
    public static func choose(
        supportsWrite: Bool,
        supportsWriteWithoutResponse: Bool
    ) -> StateCommandWriteKind {
        if supportsWrite {
            return .withResponse
        }
        if supportsWriteWithoutResponse {
            return .withoutResponse
        }
        return .unavailable
    }
}

public struct StateCommandAcknowledgement: Equatable {
    public let stateCommand: UInt8
    public let resultCode: UInt8

    public static func parse(_ data: Data) -> StateCommandAcknowledgement? {
        guard data.count == 6,
              data[0] == 0xAA,
              data[1] == 0xBB,
              data[2] == 0x90,
              data[4] == 0xCC,
              data[5] == 0xDD else {
            return nil
        }
        return StateCommandAcknowledgement(
            stateCommand: data[2],
            resultCode: data[3]
        )
    }
}
