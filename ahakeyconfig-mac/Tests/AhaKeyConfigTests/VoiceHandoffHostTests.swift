import XCTest
@testable import AhaKeyConfig

final class VoiceHandoffHostTests: XCTestCase {
    @MainActor
    func testPreparedDraftOnlyReplacesVoiceTriggersInEveryMode() {
        var original = AhaKeyStudioDraft.default
        var mode = original.draft(for: .mode0)
        var voice = mode.key(for: .voice)
        voice.voicePreset = .typeless
        voice.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        voice.macro = [MacroStep(action: .downKey, param: HIDUsage.enter)]
        voice.description = "Keep voice label"
        mode.updateKey(voice); original.updateMode(mode)
        let prepared = VoiceHandoffHost.preparedDraft(from: original)
        for slot in AhaKeyModeSlot.allCases {
            let before = original.draft(for: slot), after = prepared.draft(for: slot)
            let voice = after.key(for: .voice)
            XCTAssertEqual(voice.voicePreset, .macOSNative)
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
}
