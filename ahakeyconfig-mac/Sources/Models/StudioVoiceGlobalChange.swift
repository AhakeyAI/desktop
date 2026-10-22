import Foundation
import AhaKeyConfigShared

struct StudioVoiceGlobalChange: Identifiable {
    let id = UUID()
    let deviceID: String
    let operationID: UUID
    let baseline: VoiceHandoffSnapshot
    let key: AhaKeyKeyDraft
    let target: OrdinaryKeyReadback
    var exitsGlobalPreset: Bool { baseline.onboardingState != 3 && baseline.onboardingState != 4 }
}

extension StudioVoiceConfiguration {
    /// Reconcile the effective host routes after the global Consumer preset is
    /// disabled. Other ordinary device bindings are read, never rewritten.
    func confirmingConsumer(_ actual: VoiceHandoffSnapshot) throws -> Self {
        guard actual.isValid, actual.onboardingState == 2 else { throw ConfirmedVoiceHandoff.Failure.ownershipMismatch }
        var draft = routeDraft
        for slot in AhaKeyModeSlot.allCases {
            let old = key(for: slot)
            var consumer = importing(actual.keys[slot.rawValue], preserving: old) ?? old
            consumer.voicePreset = .systemDictation
            var mode = draft.draft(for: slot); mode.updateKey(consumer); draft.updateMode(mode)
        }
        return StudioVoiceConfiguration(draft: draft, fallback: .legacy())
    }

    func afterGlobalExit(key selected: AhaKeyKeyDraft, mode: AhaKeyModeSlot, actual: VoiceHandoffSnapshot) throws -> Self {
        guard actual.isValid, actual.onboardingState == 3 || actual.onboardingState == 4 else {
            throw ConfirmedVoiceHandoff.Failure.ownershipMismatch
        }
        var draft = routeDraft
        for slot in AhaKeyModeSlot.allCases where slot != mode {
            let old = key(for: slot)
            var imported = importing(actual.keys[slot.rawValue], preserving: old) ?? old
            if imported.voicePreset == .systemDictation { imported.voicePreset = .custom }
            var value = draft.draft(for: slot)
            value.updateKey(imported); draft.updateMode(value)
        }
        let updated = StudioVoiceConfiguration(draft: draft, fallback: .legacy())
        return try updated.committing(key: selected, mode: mode, actual: actual.keys[mode.rawValue])
    }
}
