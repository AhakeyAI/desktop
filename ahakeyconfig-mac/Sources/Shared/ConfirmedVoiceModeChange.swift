import Foundation

/// Only the selected ordinary binding changes. Exiting the firmware Consumer
/// preset is global, so all four underlying bindings are checked, not rewritten.
public enum ConfirmedVoiceModeChange {
    @MainActor
    public static func run(baseline: VoiceHandoffSnapshot, target: OrdinaryKeyReadback,
                           checkSession: () throws -> Void, checkHostReady: () throws -> Void,
                           read: () async throws -> VoiceHandoffSnapshot,
                           validateCurrentKey: (OrdinaryKeyReadback) throws -> Void,
                           prepareHost: () throws -> Void,
                           write: (Data) async throws -> Void) async throws -> VoiceHandoffSnapshot {
        guard baseline.isValid, target.mode < 4, target.keyIndex == 0,
              OrdinaryKeyConfiguration.valid(target) else { throw ConfirmedVoiceHandoff.Failure.invalidSnapshot }
        var targets = baseline.keys
        let old = targets[Int(target.mode)]
        targets[Int(target.mode)] = target
        var commands: [Data] = []
        if old.actionType != target.actionType || old.action != target.action {
            guard let frame = OrdinaryKeyConfiguration.actionRequest(target) else { throw ConfirmedVoiceHandoff.Failure.invalidSnapshot }
            commands.append(frame)
        }
        if old.description != target.description {
            guard let frame = OrdinaryKeyConfiguration.descriptionRequest(target) else { throw ConfirmedVoiceHandoff.Failure.invalidSnapshot }
            commands.append(frame)
        }
        try Task.checkCancellation(); try checkSession(); try checkHostReady()
        let current = try await read()
        try Task.checkCancellation(); try checkSession()
        guard current == baseline else { throw ConfirmedVoiceHandoff.Failure.changedSinceRead }
        try validateCurrentKey(current.keys[Int(target.mode)])
        let consumerActive = current.onboardingState == 2
        if !consumerActive {
            try checkHostReady(); try prepareHost()
            try Task.checkCancellation(); try checkSession()
        }
        for frame in commands {
            try await write(frame)
            try Task.checkCancellation(); try checkSession()
        }
        if !commands.isEmpty {
            try await write(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]))
            try Task.checkCancellation(); try checkSession()
        }
        let staged = commands.isEmpty ? current : try await read()
        try Task.checkCancellation(); try checkSession()
        guard staged.keys == targets else { throw ConfirmedVoiceHandoff.Failure.bindingsMismatch }
        guard staged.onboardingState == baseline.onboardingState else { throw ConfirmedVoiceHandoff.Failure.changedSinceRead }
        try checkHostReady()
        // While Consumer owns physical presses, stage and verify first. When
        // ordinary bindings already own presses, the host is armed above.
        if consumerActive { try prepareHost() }
        try Task.checkCancellation(); try checkSession()
        if staged.onboardingState == 3 || staged.onboardingState == 4 { return staged }
        try await write(ConfirmedVoiceHandoff.suppressRequest)
        try Task.checkCancellation(); try checkSession()
        let actual = try await read()
        try Task.checkCancellation(); try checkSession()
        guard actual.onboardingState == 3 else { throw ConfirmedVoiceHandoff.Failure.ownershipMismatch }
        guard actual.keys == targets else { throw ConfirmedVoiceHandoff.Failure.bindingsMismatch }
        return actual
    }
}
