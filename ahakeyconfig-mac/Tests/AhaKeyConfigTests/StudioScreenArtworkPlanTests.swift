import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioScreenArtworkPlanTests: XCTestCase {
    private func payload(_ entry: UInt8, count: Int) throws -> WS3ResourcePayload {
        try .init(entryID: entry, frames: (0..<count).map { Data(repeating: UInt8($0), count: 25_600) })
    }
    func testEachScopeHasExactlyThreeVisibleStatesAndNoIdleCard() {
        for mode in 0..<4 {
            XCTAssertEqual(StudioScreenArtworkPlan.entries(mode: mode, presentation: .single), (1...3).map { UInt8(mode * 4 + $0) })
            XCTAssertEqual(StudioScreenArtworkPlan.entries(mode: mode, presentation: .multi), [16,17,18])
        }
        XCTAssertTrue(StudioScreenArtworkPlan.entries(mode: -1, presentation: .single).isEmpty)
    }
    func testSelectedPresentationOnlySubmitsItsOwnArtworkWithIdleLast() {
        let dirty: Set<UInt8> = [0,8,9,10,11,12,16,17,18]
        XCTAssertEqual(StudioScreenArtworkPlan.pending(mode: 2, presentation: .single, dirty: dirty), [9,10,11,8])
        XCTAssertEqual(StudioScreenArtworkPlan.pending(mode: 2, presentation: .multi, dirty: dirty), [16,17,18])
    }
    func testCompletedAnimationAutomaticallyFitsEightFrameIdleSlot() throws {
        let completed = try payload(11, count: 12)
        let idle = try StudioScreenArtworkPlan.fallback(completed)
        XCTAssertEqual(idle.entryID, 8); XCTAssertEqual(idle.frameCount, 8)
        let stride = Int(WS3ResourceReadback.frameBytes)
        XCTAssertEqual((0..<8).map { idle.bytes[$0 * stride] }, [0,1,3,4,6,7,9,11])
        XCTAssertEqual(completed.frameCount, 12)
        XCTAssertThrowsError(try StudioScreenArtworkPlan.fallback(payload(16, count: 3)))
    }
    func testStaticCompletedImageCopiesExactlyToIdle() throws {
        let completed = try payload(3, count: 1)
        let idle = try StudioScreenArtworkPlan.fallback(completed)
        XCTAssertEqual(idle.entryID, 0); XCTAssertEqual(idle.bytes, completed.bytes)
        XCTAssertEqual(idle.crc32, completed.crc32)
    }
    func testOldIdleDraftIsRetainedButNotSubmittedUntilExplicitCompletedWrite() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("resources.plist")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = try payload(8, count: 1), completed = try payload(11, count: 12)
        let store = StudioResourceDraftStore(url: url)
        let items = [old, completed].map { p in StudioResourceDraftStore.Item(entry: p.entryID, bytes: p.bytes, checksum: p.crc32,
            frameCount: p.frameCount, previewPNG: nil, filename: "test.gif", sourceFrameCount: Int(p.frameCount), wasResized: false) }
        try await store.save(.init(items: items), revision: 1)
        let model = StudioResourceInspectorModel(storeURL: url)
        for _ in 0..<1000 {
            if !model.isPreparing { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(model.drafts[8]?.payload, old)
        XCTAssertFalse(model.screenDirtyEntries.contains(8))
        model.selectEntry(11)
        try model.stageCompletedFallback(mode: .mode2)
        XCTAssertEqual(model.drafts[8]?.payload, try StudioScreenArtworkPlan.fallback(completed))
        XCTAssertTrue(model.screenDirtyEntries.contains(8))
        XCTAssertEqual(model.drafts[11]?.payload, completed)
    }

    func testPendingIdleRestoreSurvivesRelaunchAfterCompletedRestoreSucceeded() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("resources.plist")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = StudioResourceDraftStore(url: url)
        try await store.save(.init(defaults: [8], completedFallbacks: [8]), revision: 1)
        let model = StudioResourceInspectorModel(storeURL: url)
        for _ in 0..<1000 {
            if !model.isPreparing { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(model.screenDirtyEntries.contains(8))
        XCTAssertEqual(StudioScreenArtworkPlan.pending(mode: 2, presentation: .single, dirty: model.screenDirtyEntries), [8])
        model.selectEntry(11); model.discardSelection()
        XCTAssertFalse(model.defaultDrafts.contains(8))
        XCTAssertFalse(model.completedFallbacks.contains(8))
    }

}
