import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class StudioK1VoiceTests: XCTestCase {
    private var config: StudioVoiceConfiguration { .init(draft: .legacyAppVoice, fallback: .legacy()) }
    private var consumer: K1OutputRoute { K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))! }
    private var ordinary: K1OutputRoute { K1OutputRoute(kind: .ordinary, action: Data([0x73, 1, HIDUsage.f18]))! }
    private func key(consumer: Bool = true, description: String = "Record") -> AhaKeyKeyDraft {
        var key = config.key(for: .mode2); key.voicePreset = consumer ? .systemDictation : .macOSNative
        key.shortcut = VoicePreset.macOSNative.defaultBinding; key.description = description; return key
    }
    private func fact(_ route: K1OutputRoute, description: String = "Record") -> StudioInlineKeyFact {
        .init(deviceID: "A", value: StudioK1VoiceProposal.projection(route, mode: 2, description: Data(description.utf8)), k1Route: route)
    }
    @MainActor private func session(release: @escaping () -> Void = {}) -> StudioInspectorSession {
        .init(access: .init(begin: { 1 }, isCurrent: { $0 == 1 }, isReady: { true }, generation: { 7 }, deviceID: { "A" }, release: { _ in release() }, pause: {}))
    }
    func testConsumerIsNotMisrepresentedAsOrdinaryF18AndOnlyOneHostModeChanges() throws {
        let original = config, selected = key()
        let projection = fact(consumer).value
        XCTAssertEqual(projection.actionType, 0); XCTAssertTrue(projection.action.isEmpty)
        XCTAssertEqual(try StudioK1VoiceProposal.route(for: selected), consumer)
        let applied = try original.committingK1(key: selected, mode: .mode2, route: consumer, actual: projection)
        XCTAssertEqual(applied.key(for: .mode2).voicePreset, .systemDictation)
        for mode in [AhaKeyModeSlot.mode0, .mode1, .mode3] { XCTAssertEqual(applied.key(for: mode), original.key(for: mode)) }
        XCTAssertEqual(VoiceRelayService.buildRoutes(from: applied.routeDraft), VoiceRelayService.buildRoutes(from: original.routeDraft).filter { $0.mode != .mode2 })
        XCTAssertThrowsError(try original.committingK1(key: selected, mode: .mode2, route: ordinary, actual: projection))
    }
    func testReadingConsumerAndDisabledRoutesDoesNotRequireInventedOrdinaryAction() throws {
        XCTAssertEqual(StudioK1VoiceProposal.importing(route: consumer, actual: fact(consumer).value,
            configuration: config, preserving: key(consumer: false))?.voicePreset, .systemDictation)
        let disabled = K1OutputRoute(kind: .ordinary, action: Data())!
        let imported = try XCTUnwrap(StudioK1VoiceProposal.importing(route: disabled, actual: fact(disabled).value,
            configuration: config, preserving: key()))
        XCTAssertEqual(imported.voicePreset, .custom); XCTAssertTrue(imported.shortcut.hidCodes.isEmpty)
        let unknown = K1OutputRoute(kind: .consumer, action: Data([0x9D, 2]))!
        XCTAssertNil(StudioK1VoiceProposal.importing(route: unknown, actual: fact(unknown).value, configuration: config, preserving: key()))
    }
    func testConsumerRoundTripCanReturnToAppAndCustomShortcut() throws {
        XCTAssertEqual(try StudioK1VoiceProposal.route(for: key(consumer: false)), ordinary)
        var custom = key(); custom.voicePreset = .custom
        custom.shortcut = .init(modifiers: [.command], keyCode: HIDUsage.space)
        let route = try StudioK1VoiceProposal.route(for: custom)
        XCTAssertEqual(route.kind, .ordinary)
        let applied = try config.committingK1(key: custom, mode: .mode2, route: route, actual: StudioK1VoiceProposal.projection(route, mode: 2, description: Data("Record".utf8)))
        XCTAssertEqual(applied.key(for: .mode2), custom)
        XCTAssertFalse(VoiceRelayService.buildRoutes(from: applied.routeDraft).contains { $0.mode == .mode2 })
    }
    func testOrdinaryF18NeverInheritsConsumerFromTheHostPlaceholderShortcut() throws {
        let applied = try config.committingK1(key: key(), mode: .mode2, route: consumer, actual: fact(consumer).value)
        let imported = try XCTUnwrap(StudioK1VoiceProposal.importing(route: ordinary, actual: fact(ordinary).value,
            configuration: applied, preserving: key()))
        XCTAssertEqual(imported.voicePreset, .custom)
        XCTAssertEqual(imported.shortcut, VoicePreset.macOSNative.defaultBinding)
    }
    @MainActor
    func testRouteRecoveryUsesOneComponentAndReleasesConnection() async throws {
        let before = fact(ordinary); var actual = before; var events: [String] = []
        let result = try await StudioK1VoiceSave.run(session: session { events.append("release") }, baseline: before,
            key: key(), configuration: config, read: { mode in XCTAssertEqual(mode, 2); events.append("read"); return actual },
            saveDescription: { _, _, _ in XCTFail("Description unchanged") }, saveRoute: { baseline, desired, generation in
                XCTAssertEqual(generation, 7); XCTAssertEqual(baseline, self.ordinary); XCTAssertEqual(desired, self.consumer)
                events.append("route"); actual = self.fact(desired)
            }, checkHostReady: {}, prepareHost: { events.append("host") }, writeStarted: {})
        guard case .saved(let confirmed) = result else { return XCTFail() }
        XCTAssertEqual(confirmed.k1Route, consumer)
        XCTAssertEqual(events, ["read", "host", "route", "read", "release"])
    }
    @MainActor
    func testRouteOnlyConflictIsDetectedEvenWhenOrdinaryProjectionIsIdentical() async throws {
        let disabled = K1OutputRoute(kind: .ordinary, action: Data())!
        XCTAssertEqual(fact(disabled).value, fact(consumer).value)
        let result = try await StudioK1VoiceSave.run(session: session(), baseline: fact(consumer), key: key(), configuration: config,
            read: { _ in self.fact(disabled) }, saveDescription: { _, _, _ in XCTFail() }, saveRoute: { _, _, _ in XCTFail() },
            checkHostReady: { XCTFail() }, prepareHost: { XCTFail() }, writeStarted: { XCTFail() })
        guard case .conflict(let conflict) = result else { return XCTFail() }
        XCTAssertEqual(conflict.k1Route, disabled); XCTAssertEqual(conflict.desiredK1Route, consumer)
    }
    @MainActor
    func testConsumerDescriptionSaveDoesNotExitConsumerOrWriteARoute() async throws {
        let before = fact(consumer); var actual = before
        let result = try await StudioK1VoiceSave.run(session: session(), baseline: before, key: key(description: "Dictation"), configuration: config,
            read: { _ in actual }, saveDescription: { value, description, generation in
                XCTAssertEqual(value, before.value); XCTAssertEqual(generation, 7)
                actual = self.fact(self.consumer, description: String(decoding: description, as: UTF8.self))
            }, saveRoute: { _, _, _ in XCTFail() }, checkHostReady: {}, prepareHost: {}, writeStarted: {})
        guard case .saved(let confirmed) = result else { return XCTFail() }
        XCTAssertEqual(confirmed.k1Route, consumer); XCTAssertEqual(confirmed.value.description, Data("Dictation".utf8))
    }
    @MainActor
    func testUnchangedRouteAndDescriptionOnlyPrepareTheHost() async throws {
        var prepared = false
        let result = try await StudioK1VoiceSave.run(session: session(), baseline: fact(consumer), key: key(), configuration: config,
            read: { _ in self.fact(self.consumer) }, saveDescription: { _, _, _ in XCTFail() }, saveRoute: { _, _, _ in XCTFail() },
            checkHostReady: {}, prepareHost: { prepared = true }, writeStarted: { XCTFail() })
        guard case .unchanged = result else { return XCTFail() }; XCTAssertTrue(prepared)
    }
    @MainActor
    func testDescriptionFailureStopsBeforeHostPreparationOrRouteChange() async {
        enum Failed: Error { case storage }
        var released = false, started = false
        do {
            _ = try await StudioK1VoiceSave.run(session: session { released = true }, baseline: fact(ordinary), key: key(description: "New"), configuration: config,
                read: { _ in self.fact(self.ordinary) }, saveDescription: { _, _, _ in throw Failed.storage }, saveRoute: { _, _, _ in XCTFail() },
                checkHostReady: {}, prepareHost: { XCTFail() }, writeStarted: { started = true })
            XCTFail()
        } catch { XCTAssertTrue(error is Failed) }
        XCTAssertTrue(released); XCTAssertTrue(started)
    }
    @MainActor
    func testConfirmationCannotBypassAnotherRouteChange() async throws {
        let first = fact(ordinary)
        let changed = fact(consumer)
        for (baseline, actual) in [(first, changed), (changed, first)] {
            let result = try await StudioK1VoiceSave.run(session: session(), baseline: baseline, key: key(), configuration: config,
                read: { _ in actual }, saveDescription: { _, _, _ in XCTFail() }, saveRoute: { _, _, _ in XCTFail() },
                checkHostReady: { XCTFail() }, prepareHost: { XCTFail() }, writeStarted: { XCTFail() })
            guard case .conflict(let conflict) = result else { return XCTFail() }
            XCTAssertEqual(conflict.k1Route, actual.k1Route)
        }
    }
    @MainActor
    func testGenerationChangeAfterDescriptionWriteCannotPrepareHostOrWriteRoute() async {
        var generation: UInt64 = 7, released = false
        let host = StudioInspectorSession(access: .init(begin: { 1 }, isCurrent: { $0 == 1 }, isReady: { true },
            generation: { generation }, deviceID: { "A" }, release: { _ in released = true }, pause: {}))
        do {
            _ = try await StudioK1VoiceSave.run(session: host, baseline: fact(ordinary), key: key(description: "Changed"), configuration: config,
                read: { _ in self.fact(self.ordinary) }, saveDescription: { _, _, _ in generation = 8 }, saveRoute: { _, _, _ in XCTFail() },
                checkHostReady: {}, prepareHost: { XCTFail() }, writeStarted: {})
            XCTFail()
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .sessionChanged) }
        XCTAssertTrue(released)
    }
    @MainActor
    func testWrongDeviceFactCannotBecomeAConflictOrAuthorizeAWrite() async {
        var foreign = fact(ordinary); foreign = .init(deviceID: "B", value: foreign.value, k1Route: foreign.k1Route)
        do {
            _ = try await StudioK1VoiceSave.run(session: session(), baseline: fact(ordinary), key: key(), configuration: config,
                read: { _ in foreign }, saveDescription: { _, _, _ in XCTFail() }, saveRoute: { _, _, _ in XCTFail() },
                checkHostReady: { XCTFail() }, prepareHost: { XCTFail() }, writeStarted: { XCTFail() })
            XCTFail()
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .deviceChanged) }
    }
}
