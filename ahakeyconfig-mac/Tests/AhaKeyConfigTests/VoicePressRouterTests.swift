import XCTest
import CoreGraphics
@testable import AhaKeyConfig

final class VoicePressRouterTests: XCTestCase {
    private func route(_ mode: AhaKeyModeSlot, code: CGKeyCode = 79,
                       modifiers: Set<ShortcutModifier> = [], action: VoiceRouteAction = .macOSDictation) -> VoiceRoute {
        .init(binding: .init(keyCode: code, modifiers: modifiers), action: action, mode: mode, compatibilityLabel: nil)
    }

    func testCurrentModeNeverBorrowsAnotherModesRoute() {
        var router = VoicePressRouter()
        let other = route(.mode0)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: [other]), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
    }

    func testSelectsExactModeWithSharedTrigger() {
        var router = VoicePressRouter()
        let first = route(.mode0, action: .functionRelay(appName: "Fn")), current = route(.mode2)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: [first, current]), .route(current))
        XCTAssertEqual(router.keyUp(code: 79), .route(current))
    }

    func testReleaseKeepsOriginalModeActionAndModifierBinding() {
        var router = VoicePressRouter()
        let original = route(.mode0, modifiers: [.command], action: .functionRelay(appName: "Fn"))
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [.command], isRepeat: false, mode: .mode0, routes: [original]), .route(original))
        // Mode, modifiers, and configuration all change while the key is held.
        let replacement = route(.mode2)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: true, mode: .mode2, routes: [replacement]), .suppressRepeat)
        XCTAssertEqual(router.keyUp(code: 79), .route(original))
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: [replacement]), .route(replacement))
    }

    func testNewRouteCannotStealPreviouslyPassedThroughPress() {
        var router = VoicePressRouter()
        let current = route(.mode2)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: []), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: true, mode: .mode2, routes: [current]), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: [current]), .route(current))
    }

    func testOrphanReleaseAndRepeatCannotStartRecording() {
        var router = VoicePressRouter()
        let current = route(.mode2)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: true, mode: .mode2, routes: [current]), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: nil, routes: [current]), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
    }

    func testResetAllowsFreshPressWithoutLeakingPriorRoute() {
        var router = VoicePressRouter()
        let original = route(.mode0), current = route(.mode2)
        _ = router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode0, routes: [original])
        router.reset()
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: [current]), .route(current))
    }

    func testMultipleHeldKeysReleaseIndependently() {
        var router = VoicePressRouter()
        let first = route(.mode0, code: 79), second = route(.mode0, code: 80)
        _ = router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode0, routes: [first, second])
        _ = router.keyDown(code: 80, modifiers: [], isRepeat: false, mode: .mode0, routes: [first, second])
        XCTAssertEqual(router.keyUp(code: 80), .route(second))
        XCTAssertEqual(router.keyUp(code: 79), .route(first))
    }

    func testPassThroughRouteDoesNotSwallowRepeats() {
        var router = VoicePressRouter()
        let direct = route(.mode0, action: .doubaoPassThrough)
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode0, routes: [direct]), .route(direct))
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: true, mode: .mode0, routes: [direct]), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .route(direct))
    }

    func testCustomF18AndF19ProduceNoAppRoutes() {
        var draft = AhaKeyStudioDraft.legacyAppVoice
        for mode in AhaKeyModeSlot.allCases {
            var item = draft.draft(for: mode)
            var voice = item.key(for: .voice)
            voice.voicePreset = .custom
            voice.shortcut = .init(keyCode: mode.rawValue.isMultiple(of: 2) ? HIDUsage.f18 : HIDUsage.f19)
            item.updateKey(voice); draft.updateMode(item)
        }
        XCTAssertTrue(VoiceRelayService.buildRoutes(from: draft).isEmpty)
    }

    func testFnCompatibilityAliasCannotCaptureCustomModeShortcut() throws {
        var draft = AhaKeyStudioDraft.legacyAppVoice
        var fnMode = draft.draft(for: .mode0), customMode = draft.draft(for: .mode2)
        var fn = fnMode.key(for: .voice), custom = customMode.key(for: .voice)
        fn.voicePreset = .typeless; fn.shortcut = .init(keyCode: HIDUsage.f19)
        custom.voicePreset = .custom; custom.shortcut = .init(keyCode: HIDUsage.f18)
        fnMode.updateKey(fn); draft.updateMode(fnMode)
        customMode.updateKey(custom); draft.updateMode(customMode)
        let routes = VoiceRelayService.buildRoutes(from: draft)
        XCTAssertTrue(routes.contains { $0.mode == .mode0 && $0.binding.keyCode == 79 })
        var router = VoicePressRouter()
        XCTAssertEqual(router.keyDown(code: 79, modifiers: [], isRepeat: false, mode: .mode2, routes: routes), .passThrough)
        XCTAssertEqual(router.keyUp(code: 79), .passThrough)
        let native = try XCTUnwrap(routes.first { $0.mode == .mode1 })
        XCTAssertEqual(router.keyDown(code: native.binding.keyCode, modifiers: native.binding.modifiers, isRepeat: false, mode: .mode1, routes: routes), .route(native))
    }
}
