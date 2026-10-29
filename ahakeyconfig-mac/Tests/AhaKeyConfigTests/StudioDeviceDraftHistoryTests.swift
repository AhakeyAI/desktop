import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioDeviceDraftHistoryTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "StudioDeviceDraftHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    private var factory: [SideSwitchReadback.Position] {
        [.init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())]
    }
    func testRelaunchPreservesDirtyDraftButCannotWriteFromHistoricalFact() {
        let defaults = defaults(), first = StudioDeviceInspectorModel(defaults: defaults)
        first.observeStandby(.init(deviceID: "A", value: 60))
        first.standbyDraft = 30
        first.observeLever(.init(deviceID: "A", value: factory))
        first.leverDraft?.set(.init(bindType: 2, action: Data()), at: 1)
        let next = StudioDeviceInspectorModel(defaults: defaults)
        XCTAssertEqual(next.standbyDraft, 30)
        XCTAssertEqual(next.leverDraft?.positions[1].bindType, 2)
        XCTAssertNil(next.standbyFact); XCTAssertNil(next.leverFact)
        XCTAssertFalse(next.canWriteLever)
        next.observeStandby(.init(deviceID: "A", value: 120))
        next.observeLever(.init(deviceID: "A", value: factory))
        XCTAssertEqual(next.standbyDraft, 30)
        XCTAssertEqual(next.leverDraft?.positions[1].bindType, 2)
        XCTAssertEqual(next.standbyFact?.value, 120)
    }
    func testPreviouslyCleanDraftFollowsNewDeviceReadback() {
        let defaults = defaults(), first = StudioDeviceInspectorModel(defaults: defaults)
        first.observeStandby(.init(deviceID: "A", value: 60))
        let next = StudioDeviceInspectorModel(defaults: defaults)
        XCTAssertTrue(next.standbyDirty, "historical fact alone cannot claim synchronization")
        next.observeStandby(.init(deviceID: "A", value: 120))
        XCTAssertEqual(next.standbyDraft, 120)
        XCTAssertFalse(next.standbyDirty)
    }
    func testDraftWithoutBaselineIsPreservedUntilExplicitChoice() {
        let defaults = defaults()
        var history = StudioDeviceDraftHistory()
        history.save(.init(standby: 30), deviceID: "A"); history.persist(to: defaults)
        let model = StudioDeviceInspectorModel(defaults: defaults)
        model.observeStandby(.init(deviceID: "A", value: 60))
        XCTAssertEqual(model.standbyDraft, 30)
        XCTAssertTrue(model.standbyDirty)
    }
    func testDeviceSwitchSeparatesDraftsAndRevokesOtherComponentFacts() {
        let model = StudioDeviceInspectorModel(defaults: defaults())
        model.observeStandby(.init(deviceID: "A", value: 60)); model.standbyDraft = 30
        model.observeLever(.init(deviceID: "A", value: factory))
        model.observeStandby(.init(deviceID: "B", value: 120))
        XCTAssertEqual(model.standbyDraft, 120); XCTAssertNil(model.leverFact)
        model.observeStandby(.init(deviceID: "A", value: 60))
        XCTAssertEqual(model.standbyDraft, 30)
    }
    func testWholeDeviceResetInvalidatesFactsButKeepsDraftsAndHistory() {
        let store = defaults(), model = StudioDeviceInspectorModel(defaults: store)
        model.observeStandby(.init(deviceID: "A", value: 60))
        model.standbyDraft = 30
        model.observeLever(.init(deviceID: "A", value: factory))
        model.leverDraft?.set(.init(bindType: 2, action: Data()), at: 1)
        model.invalidateReadbacks()
        XCTAssertNil(model.standbyFact)
        XCTAssertNil(model.leverFact)
        XCTAssertFalse(model.canWriteLever)
        XCTAssertEqual(model.standbyDraft, 30)
        XCTAssertEqual(model.leverDraft?.positions[1].bindType, 2)
        let reloaded = StudioDeviceInspectorModel(defaults: store)
        XCTAssertEqual(reloaded.standbyDraft, 30)
        XCTAssertEqual(reloaded.leverDraft?.positions[1].bindType, 2)
        model.observeStandby(.init(deviceID: "A", value: 60))
        model.observeLever(.init(deviceID: "A", value: factory))
        XCTAssertEqual(model.standbyDraft, 30)
        XCTAssertEqual(model.leverDraft?.positions[1].bindType, 2)
    }

    func testExplicitPeerChoiceSurvivesRelaunch() {
        let defaults = defaults(), model = StudioDeviceInspectorModel(defaults: defaults)
        model.observeLever(.init(deviceID: "A", value: factory))
        model.leverDraft?.set(factory[1], at: 1)
        let next = StudioDeviceInspectorModel(defaults: defaults)
        next.observeLever(.init(deviceID: "A", value: factory))
        next.leverDraft?.set(.init(bindType: 3, action: Data([0x73, 1, 4])), at: 0)
        XCTAssertEqual(next.leverDraft?.positions[1].bindType, 1,
            "the user's explicit factory peer choice must survive a same-value refresh")
    }

    func testUnconfirmedMarkerSurvivesReadAndRelaunch() {
        let defaults = defaults()
        var history = StudioDeviceDraftHistory()
        history.save(.init(standby: 30, standbyBaseline: 30, unconfirmedStandby: true), deviceID: "A")
        history.persist(to: defaults)
        let model = StudioDeviceInspectorModel(defaults: defaults)
        XCTAssertTrue(model.unconfirmed.contains(.standby))
        model.observeStandby(.init(deviceID: "A", value: 30))
        XCTAssertTrue(model.unconfirmed.contains(.standby))
    }
}
