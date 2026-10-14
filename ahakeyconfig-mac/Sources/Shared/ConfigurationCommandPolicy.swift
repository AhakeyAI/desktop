import Foundation

/// WS2 mode, standby and side-binding writes require a narrow confirmed-transaction
/// grant. Other configuration writes stay closed; unknown builds allow probes.
public enum ConfigurationCommandPolicy {
    public enum ConfirmedWrite { case none, mode, standby, sideSwitch, ordinaryKey, voiceHandoff }
    public static func permits(_ data: Data, profile: FirmwareCapabilityProfile?, confirmedWrite: ConfirmedWrite = .none) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 5, b[0] == 0xAA, b[1] == 0xBB,
              b[b.count - 2] == 0xCC, b[b.count - 1] == 0xDD else { return false }
        if profile?.identity == .legacy { return true }
        switch b[2] {
        case 0x73:
            if confirmedWrite == .voiceHandoff {
                return profile?.identity == .knownWS2Catalog && b.count == 9 && b[3] == 0x73 && b[4] < 4 && b[5] == 0 && b[6] == 0x6D
            }
            return confirmedWrite == .ordinaryKey && profile?.identity == .knownWS2Catalog && OrdinaryKeyConfiguration.validWriteRequest(data)
        case 0x04:
            return (confirmedWrite == .ordinaryKey || confirmedWrite == .voiceHandoff) && profile?.identity == .knownWS2Catalog && b.count == 5
        case 0x92: return confirmedWrite == .mode && profile?.identity == .knownWS2Catalog && b.count == 6 && b[3] < 4
        case 0x00, 0x9F: return b.count == 5
        case 0x83: return b.count == 6 && b[3] < 4
        case 0x90: return b.count == 6 && b[3] <= 8
        case 0x87: return profile?.mayQueryOrdinaryKeys == true && b.count == 7 && b[3] < 4 && b[4] < 4
        case 0x95:
            guard profile?.identity == .knownWS2Catalog else { return false }
            if b.count == 5 { return true }
            return confirmedWrite == .standby && b.count == 7 && [UInt16(0), 30, 60, 120].contains(UInt16(b[3]) | UInt16(b[4]) << 8)
        case 0x96:
            return profile?.identity == .knownWS2Catalog && (b.count == 5 || (confirmedWrite == .voiceHandoff && data == ConfirmedVoiceHandoff.suppressRequest))
        case 0x97:
            guard profile?.identity == .knownWS2Catalog else { return false }
            return b.count == 5 || (confirmedWrite == .sideSwitch && SideSwitchBindingConfiguration.validRequest(data))
        default: return false
        }
    }
}
