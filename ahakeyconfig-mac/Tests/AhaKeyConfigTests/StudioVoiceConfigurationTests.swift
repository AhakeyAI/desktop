import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class StudioVoiceConfigurationTests: XCTestCase {
    private let policy = VoiceProcessingPolicy(shortPressAhaType: true, longPressAhaType: false, longPressThresholdMs: 500)

    private var suites: [String] = []
    private func defaults() -> UserDefaults {
        let suite = "StudioVoiceConfigurationTests.\(UUID())"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    func testMigrationFreezesLegacySettingsAndLaterDraftCannotRearmRoutes() throws {
        let preferences = defaults()
        let original = AhaKeyStudioDraft.legacyAppVoice
        let applied = try StudioVoiceConfigurationStore.loadOrMigrate(draft: original, fallback: policy, defaults: preferences)
        var pending = original
        var mode = pending.draft(for: .mode2)
        var voice = mode.key(for: .voice)
        voice.voicePreset = .custom
        voice.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        voice.voiceProcessingPolicy = .init(shortPressAhaType: false, longPressAhaType: true, longPressThresholdMs: 900)
        mode.updateKey(voice); pending.updateMode(mode)
        let restarted = try StudioVoiceConfigurationStore.loadOrMigrate(draft: pending,
            fallback: .init(shortPressAhaType: false, longPressAhaType: true, longPressThresholdMs: 700), defaults: preferences)
        XCTAssertEqual(restarted, applied)
        XCTAssertEqual(restarted.key(for: .mode2).voiceProcessingPolicy, policy)
        XCTAssertEqual(VoiceRelayService.buildRoutes(from: restarted.routeDraft), VoiceRelayService.buildRoutes(from: applied.routeDraft))
    }

    func testCommitPersistsOnlyOneModeAndLeavesOtherDraftsUntouched() throws {
        let preferences = defaults()
        let original = AhaKeyStudioDraft.legacyAppVoice
        let applied = StudioVoiceConfiguration(draft: original, fallback: policy)
        var voice = applied.key(for: .mode2)
        voice.voicePreset = .custom
        voice.shortcut = ShortcutBinding(modifiers: [.option], keyCode: HIDUsage.enter)
        voice.description = "Local voice"
        let actual = try StudioKeyWriteProposal.make(key: voice, mode: .mode2)
        let committed = try applied.committing(key: voice, mode: .mode2, actual: actual)
        try StudioVoiceConfigurationStore.save(committed, defaults: preferences)
        let restarted = try StudioVoiceConfigurationStore.loadOrMigrate(draft: original, fallback: policy, defaults: preferences)
        XCTAssertEqual(restarted.key(for: .mode2), voice)
        for slot in AhaKeyModeSlot.allCases where slot != .mode2 {
            XCTAssertEqual(restarted.key(for: slot), applied.key(for: slot))
        }
        for slot in AhaKeyModeSlot.allCases {
            let mode = restarted.overlay(on: original).draft(for: slot)
            XCTAssertEqual(mode.oled, original.draft(for: slot).oled)
            XCTAssertEqual(mode.lightBar, original.draft(for: slot).lightBar)
            for role in AhaKeyKeyRole.allCases where role != .voice {
                XCTAssertEqual(mode.key(for: role), original.draft(for: slot).key(for: role))
            }
        }
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: restarted.routeDraft).allSatisfy { $0.mode != .mode2 })
    }

    func testPolicyOnlyCommitChangesNoOtherModeOrHardwareProposal() throws {
        let before = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        var voice = before.key(for: .mode2)
        let actual = try StudioKeyWriteProposal.make(key: voice, mode: .mode2)
        voice.voiceProcessingPolicy?.shortPressAhaType = false
        let after = try before.committing(key: voice, mode: .mode2, actual: actual)
        XCTAssertEqual(try StudioKeyWriteProposal.make(key: after.key(for: .mode2), mode: .mode2), actual)
        XCTAssertNotEqual(after.key(for: .mode2), before.key(for: .mode2))
        XCTAssertEqual(after.key(for: .mode1), before.key(for: .mode1))
    }

    func testMismatchedReadbackCannotPublishDesiredHostRoute() throws {
        let before = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        var voice = before.key(for: .mode2)
        voice.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        let old = try StudioKeyWriteProposal.make(key: before.key(for: .mode2), mode: .mode2)
        XCTAssertThrowsError(try before.committing(key: voice, mode: .mode2, actual: old))
        let otherMode = try StudioKeyWriteProposal.make(key: voice, mode: .mode1)
        XCTAssertThrowsError(try before.committing(key: voice, mode: .mode2, actual: otherMode))
        XCTAssertNotEqual(before.key(for: .mode2).shortcut, voice.shortcut)
    }

    func testCorruptAppliedConfigurationCannotFallBackToPendingDraft() throws {
        for payload in [Data("not json".utf8), Data("{}".utf8)] {
            let preferences = defaults()
            preferences.set(payload, forKey: StudioVoiceConfigurationStore.storageKey)
            XCTAssertThrowsError(try StudioVoiceConfigurationStore.loadOrMigrate(draft: .legacyAppVoice, fallback: policy, defaults: preferences))
            XCTAssertEqual(preferences.data(forKey: StudioVoiceConfigurationStore.storageKey), payload)
        }
        let disabled = StudioVoiceConfiguration.disabled(draft: .legacyAppVoice, fallback: policy)
        XCTAssertTrue(disabled.isValid)
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: disabled.routeDraft).isEmpty)
    }

    func testUnknownSchemaAndDuplicateModesAreRejected() throws {
        let original = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        let preferences = defaults()
        payload["version"] = 99
        preferences.set(try JSONSerialization.data(withJSONObject: payload), forKey: StudioVoiceConfigurationStore.storageKey)
        XCTAssertThrowsError(try StudioVoiceConfigurationStore.loadOrMigrate(draft: .legacyAppVoice, fallback: policy, defaults: preferences))
        payload["version"] = 1
        var entries = payload["entries"] as! [[String: Any]]
        entries[1] = entries[0]
        payload["entries"] = entries
        preferences.set(try JSONSerialization.data(withJSONObject: payload), forKey: StudioVoiceConfigurationStore.storageKey)
        XCTAssertThrowsError(try StudioVoiceConfigurationStore.loadOrMigrate(draft: .legacyAppVoice, fallback: policy, defaults: preferences))
    }
    func testHardwareImportCannotAdoptPendingHostSettingsOrArmForeignShortcut() throws {
        let applied = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        let saved = applied.key(for: .mode2)
        let actual = try StudioKeyWriteProposal.make(key: saved, mode: .mode2)
        var pending = saved
        pending.voicePreset = .typeless
        pending.voiceProcessingPolicy?.shortPressAhaType = false
        let imported = try XCTUnwrap(applied.importing(actual, preserving: pending))
        XCTAssertEqual(imported.voicePreset, saved.voicePreset)
        XCTAssertEqual(imported.voiceProcessingPolicy, saved.voiceProcessingPolicy)
        var foreign = saved
        foreign.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        let foreignValue = try StudioKeyWriteProposal.make(key: foreign, mode: .mode2)
        let foreignDraft = try XCTUnwrap(applied.importing(foreignValue, preserving: saved))
        XCTAssertEqual(foreignDraft.voicePreset, .custom)
        XCTAssertEqual(applied.key(for: .mode2), saved)
        XCTAssertNotEqual(foreignDraft.shortcut, saved.shortcut)
    }

    func testHardwareReconciliationDoesNotConfirmPendingHostChoice() throws {
        let applied = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        let baseline = applied.routeDraft
        var current = baseline
        var mode = current.draft(for: .mode2)
        var voice = mode.key(for: .voice)
        voice.voicePreset = .custom
        voice.voiceProcessingPolicy?.shortPressAhaType = false
        voice.description = "Read label"
        mode.updateKey(voice); current.updateMode(mode)
        let actual = try StudioKeyWriteProposal.make(key: voice, mode: .mode2)
        let result = StudioVoiceConfiguration.reconcileHardware(baseline: baseline, current: current, actual: actual)
        let reconciled = result.draft(for: .mode2).key(for: .voice)
        XCTAssertEqual(reconciled.description, "Read label")
        XCTAssertEqual(reconciled.voicePreset, baseline.draft(for: .mode2).key(for: .voice).voicePreset)
        XCTAssertEqual(reconciled.voiceProcessingPolicy, policy)
        XCTAssertNotEqual(reconciled, voice)
    }

    func testLegacyModesWithoutUsablePresetDoNotPauseOtherModes() throws {
        for missing: VoicePreset? in [nil, .codex] {
            var old = AhaKeyStudioDraft.legacyAppVoice
            var mode = old.draft(for: .mode1)
            var voice = mode.key(for: .voice)
            voice.voicePreset = missing
            mode.updateKey(voice); old.updateMode(mode)
            let expected = VoiceRelayService.buildRoutes(from: old)
            let migrated = try StudioVoiceConfigurationStore.loadOrMigrate(draft: old, fallback: policy, defaults: defaults())
            XCTAssertTrue(migrated.isValid)
            XCTAssertEqual(migrated.key(for: .mode1).voicePreset, .custom)
            let actual = VoiceRelayService.buildRoutes(from: migrated.routeDraft)
            XCTAssertEqual(actual.map(\.mode), expected.map(\.mode))
            XCTAssertEqual(actual.map(\.binding), expected.map(\.binding))
            XCTAssertEqual(actual.map(\.action), expected.map(\.action))
            XCTAssertTrue(actual.contains { $0.mode == .mode2 })
        }
    }

    func testRestoredDefaultsResolveDisplayedPolicyBeforeHardwareCommit() throws {
        let applied = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        let restored = AhaKeyModeDraft.default(for: .mode2).key(for: .voice)
        XCTAssertNil(restored.voiceProcessingPolicy)
        let prepared = try applied.preparing(restored, mode: .mode2)
        XCTAssertEqual(prepared.voiceProcessingPolicy, applied.key(for: .mode2).voiceProcessingPolicy)
        let actual = try StudioKeyWriteProposal.make(key: restored, mode: .mode2)
        let saved = try applied.committing(key: restored, mode: .mode2, actual: actual)
        XCTAssertEqual(saved.key(for: .mode2), prepared)
        var invalid = restored
        invalid.voiceProcessingPolicy = .init(shortPressAhaType: false, longPressAhaType: false, longPressThresholdMs: -1)
        XCTAssertThrowsError(try applied.preparing(invalid, mode: .mode2))
    }

}
