import Foundation
import CoreFoundation

public enum LeverAssignedAction: Int, Equatable, Sendable {
    case automatic = 0, manual = 1, disabled = 2, shortcut = 3, macro = 4

    public init?(position: SideSwitchReadback.Position) {
        switch position.bindType {
        case 0...2 where position.action.isEmpty: self.init(rawValue: Int(position.bindType))
        case 3:
            switch position.action.first {
            case 0x73: self = .shortcut
            case 0x74: self = .macro
            default: return nil
            }
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .automatic: return NSLocalizedString("自动批准", comment: "")
        case .manual: return NSLocalizedString("手动批准", comment: "")
        case .disabled: return NSLocalizedString("不执行", comment: "")
        case .shortcut: return NSLocalizedString("快捷键", comment: "")
        case .macro: return NSLocalizedString("宏", comment: "")
        }
    }
}

public enum ApprovalBindingPolicy {
    public static func assignedAction(physicalState: Int?, profile: FirmwareCapabilityProfile?,
                                      binding: SideSwitchReadback?) -> LeverAssignedAction? {
        guard let physicalState, (0...1).contains(physicalState) else { return nil }
        if profile?.identity == .legacy { return physicalState == 0 ? .automatic : .manual }
        guard profile?.mayQuerySideSwitchBindings == true, let binding, binding.positions.count == 2,
              Int(binding.physicalState) == physicalState else { return nil }
        return LeverAssignedAction(position: binding.positions[physicalState])
    }

    public static func mayAutoApprove(physicalState: Int?, fresh: Bool,
                                      profile: FirmwareCapabilityProfile?,
                                      binding: SideSwitchReadback?) -> Bool {
        fresh && assignedAction(physicalState: physicalState, profile: profile, binding: binding) == .automatic
    }

    /// Missing or malformed proof never grants approval. Older replies only
    /// verify automatic on position 0 and do not include the assigned action.
    public static func effectiveSwitchState(_ reply: [String: Any]?) -> Int {
        guard let reply, strictInteger(reply["approvalPolicyVersion"]) == 1,
              strictInteger(reply["switchState"]) == 0,
              let position = strictInteger(reply["physicalSwitchState"]), (0...1).contains(position),
              isTrueBoolean(reply["approvalAutoVerified"]) else { return 1 }
        if reply["leverAction"] != nil { return assignedAction(in: reply) == .automatic ? 0 : 1 }
        return position == 0 ? 0 : 1
    }

    public static func assignedAction(in reply: [String: Any]) -> LeverAssignedAction? {
        strictInteger(reply["leverAction"]).flatMap(LeverAssignedAction.init(rawValue:))
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
