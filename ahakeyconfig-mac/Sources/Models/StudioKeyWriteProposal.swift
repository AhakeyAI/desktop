import Foundation
import AhaKeyConfigShared

/// Conversion is an explicit proposal, never a device write or lossy import.
enum StudioKeyWriteProposal {
    enum Failure: Error, LocalizedError {
        case description, action
        var errorDescription: String? {
            switch self {
            case .description: return "画布描述必须为英文字符，最多 20 字节；请修改后再载入。"
            case .action: return "画布动作无法完整保存和读回，请检查宏释放及动作容量。"
            }
        }
    }
    static func make(key: AhaKeyKeyDraft, mode: AhaKeyModeSlot) throws -> OrdinaryKeyReadback {
        guard var description = key.description.data(using: .ascii, allowLossyConversion: false), description.count <= 20 else { throw Failure.description }
        while description.last == 0x20 { description.removeLast() }
        let result = OrdinaryKeyReadback(mode: UInt8(mode.rawValue), keyIndex: UInt8(key.role.rawValue),
            actionType: key.usesMacro ? 0x74 : 0x73,
            action: Data(key.usesMacro ? key.macro.flattenedBytes : key.shortcut.hidCodes), description: description)
        guard OrdinaryKeyConfiguration.valid(result) else { throw Failure.action }
        return result
    }
    static func reconcile(baseline: AhaKeyStudioDraft, current: AhaKeyStudioDraft, actual: OrdinaryKeyReadback) -> AhaKeyStudioDraft {
        guard let slot = AhaKeyModeSlot(rawValue: Int(actual.mode)), let role = AhaKeyKeyRole(rawValue: Int(actual.keyIndex)) else { return baseline }
        let key = current.draft(for: slot).key(for: role)
        guard (try? make(key: key, mode: slot)) == actual else { return baseline }
        var result = baseline
        var mode = result.draft(for: slot)
        mode.updateKey(key); result.updateMode(mode)
        return result
    }
}

extension Notification.Name {
    static let ahaKeyOrdinaryKeyConfirmed = Notification.Name("ahaKeyOrdinaryKeyConfirmed")
}
