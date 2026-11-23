import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioResourceDraftStoreTests: XCTestCase {
    private func location() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("resource-drafts-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("drafts.plist")
    }
    private func item(entry: UInt8 = 0) throws -> StudioResourceDraftStore.Item {
        let payload = try WS3ResourcePayload(entryID: entry, frames: [Data(repeating: 0x42, count: 25_600)])
        return .init(entry: entry, bytes: payload.bytes, checksum: payload.crc32, frameCount: 1,
                     previewPNG: nil, filename: "selected.jpeg", sourceFrameCount: 1, wasResized: true)
    }
    func testArchiveRoundTripPreservesPayloadDefaultsAndUncertainty() async throws {
        let url = location(), store = StudioResourceDraftStore(url: url)
        let image = try item()
        let snapshot = StudioResourceDraftStore.Snapshot(items: [image], defaults: [16],
            unconfirmed: [0], uncertainDeviceID: "keyboard-A")
        try await store.save(snapshot, revision: 1)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.payloads[0]?.bytes, image.bytes)
        XCTAssertEqual(loaded.snapshot.defaults, [16]); XCTAssertEqual(loaded.snapshot.unconfirmed, [0])
        XCTAssertEqual(loaded.snapshot.uncertainDeviceID, "keyboard-A")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testOlderSaveCannotResurrectDiscardedArtwork() async throws {
        let url = location(), store = StudioResourceDraftStore(url: url)
        let snapshot = StudioResourceDraftStore.Snapshot(items: [try item()])
        try await store.save(snapshot, revision: 1)
        try await store.save(.init(), revision: 3)
        try await store.save(snapshot, revision: 2)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.snapshot.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testCorruptPixelsCannotBecomeAnUploadPayload() async throws {
        let store = StudioResourceDraftStore(url: location()), source = try item()
        var changed = source.bytes; changed[10] ^= 0xFF
        let bad = StudioResourceDraftStore.Item(entry: source.entry, bytes: changed, checksum: source.checksum,
            frameCount: 1, previewPNG: nil, filename: "image", sourceFrameCount: 1, wasResized: false)
        try await store.save(.init(items: [bad]), revision: 1)
        do { _ = try await store.load(); XCTFail("CRC must detect altered pixel bytes") } catch {}
    }
    func testTwelveFrameArtworkSurvivesIndependentReload() async throws {
        let payload = try WS3ResourcePayload(entryID: 18,
            frames: (0..<12).map { Data(repeating: UInt8($0), count: 25_600) })
        let value = StudioResourceDraftStore.Item(entry: 18, bytes: payload.bytes, checksum: payload.crc32,
            frameCount: 12, previewPNG: nil, filename: "maximum.gif", sourceFrameCount: 13, wasResized: true)
        let url = location()
        try await StudioResourceDraftStore(url: url).save(.init(items: [value]), revision: 1)
        let loaded = try await StudioResourceDraftStore(url: url).load()
        XCTAssertEqual(loaded.payloads[18], payload)
        XCTAssertEqual(loaded.snapshot.items.first?.sourceFrameCount, 13)
    }

    func testPendingUploadOnPreviousKeyboardDoesNotBlockReadingAndWritingDraftOnCurrentKeyboard() async throws {
        let url = location(), store = StudioResourceDraftStore(url: url)
        try await store.save(.init(items: [try item(entry: 18)], unconfirmed: [18],
                                  uncertainDeviceID: "keyboard-A"), revision: 1)
        let model = StudioResourceInspectorModel(storeURL: url)
        for _ in 0..<1000 {
            if !model.isPreparing { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(model.isPreparing)
        model.selectEntry(18)
        var connectedDevice = "keyboard-B"
        let session = StudioInspectorSession(access: .init(begin: { 1 }, isCurrent: { $0 == 1 },
            isReady: { true }, generation: { 7 }, deviceID: { connectedDevice }, release: { _ in }, pause: {}))
        XCTAssertTrue(session.beginEditing(deviceID: "keyboard-A", isConnected: true))
        let resources = (UInt8(0)..<19).compactMap {
            WS3ResourceReadback(id: $0, basic: .resourceBasic(userValid: false, writeState: .empty),
                integrity: .resourceIntegrity(frames: 0, bytes: 0, crc32: 0))
        }
        let success = await withCheckedContinuation { continuation in
            model.read(session: session, completion: { continuation.resume(returning: $0) }) {
                WS3DisplaySnapshot(generation: 7, brightness: 35, resources: resources)
            }
        }
        XCTAssertTrue(success)
        XCTAssertEqual(model.deviceID, "keyboard-B")
        XCTAssertEqual(session.editingDeviceID, "keyboard-B")
        XCTAssertNil(model.readback(for: 18, on: "keyboard-A"))
        XCTAssertEqual(model.readback(for: 18, on: "keyboard-B")?.id, 18)
        XCTAssertTrue(model.canWrite)
        XCTAssertTrue(model.hasPendingOnOtherKeyboard)
        XCTAssertTrue(model.unconfirmed.isEmpty)
        XCTAssertEqual(model.draft?.filename, "selected.jpeg")

        connectedDevice = "keyboard-A"
        let returned = await withCheckedContinuation { continuation in
            model.read(session: session, completion: { continuation.resume(returning: $0) }) {
                WS3DisplaySnapshot(generation: 7, brightness: 35, resources: resources)
            }
        }
        XCTAssertTrue(returned)
        XCTAssertEqual(session.editingDeviceID, "keyboard-A")
        XCTAssertEqual(model.unconfirmed, [18])
        XCTAssertFalse(model.hasPendingOnOtherKeyboard)
    }

    func testArchivePreservesIndependentPendingUploadsForTwoKeyboards() async throws {
        let store = StudioResourceDraftStore(url: location())
        let uploads: [String: Set<UInt8>] = ["keyboard-A": [18], "keyboard-B": [18, 4]]
        try await store.save(.init(unconfirmedByDevice: uploads), revision: 1)
        let loaded = try await store.load()
        XCTAssertFalse(loaded.snapshot.isEmpty)
        XCTAssertEqual(loaded.snapshot.pendingUploads, uploads)
    }

    func testRelaunchRestoresEditingDataWithoutDeviceFactsOrWriteAccess() async throws {
        let url = location(), store = StudioResourceDraftStore(url: url)
        try await store.save(.init(items: [try item()], defaults: [16], unconfirmed: [0],
                                  uncertainDeviceID: "keyboard-A"), revision: 1)
        let model = StudioResourceInspectorModel(storeURL: url)
        for _ in 0..<1000 {
            if !model.isPreparing { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(model.isPreparing)
        XCTAssertEqual(model.draft?.filename, "selected.jpeg")
        XCTAssertEqual(model.defaultDrafts, [16]); XCTAssertTrue(model.unconfirmed.isEmpty)
        XCTAssertNil(model.display); XCTAssertNil(model.deviceID); XCTAssertFalse(model.canWrite)
        model.discardSelection()
        try await model.flushDraftPersistence()
        let loaded = try await store.load()
        XCTAssertTrue(loaded.snapshot.items.isEmpty)
        XCTAssertEqual(loaded.snapshot.pendingUploads, ["keyboard-A": [0]], "discarding a local draft is not upload rollback")
    }
}
