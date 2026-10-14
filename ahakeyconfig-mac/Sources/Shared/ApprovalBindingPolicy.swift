import Foundation

public enum ApprovalBindingPolicy {
    /// Raw GPIO is a display fact, not sufficient authority for approval.
    public static func mayAutoApprove(physicalState: Int?, fresh: Bool,
                                      profile: FirmwareCapabilityProfile?,
                                      binding: SideSwitchReadback?) -> Bool {
        guard fresh, physicalState == 0 else { return false }
        switch profile?.identity {
        case .legacy: return true
        case .knownWS2Catalog:
            guard let binding, binding.physicalState == 0, binding.positions.count == 2 else { return false }
            return binding.positions[0].bindType == 0 && binding.positions[0].action.isEmpty
        default: return false
        }
    }

    /// Missing metadata from an old/unavailable Agent is never an auto grant.
    public static func effectiveSwitchState(_ reply: [String: Any]?) -> Int {
        guard let reply, reply["approvalPolicyVersion"] as? Int == 1,
              reply["switchState"] as? Int == 0,
              reply["physicalSwitchState"] as? Int == 0,
              reply["approvalAutoVerified"] as? Bool == true else { return 1 }
        return 0
    }
}
