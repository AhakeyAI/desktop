import Foundation
import AhaKeyConfigShared

/// Applied host routes are stored separately from the editable canvas. This is
/// an installation preference, not a claim that a newly connected device has
/// the same bindings. Device writes still require a fresh identified lease.
struct StudioVoiceConfiguration: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let mode: AhaKeyModeSlot
        var key: AhaKeyKeyDraft
    }
    private(set) var version = 1
    private(set) var entries: [Entry]

    init(draft: AhaKeyStudioDraft, fallback: VoiceProcessingPolicy) {
        entries = AhaKeyModeSlot.allCases.map { mode in
            var key = draft.draft(for: mode).key(for: .voice)
            if key.voicePreset?.availableInV1 != true { key.voicePreset = .custom }
            key.voiceProcessingPolicy = key.voiceProcessingPolicy ?? fallback
            return Entry(mode: mode, key: key)
        }
    }

    var isValid: Bool {
        version == 1 && entries.count == 4 && Set(entries.map(\.mode)) == Set(AhaKeyModeSlot.allCases) &&
        entries.allSatisfy { entry in
            guard entry.key.role == .voice, let preset = entry.key.voicePreset, preset.availableInV1,
                  let policy = entry.key.voiceProcessingPolicy else { return false }
            return (200...2_000).contains(policy.longPressThresholdMs)
        }
    }

    func key(for mode: AhaKeyModeSlot) -> AhaKeyKeyDraft {
        entries.first { $0.mode == mode }!.key
    }

    func overlay(on original: AhaKeyStudioDraft) -> AhaKeyStudioDraft {
        var result = original
        for entry in entries {
            var mode = result.draft(for: entry.mode)
            mode.updateKey(entry.key)
            result.updateMode(mode)
        }
        return result
    }

    var routeDraft: AhaKeyStudioDraft { overlay(on: .default) }

    /// Resolve the same fallback the inspector displays and reject invalid host
    /// settings before any hardware write is attempted.
    func preparing(_ draft: AhaKeyKeyDraft, mode: AhaKeyModeSlot) throws -> AhaKeyKeyDraft {
        guard draft.role == .voice, let index = entries.firstIndex(where: { $0.mode == mode }) else {
            throw StudioVoiceConfigurationStore.Failure.invalidConfiguration
        }
        var key = draft
        if key.voicePreset?.availableInV1 != true { key.voicePreset = .custom }
        key.voiceProcessingPolicy = key.voiceProcessingPolicy ?? self.key(for: mode).voiceProcessingPolicy
        var next = self
        next.entries[index].key = key
        guard next.isValid else { throw StudioVoiceConfigurationStore.Failure.invalidConfiguration }
        return key
    }

    func committing(key: AhaKeyKeyDraft, mode: AhaKeyModeSlot,
                    actual: OrdinaryKeyReadback) throws -> Self {
        let prepared = try preparing(key, mode: mode)
        guard actual.keyIndex == 0, actual.mode == UInt8(mode.rawValue),
              try StudioKeyWriteProposal.make(key: prepared, mode: mode) == actual else {
            throw ConfirmedOrdinaryKeySetting.Failure.mismatch
        }
        var next = self
        let index = next.entries.firstIndex { $0.mode == mode }!
        next.entries[index].key = prepared
        return next
    }

    func importing(_ actual: OrdinaryKeyReadback, preserving original: AhaKeyKeyDraft) -> AhaKeyKeyDraft? {
        guard var key = StudioKeyWriteProposal.draft(from: actual, preserving: original) else { return nil }
        if original.role == .voice, let mode = AhaKeyModeSlot(rawValue: Int(actual.mode)) {
            let applied = self.key(for: mode)
            let expected = try? StudioKeyWriteProposal.make(key: applied, mode: mode)
            key.voicePreset = expected?.actionType == actual.actionType && expected?.action == actual.action ? applied.voicePreset : .custom
            key.voiceProcessingPolicy = applied.voiceProcessingPolicy
        }
        return key
    }

    /// A hardware read cannot confirm a pending host processing/preset choice.
    static func reconcileHardware(baseline old: AhaKeyStudioDraft, current: AhaKeyStudioDraft,
                                  actual: OrdinaryKeyReadback) -> AhaKeyStudioDraft {
        var result = StudioKeyWriteProposal.reconcile(baseline: old, current: current, actual: actual)
        if actual.keyIndex == 0, let mode = AhaKeyModeSlot(rawValue: Int(actual.mode)) {
            var draft = result.draft(for: mode)
            var key = draft.key(for: .voice)
            let previous = old.draft(for: mode).key(for: .voice)
            key.voicePreset = previous.voicePreset
            key.voiceProcessingPolicy = previous.voiceProcessingPolicy
            draft.updateKey(key); result.updateMode(draft)
        }
        return result
    }

    /// Corrupt applied data must not re-arm arbitrary canvas drafts.
    static func disabled(draft: AhaKeyStudioDraft, fallback: VoiceProcessingPolicy) -> Self {
        var value = Self(draft: draft, fallback: fallback)
        for index in value.entries.indices {
            value.entries[index].key.voicePreset = .custom
            value.entries[index].key.voiceProcessingPolicy = fallback
        }
        return value
    }
}

enum StudioVoiceConfigurationStore {
    enum Failure: Error, LocalizedError {
        case invalidConfiguration, invalidStoredConfiguration
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration:
                return NSLocalizedString("语音配置无法校验，未启用本次改动；请重新读取并保存当前模式。", comment: "")
            case .invalidStoredConfiguration:
                return NSLocalizedString("已启用的语音配置无法读取，App 语音接管已暂停；请重新读取并保存当前模式。", comment: "")
            }
        }
    }
    static let storageKey = "ahakey.studio.voice.applied.v1"

    static func loadOrMigrate(draft: AhaKeyStudioDraft, fallback: VoiceProcessingPolicy,
                              defaults: UserDefaults = .standard) throws -> StudioVoiceConfiguration {
        if defaults.object(forKey: storageKey) != nil {
            guard let data = defaults.data(forKey: storageKey),
                  let value = try? JSONDecoder().decode(StudioVoiceConfiguration.self, from: data), value.isValid else {
                throw Failure.invalidStoredConfiguration
            }
            return value
        }
        let value = StudioVoiceConfiguration(draft: draft, fallback: fallback)
        try save(value, defaults: defaults)
        return value
    }

    static func save(_ value: StudioVoiceConfiguration, defaults: UserDefaults = .standard) throws {
        guard value.isValid else { throw Failure.invalidConfiguration }
        defaults.set(try JSONEncoder().encode(value), forKey: storageKey)
    }
}
