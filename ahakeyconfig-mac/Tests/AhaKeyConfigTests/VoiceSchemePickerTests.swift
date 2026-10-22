import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class VoiceSchemePickerTests: XCTestCase {
    private let policy = VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false, longPressThresholdMs: 500)
    private func snapshot(_ draft: AhaKeyStudioDraft, state: UInt8) throws -> VoiceHandoffSnapshot {
        .init(onboardingState: state, keys: try AhaKeyModeSlot.allCases.map {
            try StudioKeyWriteProposal.make(key: draft.draft(for: $0).key(for: .voice), mode: $0)
        })
    }

    func testNewPickerSeparatesConsumerCloudAndCustomWithoutReinterpretingOldProfiles() throws {
        XCTAssertEqual(VoicePreset.visibleCases, [.systemDictation, .ahaTypeCloud, .custom])
        XCTAssertFalse(VoicePreset.systemDictation.usesAppTranscription)
        XCTAssertTrue(VoicePreset.ahaTypeCloud.usesAppTranscription)
        let old = try JSONDecoder().decode(VoicePreset.self, from: Data("\"macOSNative\"".utf8))
        XCTAssertEqual(old, .macOSNative)
        XCTAssertTrue(old.usesAppTranscription)
        XCTAssertNotEqual(old.pickerCategory, .systemDictation)
        XCTAssertEqual(VoicePreset.typeless.pickerCategory, .custom)
        XCTAssertNotEqual(VoicePreset.typeless.pickerCategory, .ahaTypeCloud)
    }

    func testFreshDefaultsAreConsumerAndHaveNoAppVoiceHooks() {
        XCTAssertTrue(AhaKeyModeSlot.allCases.allSatisfy { AhaKeyStudioDraft.default.draft(for: $0).key(for: .voice).voicePreset == .systemDictation })
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: .default).isEmpty)
    }

    func testLegacyAppAndFnProfilesKeepExistingRoutesDuringMigration() throws {
        var old = AhaKeyStudioDraft.legacyAppVoice
        var mode = old.draft(for: .mode1)
        var fn = mode.key(for: .voice); fn.voicePreset = .typeless; fn.shortcut = VoicePreset.typeless.defaultBinding
        mode.updateKey(fn); old.updateMode(mode)
        let migrated = StudioVoiceConfiguration(draft: old, fallback: policy)
        let routes = VoiceRelayService.buildRoutes(from: migrated.routeDraft)
        XCTAssertEqual(migrated.key(for: .mode0).voicePreset, .macOSNative)
        XCTAssertTrue(routes.contains { $0.mode == .mode0 && $0.action == .macOSDictation })
        XCTAssertTrue(routes.contains { $0.mode == .mode1 && $0.action.isFunctionRelay })
    }

    func testGlobalConsumerExitKeepsEveryOtherPhysicalBindingAndDoesNotArmTheirF18() throws {
        let original = AhaKeyStudioDraft.default
        let before = StudioVoiceConfiguration(draft: original, fallback: policy)
        var selected = before.key(for: .mode2)
        selected.voicePreset = .custom
        selected.shortcut = ShortcutBinding(modifiers: [.command, .option], keyCode: HIDUsage.enter)
        var afterDraft = original
        var mode = afterDraft.draft(for: .mode2); mode.updateKey(selected); afterDraft.updateMode(mode)
        let actual = try snapshot(afterDraft, state: 3)
        let after = try before.afterGlobalExit(key: selected, mode: .mode2, actual: actual)
        for slot in AhaKeyModeSlot.allCases where slot != .mode2 {
            XCTAssertEqual(try StudioKeyWriteProposal.make(key: after.key(for: slot), mode: slot), try StudioKeyWriteProposal.make(key: before.key(for: slot), mode: slot))
            XCTAssertEqual(after.key(for: slot).voicePreset, .custom)
        }
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: after.routeDraft).isEmpty)
    }

    func testCloudSelectionArmsOnlySelectedModeAndBothPressesUseAhaType() throws {
        let before = StudioVoiceConfiguration(draft: .default, fallback: policy)
        var selected = before.key(for: .mode2); selected.voicePreset = .ahaTypeCloud
        let prepared = try before.preparing(selected, mode: .mode2)
        XCTAssertEqual(prepared.voiceProcessingPolicy?.shortPressAhaType, true)
        XCTAssertEqual(prepared.voiceProcessingPolicy?.longPressAhaType, true)
        let actual = try snapshot(before.routeDraft, state: 3)
        let after = try before.afterGlobalExit(key: prepared, mode: .mode2, actual: actual)
        let routes = VoiceRelayService.buildRoutes(from: after.routeDraft)
        XCTAssertFalse(routes.isEmpty)
        XCTAssertTrue(routes.allSatisfy { $0.mode == .mode2 && $0.action == .macOSDictation })
    }

    func testConsumerReadConfirmationCannotPretendToRestoreSuppressedFirmware() throws {
        let before = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        XCTAssertThrowsError(try before.confirmingConsumer(snapshot(before.routeDraft, state: 3)))
        let actual = try snapshot(before.routeDraft, state: 2)
        let consumer = try before.confirmingConsumer(actual)
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: consumer.routeDraft).isEmpty)
        for slot in AhaKeyModeSlot.allCases {
            XCTAssertEqual(try StudioKeyWriteProposal.make(key: consumer.key(for: slot), mode: slot), actual.keys[slot.rawValue])
        }
    }
    func testOpaqueOtherModeNeverKeepsStaleAppRouteAndPreservesActualReadOnlyBytes() throws {
        let before = StudioVoiceConfiguration(draft: .legacyAppVoice, fallback: policy)
        var selected = before.key(for: .mode2); selected.voicePreset = .ahaTypeCloud
        selected = try before.preparing(selected, mode: .mode2)
        var keys = try snapshot(before.routeDraft, state: 3).keys
        let raw = OrdinaryKeyReadback(mode: 0, keyIndex: 0, actionType: 0x73,
            action: Data([HIDUsage.enter, HIDUsage.leftGUI]), description: Data("External".utf8))
        keys[0] = raw
        let actual = VoiceHandoffSnapshot(onboardingState: 3, keys: keys)
        let after = try before.afterGlobalExit(key: selected, mode: .mode2, actual: actual)
        XCTAssertEqual(after.key(for: .mode0).voicePreset, .custom)
        XCTAssertEqual(after.readOnlyBinding(for: .mode0), raw)
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: after.routeDraft).allSatisfy { $0.mode != .mode0 })
        XCTAssertTrue(after.isValid)
        let restored = try JSONDecoder().decode(StudioVoiceConfiguration.self, from: JSONEncoder().encode(after))
        XCTAssertEqual(restored.readOnlyBinding(for: .mode0), raw)
        let consumer = try before.confirmingConsumer(.init(onboardingState: 2, keys: keys))
        XCTAssertEqual(consumer.readOnlyBinding(for: .mode0), raw)
        XCTAssertNotEqual(consumer.key(for: .mode0).shortcut, before.key(for: .mode0).shortcut)
        XCTAssertTrue(consumer.isValid)
    }

}
