import Foundation
import CoreFoundation

public enum ApprovalBindingPolicy {
    /// Raw GPIO is a display fact, not sufficient authority for approval.
    public static func mayAutoApprove(physicalState: Int?, fresh: Bool,
                                      profile: FirmwareCapabilityProfile?,
                                      binding: SideSwitchReadback?) -> Bool {
        guard fresh, physicalState == 0 else { return false }
        switch profile?.identity {
        case .legacy: return true
        case .knownWS2Catalog, .verifiedCatalog:
            guard profile?.mayQuerySideSwitchBindings == true, let binding, binding.physicalState == 0, binding.positions.count == 2 else { return false }
            return binding.positions[0].bindType == 0 && binding.positions[0].action.isEmpty
        default: return false
        }
    }

    /// Missing metadata from an old/unavailable Agent is never an auto grant.
    public static func effectiveSwitchState(_ reply: [String: Any]?) -> Int {
        guard let reply, strictInteger(reply["approvalPolicyVersion"]) == 1,
              strictInteger(reply["switchState"]) == 0,
              strictInteger(reply["physicalSwitchState"]) == 0,
              isTrueBoolean(reply["approvalAutoVerified"]) else { return 1 }
        return 0
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q", "C", "S", "I", "L", "Q":
            return Int(number.stringValue)
        default:
            return nil
        }
    }

    private static func isTrueBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

}
