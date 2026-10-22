@testable import AhaKeyConfig

extension AhaKeyStudioDraft {
    /// Stored drafts from releases before the Consumer/default picker split.
    static var legacyAppVoice: Self {
        var draft = Self.default
        for slot in AhaKeyModeSlot.allCases {
            var mode = draft.draft(for: slot)
            var key = mode.key(for: .voice)
            key.voicePreset = .macOSNative
            key.shortcut = VoicePreset.macOSNative.defaultBinding
            mode.updateKey(key); draft.updateMode(mode)
        }
        return draft
    }
}
