import Foundation
import AhaKeyConfigShared

enum DesktopSpeechChoice: String, CaseIterable, Identifiable {
    case native, ahaType
    var id: String { rawValue }
    var title: String { self == .native ? NSLocalizedString("App 原生转写", comment: "") : NSLocalizedString("App 转写 + AhaType", comment: "") }
}

extension Notification.Name {
    static let ahaKeyVoiceDesktopPrepared = Notification.Name("ahaKeyVoiceDesktopPrepared")
    static let ahaKeyVoiceDesktopConfirmed = Notification.Name("ahaKeyVoiceDesktopConfirmed")
}

@MainActor
enum VoiceHandoffHost {
    enum Failure: Error, LocalizedError {
        case cloudNotConfigured, cloudDisabled
        var errorDescription: String? {
            switch self {
            case .cloudNotConfigured: return NSLocalizedString("请先登录 AhaType；有效账号及额度在实际转写时验证。", comment: "")
            case .cloudDisabled: return NSLocalizedString("请先开启 AhaType 总开关，再保存当前模式的云端整理方案。", comment: "")
            }
        }
    }
    static func checkReady(_ choice: DesktopSpeechChoice) throws {
        let relay = VoiceRelayService.shared
        let speech = NativeSpeechTranscriptionService.shared
        guard relay.inputMonitoringGranted, relay.accessibilityGranted, relay.isListening,
              speech.microphoneGranted, speech.speechRecognitionGranted, !speech.isRecording else {
            throw ConfirmedVoiceHandoff.Failure.hostNotReady
        }
        if choice == .ahaType, !AhaTypeTextOptimizer.shared.hasConfiguredCloudToken { throw Failure.cloudNotConfigured }
    }

    static func prepare(_ choice: DesktopSpeechChoice, baseline: VoiceHandoffSnapshot) throws {
        try checkReady(choice)
        try backup(baseline)
        let original = preparedDraft(from: AhaKeyStudioStore.load() ?? .default)
        let speech = NativeSpeechTranscriptionService.shared
        let policy = VoiceProcessingPolicy(shortPressAhaType: choice == .ahaType,
            longPressAhaType: choice == .ahaType, longPressThresholdMs: min(2_000, max(200, speech.longPressThresholdMs)))
        let applied = StudioVoiceConfiguration(draft: original, fallback: policy)
        try StudioVoiceConfigurationStore.save(applied)
        let draft = applied.overlay(on: original)
        let relay = VoiceRelayService.shared
        relay.updateRoutes(from: draft)
        guard relay.hasPreparedNativeF18Routes else { throw ConfirmedVoiceHandoff.Failure.hostNotReady }
        AhaTypeTextOptimizer.shared.setEnabled(choice == .ahaType)
        speech.shortPressAhaTypeEnabled = choice == .ahaType
        speech.longPressAhaTypeEnabled = choice == .ahaType
        AhaKeyStudioStore.save(draft)
        NotificationCenter.default.post(name: .ahaKeyVoiceDesktopPrepared, object: nil)
    }

    static func backup(_ baseline: VoiceHandoffSnapshot) throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AhaKeyConfig/voice-handoff-backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let values: [[String: Any]] = baseline.keys.map {
            ["mode": Int($0.mode), "keyIndex": Int($0.keyIndex), "actionType": Int($0.actionType),
             "action": Array($0.action).map(Int.init), "description": Array($0.description).map(Int.init)]
        }
        let backup = try JSONSerialization.data(withJSONObject: ["onboardingState": Int(baseline.onboardingState), "keys": values], options: [.prettyPrinted, .sortedKeys])
        let url = directory.appendingPathComponent(UUID().uuidString + ".json")
        try backup.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

    }

    static func preparedDraft(from original: AhaKeyStudioDraft) -> AhaKeyStudioDraft {
        var draft = original
        for mode in AhaKeyModeSlot.allCases {
            var modeDraft = draft.draft(for: mode)
            var voice = modeDraft.key(for: .voice)
            voice.voicePreset = .macOSNative
            voice.voiceProcessingPolicy = nil
            voice.shortcut = ShortcutBinding(keyCode: HIDUsage.f18)
            voice.macro = []
            modeDraft.updateKey(voice)
            draft.updateMode(modeDraft)
        }
        return draft
    }

    /// Confirm only fields actually applied by the handoff. In particular, a
    /// pending description or any non-Voice edit must remain pending.
    static func confirmedBaseline(from original: AhaKeyStudioDraft, configuration: StudioVoiceConfiguration? = nil) -> AhaKeyStudioDraft {
        var baseline = preparedDraft(from: original)
        if let configuration {
            for slot in AhaKeyModeSlot.allCases {
                var mode = baseline.draft(for: slot)
                var voice = mode.key(for: .voice)
                voice.voiceProcessingPolicy = configuration.key(for: slot).voiceProcessingPolicy
                mode.updateKey(voice); baseline.updateMode(mode)
            }
        }
        return baseline
    }

}
