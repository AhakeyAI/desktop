import XCTest
@testable import AhaKeyConfig

final class VoiceHandoffHostTests: XCTestCase {
    @MainActor
    func testPreparedDraftOnlyReplacesVoiceTriggersInEveryMode() {
        var original = AhaKeyStudioDraft.default
        var mode = original.draft(for: .mode0)
        var voice = mode.key(for: .voice)
        voice.voicePreset = .typeless
        voice.voiceProcessingPolicy = .init(shortPressAhaType: true, longPressAhaType: true, longPressThresholdMs: 900)
        voice.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        voice.macro = [MacroStep(action: .downKey, param: HIDUsage.enter)]
        voice.description = "Keep voice label"
        mode.updateKey(voice); original.updateMode(mode)
        let prepared = VoiceHandoffHost.preparedDraft(from: original)
        for slot in AhaKeyModeSlot.allCases {
            let before = original.draft(for: slot), after = prepared.draft(for: slot)
            let voice = after.key(for: .voice)
            XCTAssertEqual(voice.voicePreset, .macOSNative)
            XCTAssertNil(voice.voiceProcessingPolicy)
            XCTAssertEqual(voice.shortcut, ShortcutBinding(keyCode: HIDUsage.f18))
            XCTAssertTrue(voice.macro.isEmpty)
            XCTAssertEqual(voice.description, before.key(for: .voice).description)
            for role in AhaKeyKeyRole.allCases where role != .voice {
                XCTAssertEqual(after.key(for: role), before.key(for: role))
            }
            XCTAssertEqual(after.oled, before.oled)
            XCTAssertEqual(after.lightBar, before.lightBar)
        }
    }

    @MainActor
    func testConfirmedVoiceDoesNotMarkOtherDraftChangesApplied() {
        var saved = AhaKeyStudioDraft.default
        var initial = saved.draft(for: .mode0)
        var previous = initial.key(for: .voice)
        previous.voicePreset = .typeless
        previous.shortcut = ShortcutBinding(keyCode: HIDUsage.f19)
        initial.updateKey(previous); saved.updateMode(initial)
        var pending = saved
        var mode = pending.draft(for: .mode0)
        var voice = mode.key(for: .voice)
        voice.description = "Pending label"
        mode.updateKey(voice)
        var other = mode.key(for: .approve)
        other.shortcut = ShortcutBinding(keyCode: HIDUsage.escape)
        mode.updateKey(other)
        pending.updateMode(mode)
        let prepared = VoiceHandoffHost.preparedDraft(from: pending)
        let confirmed = VoiceHandoffHost.confirmedBaseline(from: saved)
        XCTAssertEqual(confirmed.draft(for: .mode0).key(for: .voice).shortcut, prepared.draft(for: .mode0).key(for: .voice).shortcut)
        XCTAssertNotEqual(confirmed.draft(for: .mode0).key(for: .voice).description, prepared.draft(for: .mode0).key(for: .voice).description)
        XCTAssertNotEqual(confirmed.draft(for: .mode0).key(for: .approve), prepared.draft(for: .mode0).key(for: .approve))
    }

    @MainActor
    func testExplicitFourModeHandoffKeepsPendingLabelsWhileConfirmingResolvedPolicies() {
        let original = AhaKeyStudioDraft.default
        var pending = original
        var mode = pending.draft(for: .mode2)
        var voice = mode.key(for: .voice)
        voice.description = "Unwritten label"
        mode.updateKey(voice); pending.updateMode(mode)
        let policy = VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false, longPressThresholdMs: 500)
        let applied = StudioVoiceConfiguration(draft: VoiceHandoffHost.preparedDraft(from: pending), fallback: policy)
        let baseline = VoiceHandoffHost.confirmedBaseline(from: original, configuration: applied)
        XCTAssertEqual(baseline.draft(for: .mode2).key(for: .voice).description, original.draft(for: .mode2).key(for: .voice).description)
        XCTAssertEqual(baseline.draft(for: .mode2).key(for: .voice).voiceProcessingPolicy, policy)
    }

}
