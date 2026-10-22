import XCTest
@testable import AhaKeyConfig

final class VoiceProcessingPolicyTests: XCTestCase {
    private let native = VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false, longPressThresholdMs: 500)
    private let mixed = VoiceProcessingPolicy(shortPressAhaType: true, longPressAhaType: false, longPressThresholdMs: 700)

    func testOldKeyWithoutPolicyRetainsLegacyFallback() throws {
        let key = AhaKeyModeDraft.default(for: .mode0).key(for: .voice)
        let data = try JSONEncoder().encode(key)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["voiceProcessingPolicy"])
        XCTAssertNil(try JSONDecoder().decode(AhaKeyKeyDraft.self, from: data).voiceProcessingPolicy)
    }

    func testPerModePoliciesRoundTripAndAliasesKeepTheirOwnPolicy() throws {
        var draft = AhaKeyStudioDraft.default
        for (slot, policy) in [(AhaKeyModeSlot.mode0, native), (.mode2, mixed)] {
            var mode = draft.draft(for: slot)
            var key = mode.key(for: .voice)
            key.voicePreset = .macOSNative
            key.shortcut = ShortcutBinding(keyCode: HIDUsage.f19)
            key.voiceProcessingPolicy = policy
            mode.updateKey(key); draft.updateMode(mode)
        }
        let restored = try JSONDecoder().decode(AhaKeyStudioDraft.self, from: JSONEncoder().encode(draft))
        let routes = VoiceRelayService.buildRoutes(from: restored)
        let first = routes.filter { $0.mode == .mode0 }
        XCTAssertEqual(first.count, 2)
        XCTAssertTrue(first.allSatisfy { $0.processingPolicy == native })
        XCTAssertEqual(routes.first { $0.mode == .mode2 }?.processingPolicy, mixed)
        XCTAssertNil(routes.first { $0.mode == .mode1 }?.processingPolicy)
    }

    func testPressCapturesProcessingBeforeModeAndConfigurationChange() throws {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode2)
        var key = mode.key(for: .voice)
        key.voicePreset = .macOSNative
        key.shortcut = ShortcutBinding(keyCode: HIDUsage.f18)
        key.voiceProcessingPolicy = mixed
        mode.updateKey(key); draft.updateMode(mode)
        var router = VoicePressRouter()
        guard case .route(let down) = router.keyDown(code: 79, modifiers: [], isRepeat: false,
                mode: .mode2, routes: VoiceRelayService.buildRoutes(from: draft)) else { return XCTFail("missing route") }
        key.voiceProcessingPolicy = native
        mode.updateKey(key); draft.updateMode(mode)
        XCTAssertEqual(down.processingPolicy, mixed)
        XCTAssertEqual(router.keyUp(code: 79), .route(down))
    }

    func testShortAndLongPressUseTheirCapturedPolicy() {
        let short = VoiceRecordingPolicySnapshot(policy: mixed, gesture: .shortPress, ahaTypeEnabledAtStart: true)
        let long = VoiceRecordingPolicySnapshot(policy: mixed, gesture: .longPress, ahaTypeEnabledAtStart: true)
        XCTAssertTrue(short.usesAhaType)
        XCTAssertFalse(long.usesAhaType)
        XCTAssertFalse(VoiceRecordingPolicySnapshot(policy: mixed, gesture: .shortPress,
            ahaTypeEnabledAtStart: false).usesAhaType)
    }

    func testChangingSourceSettingsCannotEnableCloudForStartedDirectRecording() {
        var policy = native
        let direct = VoiceRecordingPolicySnapshot(policy: policy, gesture: .shortPress, ahaTypeEnabledAtStart: true)
        policy.shortPressAhaType = true
        XCTAssertFalse(direct.usesAhaType)
        let next = VoiceRecordingPolicySnapshot(policy: policy, gesture: .shortPress, ahaTypeEnabledAtStart: true)
        policy.shortPressAhaType = false
        XCTAssertTrue(next.usesAhaType)
    }

    func testThresholdBoundsUnsafePersistedValues() {
        XCTAssertEqual(VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false,
            longPressThresholdMs: Int.min).thresholdSeconds, 0.2)
        XCTAssertEqual(VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false,
            longPressThresholdMs: Int.max).thresholdSeconds, 2.0)
    }
}
