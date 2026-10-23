import XCTest
import Combine
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioLCDInspectorTests: XCTestCase {
    private let device = "40D918AF-573B-4A54-813C-B3B2FA943B80"
    private func report(_ mode: WS3PresentationMode? = nil, generation: UInt64 = 7) -> WS3TaskOverview {
        .init(connected: true, tasks: [], unrepresentedEvents: 0, requestedMode: mode,
              presentationBusy: false, connectionGeneration: generation, targetedModeWrites: true)
    }
    private func access(read: (() async -> WS3TaskOverview?)? = nil,
                        apply: ((WS3PresentationMode, String, UInt64) async throws -> WS3TaskOverview)? = nil,
                        setFollow: @escaping (Bool) -> Void = { _ in }) -> StudioLCDInspectorModel.Access {
        .init(revision: { 1 }, available: { true }, read: read ?? { self.report() },
              apply: apply ?? { mode, _, _ in self.report(mode) }, followEnabled: { false }, setFollow: setFollow, pause: {})
    }
    private func finish(_ model: StudioLCDInspectorModel) async throws {
        for _ in 0..<1000 {
            if !model.isWriting && !model.isReading { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Inspector did not finish")
    }

    func testRefreshAndDraftSelectionNeverWriteOrEnableFollowing() async throws {
        var writes = 0, following = 0
        let model = StudioLCDInspectorModel()
        let io = access(read: { self.report(.multi) }, apply: { mode, _, _ in writes += 1; return self.report(mode) },
                        setFollow: { _ in following += 1 })
        model.read(using: io); try await finish(model)
        XCTAssertEqual(model.selectedMode, .multi); XCTAssertFalse(model.hasSettingsDraft)
        model.chooseMode(.single); model.chooseFollow(true)
        XCTAssertEqual(writes, 0); XCTAssertEqual(following, 0); XCTAssertTrue(model.hasSettingsDraft)
    }

    func testOneSubmissionWritesArtworkBeforeModeAndFollowsOnlyAfterConfirmation() async throws {
        var events: [String] = [], outcomes: [KeyboardWriteOutcome] = []
        let model = StudioLCDInspectorModel()
        let subscription = model.writeCompleted.sink { outcomes.append($0) }
        defer { subscription.cancel() }
        model.chooseMode(.multi); model.chooseFollow(true)
        let io = access(read: { events.append("fresh"); return self.report() }, apply: { mode, id, generation in
            events.append("mode"); XCTAssertEqual(id, self.device); XCTAssertEqual(generation, 7)
            return self.report(mode)
        }, setFollow: { value in XCTAssertTrue(value); events.append("follow") })
        model.write(artwork: [.init(title: "image1", run: { events.append("image1") }),
                              .init(title: "default2", run: { events.append("default2") })], deviceID: device, using: io)
        try await finish(model)
        XCTAssertEqual(events, ["image1", "default2", "fresh", "mode", "follow"])
        XCTAssertEqual(outcomes.count, 1); XCTAssertTrue(outcomes[0].succeeded)
        XCTAssertFalse(model.hasSettingsDraft)
    }

    func testArtworkFailureStopsRemainingStagesAndRetainsSettingsDraft() async throws {
        var events: [String] = []
        let model = StudioLCDInspectorModel(); model.chooseMode(.multi); model.chooseFollow(true)
        model.write(artwork: [.init(title: "first", run: { events.append("first") }),
            .init(title: "second", run: { throw StudioLCDInspectorModel.Failure.artworkNeedsAttention }),
            .init(title: "third", run: { XCTFail("Must not continue") })], deviceID: device,
            using: access(apply: { _, _, _ in XCTFail("Must not apply display"); throw CancellationError() },
                          setFollow: { _ in XCTFail("Must not enable follow") }))
        try await finish(model)
        XCTAssertEqual(events, ["first"]); XCTAssertTrue(model.hasSettingsDraft)
        XCTAssertTrue(model.message?.contains("first") == true)
    }

    func testModeFailureReportsPartialWriteAndRetryDoesNotRepeatConfirmedArtwork() async throws {
        var imageWrites = 0, outcomes: [KeyboardWriteOutcome] = []
        let model = StudioLCDInspectorModel(); model.chooseMode(.multi)
        let subscription = model.writeCompleted.sink { outcomes.append($0) }; defer { subscription.cancel() }
        model.write(artwork: [.init(title: "image", run: { imageWrites += 1 })], deviceID: device,
                    using: access(apply: { _, _, _ in throw StudioLCDInspectorModel.Failure.changed }))
        try await finish(model)
        XCTAssertFalse(outcomes[0].succeeded); XCTAssertTrue(outcomes[0].message.contains("image"))
        XCTAssertEqual(model.modeDraft, .multi)
        model.write(artwork: [], deviceID: device, using: access()); try await finish(model)
        XCTAssertEqual(imageWrites, 1); XCTAssertTrue(outcomes.last?.succeeded == true)
        XCTAssertNil(model.modeDraft)
    }

    func testGenerationChangeAfterRequestDoesNotConfirmOrClearDraft() async throws {
        let model = StudioLCDInspectorModel(); model.chooseMode(.multi)
        model.write(artwork: [], deviceID: device,
                    using: access(apply: { mode, _, _ in self.report(mode, generation: 8) }))
        try await finish(model)
        XCTAssertEqual(model.modeDraft, .multi); XCTAssertNotNil(model.message)
    }

    func testFollowOnlyChangesHostPreferenceWithoutADeviceRequest() async throws {
        var enabled = false
        let model = StudioLCDInspectorModel(); model.chooseFollow(true)
        model.write(artwork: [], deviceID: nil, using: access(read: { XCTFail(); return nil },
            apply: { _, _, _ in XCTFail(); throw CancellationError() }, setFollow: { enabled = $0 }))
        try await finish(model)
        XCTAssertTrue(enabled); XCTAssertFalse(model.hasSettingsDraft)
    }

    func testOlderBackendIsReadableButCannotSilentlyIgnoreWriteTarget() async throws {
        let model = StudioLCDInspectorModel()
        let old = WS3TaskOverview(connected: true, tasks: [], unrepresentedEvents: 0,
            presentationBusy: false, connectionGeneration: 7)
        let io = access(read: { old }, apply: { _, _, _ in XCTFail("Old backend must not receive a targeted write"); throw CancellationError() })
        model.read(using: io); try await finish(model)
        XCTAssertNotNil(model.overview)
        model.chooseMode(.multi)
        model.write(artwork: [], deviceID: device, using: io); try await finish(model)
        XCTAssertEqual(model.modeDraft, .multi)
        XCTAssertTrue(model.message?.contains(NSLocalizedString("请更新并重启后台后重试。", comment: "")) == true)
    }

    func testCanceledArtworkNeverAppliesModeOrDropsDraft() async throws {
        let model = StudioLCDInspectorModel(); model.chooseMode(.single)
        model.write(artwork: [.init(title: "image", run: { throw CancellationError() })], deviceID: device,
                    using: access(apply: { _, _, _ in XCTFail(); throw CancellationError() }))
        try await finish(model); XCTAssertEqual(model.modeDraft, .single)
    }

    func testScopeIncludesCurrentModeAndSharedArtworkButPreservesOtherModes() {
        XCTAssertEqual(StudioResourceInspectorModel.pendingEntries(mode: 2, dirty: [0, 7, 8, 9, 12, 16, 18, 19]), [8, 9, 16, 18])
        XCTAssertTrue(StudioResourceInspectorModel.pendingEntries(mode: -1, dirty: [0, 16]).isEmpty)
    }

    func testTargetProofRejectsWrongDeviceOldGenerationAndMalformedFields() {
        let id = UUID(uuidString: device)!
        XCTAssertTrue(WS3PresentationRequestTarget.matches([:], deviceID: nil, generation: 7))
        XCTAssertTrue(WS3PresentationRequestTarget.matches(["deviceID": device, "generation": 7], deviceID: id, generation: 7))
        for fields: [String: Any] in [["deviceID": UUID().uuidString, "generation": 7],
            ["deviceID": device, "generation": 6], ["deviceID": device, "generation": true],
            ["deviceID": device, "generation": "7"], ["deviceID": device], ["generation": 7]] {
            XCTAssertFalse(WS3PresentationRequestTarget.matches(fields, deviceID: id, generation: 7))
        }
    }
}
