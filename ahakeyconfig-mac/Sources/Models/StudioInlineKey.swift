import Foundation
import AhaKeyConfigShared

struct StudioInlineKeyTarget: Equatable {
    let mode: UInt8
    let index: UInt8
    var title: String { "Mode \(mode + 1) · Key \(index + 1)" }
}

struct StudioInlineKeyFact {
    let deviceID: String
    let value: OrdinaryKeyReadback
}

struct StudioInlineKeyConflict: Identifiable {
    let id = UUID()
    let deviceID: String
    let actual: OrdinaryKeyReadback
    let desired: OrdinaryKeyReadback
}

/// Only import values the existing editor can round-trip without losing bytes.
/// Unknown and noncanonical actions stay visible as read-only facts.
extension StudioKeyWriteProposal {
    static func draft(from actual: OrdinaryKeyReadback, preserving original: AhaKeyKeyDraft) -> AhaKeyKeyDraft? {
        guard actual.keyIndex == UInt8(original.role.rawValue),
              let description = String(data: actual.description, encoding: .ascii) else { return nil }
        var result = original
        result.description = description
        result.macro = []
        switch actual.actionType {
        case 0x73:
            let codes = Array(actual.action)
            let modifiers = ShortcutModifier.displayOrder.filter { codes.contains($0.hidCode) }
            let keys = codes.filter { code in !modifiers.contains { $0.hidCode == code } }
            guard keys.count <= 1 else { return nil }
            result.shortcut = ShortcutBinding(modifiers: modifiers, keyCode: keys.first ?? 0)
        case 0x74:
            let bytes = Array(actual.action)
            guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
            for i in stride(from: 0, to: bytes.count, by: 2) {
                guard let action = MacroAction(rawValue: bytes[i]) else { return nil }
                result.macro.append(MacroStep(action: action, param: bytes[i + 1]))
            }
        default: return nil
        }
        guard let mode = AhaKeyModeSlot(rawValue: Int(actual.mode)),
              (try? make(key: result, mode: mode)) == actual else { return nil }
        return result
    }

    static func summary(_ value: OrdinaryKeyReadback) -> String {
        let action: String
        switch value.actionType {
        case 0: action = NSLocalizedString("无按键动作", comment: "")
        case 0x73:
            action = value.action.isEmpty ? NSLocalizedString("无按键动作", comment: "") : value.action.map { HIDUsage.name(for: $0) }.joined(separator: " + ")
        case 0x74:
            action = String(format: NSLocalizedString("宏（%@ 步）", comment: ""), String(value.action.count / 2))
        default: action = NSLocalizedString("未识别动作，保留原数据", comment: "")
        }
        return action + " · " + (String(data: value.description, encoding: .ascii) ?? value.description.map { String(format: "%02X", $0) }.joined())
    }
}

@MainActor
enum StudioInlineKeySave {
    enum Result {
        case saved(StudioInlineKeyFact)
        case unchanged(StudioInlineKeyFact)
        case conflict(StudioInlineKeyConflict)
    }

    /// A conflict is a pre-write result. Confirming it supplies the newly read
    /// baseline to another run; it never bypasses the next preflight read.
    static func run(session: StudioInspectorSession, baseline: StudioInlineKeyFact,
                    desired: OrdinaryKeyReadback,
                    read: (UInt8, UInt8) async throws -> OrdinaryKeyReadback,
                    save: (OrdinaryKeyReadback, OrdinaryKeyReadback, UInt64) async throws -> OrdinaryKeyReadback,
                    writeStarted: () -> Void) async throws -> Result {
        guard desired.mode == baseline.value.mode, desired.keyIndex == baseline.value.keyIndex,
              OrdinaryKeyConfiguration.valid(desired) else { throw ConfirmedOrdinaryKeySetting.Failure.invalidValue }
        return try await session.withConnection(expectedDeviceID: baseline.deviceID) { context in
            let actual = try await read(desired.mode, desired.keyIndex)
            guard actual.mode == desired.mode, actual.keyIndex == desired.keyIndex else {
                throw ConfirmedOrdinaryKeySetting.Failure.mismatch
            }
            guard actual == baseline.value else {
                return .conflict(.init(deviceID: context.deviceID, actual: actual, desired: desired))
            }
            if actual == desired { return .unchanged(.init(deviceID: context.deviceID, value: actual)) }
            writeStarted()
            let confirmed = try await save(actual, desired, context.generation)
            return .saved(.init(deviceID: context.deviceID, value: confirmed))
        }
    }
}
