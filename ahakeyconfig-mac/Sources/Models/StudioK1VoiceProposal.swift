import Foundation
import AhaKeyConfigShared

/// Converts one explicit Voice choice. The route is independent of the legacy
/// global onboarding byte; Consumer must not be represented as a fake F18 key.
enum StudioK1VoiceProposal {
    static func route(for key: AhaKeyKeyDraft) throws -> K1OutputRoute {
        guard key.role == .voice else { throw StudioKeyWriteProposal.Failure.action }
        if key.voicePreset == .systemDictation {
            return K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))!
        }
        let payload = key.usesMacro ? key.macro.flattenedBytes : key.shortcut.hidCodes
        // 0x9E can carry a larger action, but the current 0x87 contract must
        // still independently verify its description and ordinary projection.
        guard payload.count <= 98, 11 + payload.count + (try description(for: key)).count <= 64 else { throw StudioKeyWriteProposal.Failure.action }
        let actionBytes: [UInt8] = [key.usesMacro ? 0x74 : 0x73, UInt8(payload.count)] + payload
        let action = Data(actionBytes)
        guard (payload.isEmpty && !key.usesMacro) || SideSwitchBindingConfiguration.validAction(action, maximumBytes: 100),
              let route = K1OutputRoute(kind: .ordinary, action: action) else { throw StudioKeyWriteProposal.Failure.action }
        return route
    }
    static func projection(_ route: K1OutputRoute, mode: UInt8, description: Data) -> OrdinaryKeyReadback {
        let bytes = [UInt8](route.action)
        return .init(mode: mode, keyIndex: 0, actionType: route.kind == .consumer || bytes.isEmpty ? 0 : bytes[0],
                     action: route.kind == .consumer || bytes.isEmpty ? Data() : Data(bytes.dropFirst(2)), description: description)
    }
    static func description(for key: AhaKeyKeyDraft) throws -> Data {
        guard var result = key.description.data(using: .ascii), result.count <= 20 else { throw StudioKeyWriteProposal.Failure.description }
        while result.last == 0x20 { result.removeLast() }
        return result
    }
    static func importing(route: K1OutputRoute, actual: OrdinaryKeyReadback,
                          configuration: StudioVoiceConfiguration, preserving original: AhaKeyKeyDraft) -> AhaKeyKeyDraft? {
        guard actual.keyIndex == 0, original.role == .voice,
              projection(route, mode: actual.mode, description: actual.description) == actual,
              let text = String(data: actual.description, encoding: .ascii) else { return nil }
        if route.kind == .consumer {
            guard route.action == Data([0xCF, 0]) else { return nil }
            var key = original; key.voicePreset = .systemDictation; key.description = text; key.macro = []
            key.shortcut = VoicePreset.systemDictation.defaultBinding
            return key
        }
        if actual.actionType == 0 {
            var key = original; key.voicePreset = .custom; key.description = text
            key.macro = []; key.shortcut = ShortcutBinding(); return key
        }
        guard var imported = configuration.importing(actual, preserving: original) else { return nil }
        // Consumer's historical placeholder shortcut is also F18. Matching
        // that byte is never proof that an ordinary route is Consumer.
        if imported.voicePreset == .systemDictation { imported.voicePreset = .custom }
        return imported
    }
    static func summary(route: K1OutputRoute, actual: OrdinaryKeyReadback) -> String {
        if route.kind == .consumer {
            let action = route.action == Data([0xCF, 0]) ? NSLocalizedString("Consumer（系统听写）", comment: "") : String(format: "Consumer 0x%04X", Int(route.action[0]) | Int(route.action[1]) << 8)
            return action + " · " + (String(data: actual.description, encoding: .ascii) ?? "")
        }
        return StudioKeyWriteProposal.summary(actual)
    }
}
