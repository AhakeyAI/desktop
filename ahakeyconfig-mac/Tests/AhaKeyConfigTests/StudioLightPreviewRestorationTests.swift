import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioLightPreviewRestorationTests: XCTestCase {
    private func report(_ mode: WS3PresentationMode?, generation: UInt64 = 2) -> WS3TaskOverview {
        .init(connected: true, tasks: [], unrepresentedEvents: 0, requestedMode: mode,
            presentationBusy: false, connectionGeneration: generation, targetedModeWrites: true)
    }
    private func access(current: WS3PresentationMode? = nil,
                        restore: @escaping (WS3PresentationMode, String, UInt64) async throws -> WS3TaskOverview) -> StudioLCDInspectorModel.Access {
        .init(revision: { 1 }, available: { true }, read: { self.report(current) },
            apply: { _, _, _ in XCTFail("Recovery must never use an unconditional write"); throw WS3PresentationError.rejected },
            followEnabled: { false }, setFollow: { _ in XCTFail() }, pause: {}, restore: restore)
    }
    func testRestoresMultiWithFreshConnectionProofAfterHandoff() async throws {
        var writes = 0
        try await StudioLightPreviewRestoration.run(mode: .multi, deviceID: "A", access: access { mode, target, generation in
            XCTAssertEqual(mode, .multi); XCTAssertEqual(target, "A"); XCTAssertEqual(generation, 2)
            writes += 1; return self.report(mode)
        })
        XCTAssertEqual(writes, 1)
    }
    func testNewChoiceAlreadyPresentIsKeptWithoutWriting() async throws {
        try await StudioLightPreviewRestoration.run(mode: .multi, deviceID: "A", access: access(current: .single) { _, _, _ in
            XCTFail("New explicit choice must win"); return self.report(.multi)
        })
    }
    func testChoiceRacingReadAndRestoreIsKeptByConditionalBackend() async throws {
        try await StudioLightPreviewRestoration.run(mode: .multi, deviceID: "A", access: access { _, _, _ in
            self.report(.single)
        })
    }
    func testUnknownOriginalModeDoesNotInventAPersistentChoice() async throws {
        try await StudioLightPreviewRestoration.run(mode: nil, deviceID: "A", access: access { _, _, _ in
            XCTFail(); return self.report(.single)
        })
    }
    func testBackendWithoutConditionalRestoreCannotUseUnconditionalFallback() async {
        var legacy = access { _, _, _ in XCTFail(); return self.report(.multi) }
        legacy.restore = nil
        do {
            try await StudioLightPreviewRestoration.run(mode: .multi, deviceID: "A", access: legacy)
            XCTFail("Old backend must not receive an unconditional restore")
        } catch { XCTAssertEqual(error as? StudioLCDInspectorModel.Failure, .oldBackend) }
    }

    func testChangedConnectionNeverReportsSuccessfulRecovery() async {
        do {
            try await StudioLightPreviewRestoration.run(mode: .multi, deviceID: "A", access: access { _, _, _ in
                self.report(.multi, generation: 3)
            })
            XCTFail("Stale generation")
        } catch { XCTAssertEqual(error as? WS3PresentationError, .connectionChanged) }
    }
}
