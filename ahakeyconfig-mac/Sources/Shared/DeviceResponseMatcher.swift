import Foundation

/// Checks that a response belongs to the request currently on the command
/// channel. Commands without an echoed argument can only be distinguished by
/// serializing them; after a timeout the channel must be reconnected.
public enum DeviceResponseMatcher {
    public static func matches(request: Data, expectedCommand: UInt8, response: Data) -> Bool {
        let sent = [UInt8](request)
        let received = [UInt8](response)
        guard sent.count >= 5, sent[0] == 0xAA, sent[1] == 0xBB,
              sent[2] == expectedCommand,
              received.count >= 6, received[0] == 0xAA, received[1] == 0xBB,
              received[2] == expectedCommand,
              received[received.count - 2] == 0xCC,
              received[received.count - 1] == 0xDD else { return false }

        if expectedCommand == 0x00 {
            return received.count == 12 || received.count == 13
        }
        if received[3] != 0 { return received.count == 6 }

        switch expectedCommand {
        case 0x83:
            return sent.count >= 6 && received.count >= 15 && received[4] == sent[3]
        case 0x87:
            guard sent.count == 7 else { return false }
            if case .value = OrdinaryKeyReadbackResult.parse(
                response, requestedMode: sent[3], requestedKeyIndex: sent[4]
            ) { return true }
            return false
        case 0x95:
            return sent.count == 5 ? received.count == 8 : received.count == 6
        case 0x96:
            return sent.count == 5 ? received.count == 7 : received.count == 6
        case 0x97:
            return sent.count == 5 ? received.count >= 12 : received.count == 6
        case 0x9F:
            // Older firmware may ACK an unknown command without a catalog.
            return sent.count == 5 && received.count >= 6
        default:
            return true
        }
    }
}
