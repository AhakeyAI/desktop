import Foundation
import AhaKeyConfigShared

/// Private local artwork only. No device readbacks or write authorization are
/// archived. Disk encoding and CRC validation run outside the main actor.
actor StudioResourceDraftStore {
    struct Item: Codable, Sendable {
        let entry: UInt8
        let bytes: Data
        let checksum: UInt32
        let frameCount: UInt16
        let previewPNG: Data?
        let filename: String
        let sourceFrameCount: Int
        let wasResized: Bool
        func payload() throws -> WS3ResourcePayload {
            guard entry < 19, frameCount > 0, frameCount <= WS3ResourceReadback.maximumFrames(entry),
                  bytes.count == Int(frameCount) * Int(WS3ResourceReadback.frameBytes),
                  filename.utf8.count <= 1024, sourceFrameCount >= Int(frameCount), sourceFrameCount <= 1_000_000,
                  (previewPNG?.count ?? 0) <= 256_000 else { throw Failure.invalidArchive }
            let stride = Int(WS3ResourceReadback.frameBytes)
            let frames = (0..<Int(frameCount)).map { bytes.subdata(in: ($0 * stride)..<($0 * stride + 25_600)) }
            let result = try WS3ResourcePayload(entryID: entry, frames: frames)
            guard result.bytes == bytes, result.crc32 == checksum else { throw Failure.invalidArchive }
            return result
        }
    }
    struct Snapshot: Codable, Sendable {
        var items: [Item] = []
        var defaults: Set<UInt8> = []
        var unconfirmed: Set<UInt8> = []
        var uncertainDeviceID: String?
        var isEmpty: Bool { items.isEmpty && defaults.isEmpty && unconfirmed.isEmpty }
    }
    struct Loaded: Sendable {
        let snapshot: Snapshot
        let payloads: [UInt8: WS3ResourcePayload]
    }
    enum Failure: Error { case invalidArchive }
    static var productionURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AhaKeyConfig/studio-drafts/resources-v1.plist")
    }
    private let url: URL
    private var latestRevision: UInt64 = 0
    init(url: URL) { self.url = url }

    func load() throws -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init(snapshot: .init(), payloads: [:]) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let length = attributes[.size] as? NSNumber, length.intValue <= 12_000_000 else { throw Failure.invalidArchive }
        let data = try Data(contentsOf: url)
        guard data.count <= 12_000_000 else { throw Failure.invalidArchive }
        let snapshot = try PropertyListDecoder().decode(Snapshot.self, from: data)
        guard snapshot.items.count <= 19, Set(snapshot.items.map(\.entry)).count == snapshot.items.count,
              snapshot.defaults.allSatisfy({ $0 < 19 }), snapshot.unconfirmed.allSatisfy({ $0 < 19 }),
              snapshot.defaults.isDisjoint(with: snapshot.items.map(\.entry)),
              snapshot.unconfirmed.isEmpty || (snapshot.uncertainDeviceID?.isEmpty == false &&
                  (snapshot.uncertainDeviceID?.utf8.count ?? 0) <= 128) else { throw Failure.invalidArchive }
        var payloads: [UInt8: WS3ResourcePayload] = [:]
        for item in snapshot.items { payloads[item.entry] = try item.payload() }
        return .init(snapshot: snapshot, payloads: payloads)
    }
    func save(_ snapshot: Snapshot, revision: UInt64) throws {
        guard revision > latestRevision else { return }
        if snapshot.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let data = try encoder.encode(snapshot)
            guard data.count <= 12_000_000 else { throw Failure.invalidArchive }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        latestRevision = revision
    }
}
