import Foundation

/// WS2 mode, standby and side-binding writes require a narrow confirmed-transaction
/// grant. Other configuration writes stay closed; unknown builds allow probes.
public enum ConfigurationCommandPolicy {
    public enum ConfirmedWrite { case none, deviceName, mode, standby, sideSwitch, ordinaryKey, voiceHandoff, ws3Display, ws3Resource, ws3ResourceRestore, ws3Presentation, k1Route, k1Initialization, restoreInitialization }
    public static func permits(_ data: Data, profile: FirmwareCapabilityProfile?, confirmedWrite: ConfirmedWrite = .none,
                               ws3DisplayReadbackVerified: Bool = false, k1RouteReadbackVerified: Bool = false,
                               restoreReadbackVerified: Bool = false,
                               k1InitializationReadbackVerified: Bool = false) -> Bool {
        let b = [UInt8](data)
        guard b.count >= 5, b[0] == 0xAA, b[1] == 0xBB,
              b[b.count - 2] == 0xCC, b[b.count - 1] == 0xDD else { return false }
        guard FirmwareCommandNamespace(command: b[2]) == .official else { return false }
        if b[2] == 0x9E {
            guard profile?.mayQueryOrdinaryKeys == true, let command = K1OutputRouteCommand(request: data) else { return false }
            switch command {
            case .capability, .restoreStatus: return true
            case .read: return k1RouteReadbackVerified
            case .begin(_, let selector, _, _), .chunk(_, let selector, _, _), .commit(_, let selector):
                guard k1RouteReadbackVerified else { return false }
                return selector == 0xFF
                    ? confirmedWrite == .k1Initialization && k1InitializationReadbackVerified
                    : confirmedWrite == .k1Route
            case .startRestore: return confirmedWrite == .restoreInitialization && restoreReadbackVerified
            }
        }
        if b[2] == 0x01 {
            return confirmedWrite == .deviceName &&
                (profile?.identity == .legacy || profile?.mayQueryOrdinaryKeys == true) &&
                DeviceNameSubmission.validRequest(data)
        }
        if profile?.identity == .legacy { return true }
        switch b[2] {
        case 0x73:
            if confirmedWrite == .voiceHandoff {
                return profile?.mayQueryOrdinaryKeys == true && profile?.mayQueryVoiceOnboarding == true && b.count == 9 && b[3] == 0x73 && b[4] < 4 && b[5] == 0 && b[6] == 0x6D
            }
            return confirmedWrite == .ordinaryKey && profile?.mayQueryOrdinaryKeys == true && OrdinaryKeyConfiguration.validWriteRequest(data)
        case 0x04:
            return (confirmedWrite == .ordinaryKey || (confirmedWrite == .voiceHandoff && profile?.mayQueryVoiceOnboarding == true)) && profile?.mayQueryOrdinaryKeys == true && b.count == 5
        case 0x92: return confirmedWrite == .mode && profile?.mayQueryOrdinaryKeys == true && b.count == 6 && b[3] < 4
        case 0x00, 0x9F: return b.count == 5
        case 0x83: return b.count == 6 && b[3] < 4
        case 0x90: return b.count == 6 && b[3] <= 8
        case 0x98, 0x99:
            guard confirmedWrite == .ws3Presentation, ws3DisplayReadbackVerified,
                  profile?.mayUseWS3Presentation == true else { return false }
            return b[2] == 0x98 ? (b.count == 6 && b[3] <= 1) : WS3TaskSnapshot(request: data) != nil
        case 0x88: return profile?.mayQueryWS3Display == true && WS3DisplayItem.from(request: data) != nil
        case 0x8D:
            return confirmedWrite == .ws3ResourceRestore && ws3DisplayReadbackVerified &&
                profile?.mayQueryWS3Resources == true && WS3ResourceRestoreCommand.validRequest(data)
        case 0x8A, 0x8B, 0x8C:
            return confirmedWrite == .ws3Resource && ws3DisplayReadbackVerified &&
                profile?.mayQueryWS3Resources == true && WS3ResourceUploadCommand.validRequest(data)
        case 0x89, 0x8E:
            guard confirmedWrite == .ws3Display, ws3DisplayReadbackVerified,
                  profile?.mayQueryWS3Display == true else { return false }
            return b[2] == 0x89 ? WS3DisplayPreview.validRequest(data) : WS3DisplaySetting.validSaveRequest(data)
        case 0x87: return profile?.mayQueryOrdinaryKeys == true && b.count == 7 && b[3] < 4 && b[4] < 4
        case 0x95:
            guard profile?.mayQueryStandby == true else { return false }
            if b.count == 5 { return true }
            return confirmedWrite == .standby && b.count == 7 && [UInt16(0), 30, 60, 120].contains(UInt16(b[3]) | UInt16(b[4]) << 8)
        case 0x96:
            return profile?.mayQueryVoiceOnboarding == true && (b.count == 5 || (confirmedWrite == .voiceHandoff && data == ConfirmedVoiceHandoff.suppressRequest))
        case 0x97:
            guard profile?.mayQuerySideSwitchBindings == true else { return false }
            return b.count == 5 || (confirmedWrite == .sideSwitch && SideSwitchBindingConfiguration.validRequest(data))
        default: return false
        }
    }
}
