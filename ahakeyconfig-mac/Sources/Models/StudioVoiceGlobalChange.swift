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
        return observing(actual, consumer: true, excluding: nil)
    }

    func afterGlobalExit(key selected: AhaKeyKeyDraft, mode: AhaKeyModeSlot, actual: VoiceHandoffSnapshot) throws -> Self {
        guard actual.isValid, actual.onboardingState == 3 || actual.onboardingState == 4 else {
            throw ConfirmedVoiceHandoff.Failure.ownershipMismatch
        }
        let observed = observing(actual, consumer: false, excluding: mode)
        return try observed.committing(key: selected, mode: mode, actual: actual.keys[mode.rawValue])
    }
}
