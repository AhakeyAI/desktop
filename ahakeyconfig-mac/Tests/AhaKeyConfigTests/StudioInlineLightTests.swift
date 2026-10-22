import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioInlineLightTests: XCTestCase {
    private let target = StudioLightDrafts.Target.effect(mode: 2, state: 7)
    private let baseline = StudioLightDrafts.Fact(deviceID: "keyboard-A", value: 10)

    private func session(generation: @escaping () -> UInt64 = { 4 }, release: @escaping () -> Void = {}) -> StudioInspectorSession {
        .init(access: .init(begin: { 1 }, isCurrent: { $0 == 1 }, isReady: { true }, generation: generation,
                            deviceID: { "keyboard-A" }, release: { _ in release() }, pause: {}))
    }

    func testSaveUsesOnlySelectedSettingAndCurrentLeaseThenReleases() async throws {
        var releases = 0, writes = 0, started = 0
        let host = session { releases += 1 }
        let result = try await StudioInlineLightOperation.run(target: target, action: .save(baseline: baseline, desired: 3), session: host,
            expectedDeviceID: "keyboard-A", read: { selected, context in
                XCTAssertEqual(selected, self.target); XCTAssertEqual(context.generation, 4)
                return .init(selected: self.baseline, brightness: 35)
            }, save: { setting, actual, generation in
                XCTAssertEqual(setting, .singleLight(mode: 2, state: 7, effect: 3))
                XCTAssertEqual(actual, 10); XCTAssertEqual(generation, 4); writes += 1
            }, preview: { _ in XCTFail("Save cannot preview") }, writeStarted: { started += 1 })
        guard case .saved(let reading, let wrote) = result else { return XCTFail("Expected saved") }
        XCTAssertTrue(wrote); XCTAssertEqual(reading.selected.value, 3)
        XCTAssertEqual(writes, 1); XCTAssertEqual(started, 1); XCTAssertEqual(releases, 1); XCTAssertFalse(host.isBusy)
    }

    func testConflictConfirmationRechecksNewDeviceValueAgain() async throws {
        var releases = 0
        let host = session { releases += 1 }
        for value: UInt8 in [3, 4] {
            let result = try await StudioInlineLightOperation.run(target: target,
                action: .save(baseline: value == 3 ? baseline : .init(deviceID: "keyboard-A", value: 3), desired: 1),
                session: host, expectedDeviceID: "keyboard-A", read: { _, _ in
                    .init(selected: .init(deviceID: "keyboard-A", value: value), brightness: 35)
                }, save: { _, _, _ in XCTFail("Conflict cannot write") }, preview: { _ in XCTFail() }, writeStarted: { XCTFail() })
            guard case .conflict(let reading, let desired) = result else { return XCTFail("Expected renewed conflict") }
            XCTAssertEqual(reading.selected.value, value); XCTAssertEqual(desired, 1)
        }
        XCTAssertEqual(releases, 2)
    }

    func testFailedPersistenceReadThenRetryActuallyWritesBeforeClearingUncertainty() async throws {
        var values = StudioLightDrafts()
        values.observe(target, fact: baseline); values.edit(target, value: 3); values.markUnconfirmed(target)
        values.observe(target, fact: .init(deviceID: "keyboard-A", value: 3))
        XCTAssertTrue(values.unconfirmed.contains(target))
        let action = try XCTUnwrap(StudioInlineLightOperation.saving(target: target, values: values))
        var writes = 0
        let result = try await StudioInlineLightOperation.run(target: target, action: action, session: session(),
            expectedDeviceID: "keyboard-A", read: { _, _ in .init(selected: .init(deviceID: "keyboard-A", value: 3), brightness: 35) },
            save: { setting, _, _ in XCTAssertEqual(setting, .singleLight(mode: 2, state: 7, effect: 3)); writes += 1 },
            preview: { _ in XCTFail() }, writeStarted: {})
        guard case .saved(let reading, let wrote) = result else { return XCTFail() }
        XCTAssertTrue(wrote); XCTAssertEqual(writes, 1)
        values.confirm(target, fact: reading.selected)
        XCTAssertFalse(values.unconfirmed.contains(target))
    }

    func testLateReceiptRetainsCapturedModeAndState() {
        let originalScope = StudioLightInspectorModel.scopeTitle(target)
        let message = StudioLightInspectorModel.receipt(scope: originalScope, text: "saved")
        XCTAssertTrue(message.contains(originalScope))
        XCTAssertNotEqual(originalScope, StudioLightInspectorModel.scopeTitle(.effect(mode: 3, state: 7)))
        XCTAssertNotEqual(originalScope, StudioLightInspectorModel.scopeTitle(.effect(mode: 2, state: 1)))
    }

    func testPreviewOfCachedSelectionSurvivesExternallyChangedReadback() {
        var values = StudioLightDrafts()
        values.observe(target, fact: baseline)
        values.observe(.brightness, fact: .init(deviceID: "keyboard-A", value: 35))
        // The user explicitly previews 10 at brightness 35. Another client has
        // meanwhile changed persisted values to effect 3 and brightness 40.
        values.observePreview(target: target, selected: .init(deviceID: "keyboard-A", value: 3),
                              brightness: 40, request: .light(effect: 10, brightness: 35))
        XCTAssertEqual(values.facts[target]?.value, 3)
        XCTAssertEqual(values.facts[.brightness]?.value, 40)
        XCTAssertEqual(values.drafts[target], 10)
        XCTAssertEqual(values.drafts[.brightness], 35)
        XCTAssertEqual(values.dirtyTargets, [target, .brightness])
        values.observePreview(target: target, selected: .init(deviceID: "keyboard-A", value: 3), brightness: 40, request: .stop)
        XCTAssertEqual(values.drafts[target], 10)
        values.observePreview(target: target, selected: .init(deviceID: "keyboard-A", value: 255), brightness: 40, request: .light(effect: 10, brightness: 35))
        XCTAssertEqual(values.drafts[target], 10)
        XCTAssertNil(StudioInlineLightOperation.saving(target: target, values: values))
    }

    func testUnknownActualValueStaysReadOnlyInsteadOfOfferingOverride() async throws {
        let result = try await StudioInlineLightOperation.run(target: target, action: .save(baseline: baseline, desired: 3), session: session(),
            expectedDeviceID: "keyboard-A", read: { _, _ in .init(selected: .init(deviceID: "keyboard-A", value: 255), brightness: 35) },
            save: { _, _, _ in XCTFail() }, preview: { _ in XCTFail() }, writeStarted: { XCTFail() })
        guard case .readOnly(let reading) = result else { return XCTFail("Unknown effect must be read-only") }
        XCTAssertEqual(reading.selected.value, 255)
    }

    func testSameValueNeverWritesFlash() async throws {
        let result = try await StudioInlineLightOperation.run(target: .brightness,
            action: .save(baseline: .init(deviceID: "keyboard-A", value: 35), desired: 35), session: session(),
            expectedDeviceID: "keyboard-A", read: { _, _ in .init(selected: .init(deviceID: "keyboard-A", value: 35), brightness: 35) },
            save: { _, _, _ in XCTFail("No redundant EEPROM write") }, preview: { _ in XCTFail() }, writeStarted: { XCTFail() })
        guard case .saved(_, let wrote) = result else { return XCTFail() }
        XCTAssertFalse(wrote)
    }

    func testGenerationChangeCannotPublishConfirmedResult() async throws {
        var generation: UInt64 = 4, releases = 0, attempted = false
        let host = session(generation: { generation }, release: { releases += 1 })
        do {
            _ = try await StudioInlineLightOperation.run(target: target, action: .save(baseline: baseline, desired: 3), session: host,
                expectedDeviceID: "keyboard-A", read: { _, _ in .init(selected: self.baseline, brightness: 35) },
                save: { _, _, _ in generation = 5 }, preview: { _ in XCTFail() }, writeStarted: { attempted = true })
            XCTFail("Stale generation must throw before caller confirms")
        } catch { XCTAssertEqual(error as? StudioInspectorSession.Failure, .sessionChanged) }
        XCTAssertTrue(attempted); XCTAssertEqual(releases, 1)
    }

    func testPreviewOnlyIssuesRequestedPreviewAndReleases() async throws {
        var previews = 0, releases = 0
        _ = try await StudioInlineLightOperation.run(target: target, action: .preview(.stop), session: session { releases += 1 },
            expectedDeviceID: "keyboard-A", read: { _, _ in .init(selected: .init(deviceID: "keyboard-A", value: 255), brightness: 35) },
            save: { _, _, _ in XCTFail() }, preview: { XCTAssertEqual($0, .stop); previews += 1 }, writeStarted: { XCTFail() })
        XCTAssertEqual(previews, 1); XCTAssertEqual(releases, 1)
    }

    func testInterruptedSaveMarksUnconfirmedAndStillReleases() async throws {
        var pending = false, releases = 0
        do {
            _ = try await StudioInlineLightOperation.run(target: target, action: .save(baseline: baseline, desired: 3),
                session: session { releases += 1 }, expectedDeviceID: "keyboard-A",
                read: { _, _ in .init(selected: self.baseline, brightness: 35) },
                save: { _, _, _ in throw CancellationError() }, preview: { _ in XCTFail() }, writeStarted: { pending = true })
            XCTFail()
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(pending); XCTAssertEqual(releases, 1)
    }

    func testRefreshAndSavePreserveOtherModeAndBrightnessDrafts() {
        var values = StudioLightDrafts()
        let other = StudioLightDrafts.Target.effect(mode: 1, state: 7)
        values.observe(target, fact: baseline); values.observe(other, fact: baseline)
        values.observe(.brightness, fact: .init(deviceID: "keyboard-A", value: 35))
        values.edit(target, value: 3); values.edit(other, value: 4); values.edit(.brightness, value: 50)
        values.observe(target, fact: .init(deviceID: "keyboard-A", value: 5))
        XCTAssertEqual(values.drafts[target], 3)
        values.confirm(target, fact: .init(deviceID: "keyboard-A", value: 3))
        XCTAssertEqual(values.drafts[other], 4); XCTAssertEqual(values.drafts[.brightness], 50)
        XCTAssertEqual(values.dirtyTargets, [other, .brightness])
    }

    func testUnknownReadbackCannotBeEditedAndReadDoesNotClearUncertainty() {
        var values = StudioLightDrafts()
        values.observe(target, fact: .init(deviceID: "keyboard-A", value: 255))
        values.edit(target, value: 3); XCTAssertEqual(values.drafts[target], 255)
        values.markUnconfirmed(target)
        values.observe(target, fact: baseline)
        XCTAssertTrue(values.unconfirmed.contains(target))
    }

    func testDraftAndUnconfirmedStateSurviveModelRestart() throws {
        let suite = "StudioInlineLightTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = StudioLightInspectorModel(defaults: defaults)
        first.values.observe(target, fact: baseline); first.values.edit(target, value: 3); first.values.markUnconfirmed(target)
        let second = StudioLightInspectorModel(defaults: defaults)
        XCTAssertEqual(second.values.facts[target], baseline)
        XCTAssertEqual(second.values.drafts[target], 3)
        XCTAssertTrue(second.values.unconfirmed.contains(target))
    }
}
