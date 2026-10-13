import Foundation

/// Until confirmed-write transactions are implemented, WS2 and unknown builds
/// permit only the frozen read requests and the existing transient IDE state.
public enum ConfigurationCommandPolicy {
    public static func permits(_ data: Data, profile: FirmwareCapabilityProfile?) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 5, b[0] == 0xAA, b[1] == 0xBB,
              b[b.count - 2] == 0xCC, b[b.count - 1] == 0xDD else { return false }
        if profile?.identity == .legacy { return true }
        switch b[2] {
        case 0x00, 0x9F: return b.count == 5
        case 0x83: return b.count == 6 && b[3] < 4
        case 0x90: return b.count == 6 && b[3] <= 8
        case 0x87: return profile?.mayQueryOrdinaryKeys == true && b.count == 7 && b[3] < 4 && b[4] < 4
        case 0x95, 0x96, 0x97: return profile?.identity == .knownWS2Catalog && b.count == 5
        default: return false
        }
    }
}
