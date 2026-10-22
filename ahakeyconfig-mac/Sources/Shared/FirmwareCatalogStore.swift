import Foundation
import CryptoKit

/// Owns only authenticated catalog bytes. Device identity and setting readbacks
/// remain connection-scoped responsibilities of the caller.
public actor FirmwareCatalogStore {
    public enum Source: Equatable, Sendable { case builtin, embedded, cache, refresh }
    public struct Snapshot: Sendable {
        public let catalog: VerifiedFirmwareCatalog?
        public let source: Source
    }
    public enum Failure: Error, Equatable { case revisionConflict }

    private let publicKeys: [String: Data]
    private let cacheURL: URL?
    private var current: Snapshot
    private var payloadDigest: String?
    private var cacheStamp: CacheStamp?
    private struct CacheStamp: Equatable {
        let size: Int
        let inode: UInt64
        let modified: Date
        init?(url: URL) {
            guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = values[.size] as? Int, let inode = values[.systemFileNumber] as? UInt64,
                  let modified = values[.modificationDate] as? Date else { return nil }
            self.size = size; self.inode = inode; self.modified = modified
        }
    }

    public init(publicKeys: [String: Data], embeddedEnvelope: Data? = nil, cacheURL: URL? = nil) {
        self.publicKeys = publicKeys
        self.cacheURL = cacheURL
        var catalog = VerifiedFirmwareCatalog.builtin
        var source = Source.builtin
        var digest: String?
        if let bytes = embeddedEnvelope,
           let verified = try? FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: publicKeys) {
            catalog = verified; source = .embedded
            digest = Self.digestOfPayload(bytes)
        }
        if let cacheURL,
           let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= 2_097_152,
           let bytes = try? Data(contentsOf: cacheURL),
           let verified = try? FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: publicKeys,
               minimumRevision: catalog?.value.revision ?? 0) {
            let cachedDigest = Self.digestOfPayload(bytes)
            if digest == nil || verified.value.revision > (catalog?.value.revision ?? 0) || cachedDigest == digest {
                catalog = verified; source = .cache; digest = cachedDigest
            }
        }
        current = Snapshot(catalog: catalog, source: source)
        payloadDigest = digest
        // Do not sample after reading: a second process may have replaced the
        // file in between. The first operation must consume a fresh stamp.
        cacheStamp = nil
    }

    public func snapshot() -> Snapshot { current }

    /// App and Agent use the same signed cache. Check only on an operation,
    /// never poll; an unchanged file incurs no repeated parsing/signature work.
    public func reloadPersistedIfChanged() {
        guard !publicKeys.isEmpty, let cacheURL, let stamp = CacheStamp(url: cacheURL), stamp != cacheStamp else { return }
        cacheStamp = stamp
        guard stamp.size <= 2_097_152, let bytes = try? Data(contentsOf: cacheURL) else { return }
        _ = try? accept(bytes, persist: false)
    }

    /// Call only for an explicit refresh. A rejected update preserves both the
    /// active catalog and the last authenticated cache; there is no polling.
    @discardableResult
    public func acceptRefresh(_ bytes: Data) throws -> Snapshot {
        try accept(bytes, persist: true)
    }

    private func accept(_ bytes: Data, persist: Bool) throws -> Snapshot {
        let verified = try FirmwareCatalogEnvelope.decodeAndVerify(bytes, publicKeys: publicKeys,
            minimumRevision: current.catalog?.value.revision ?? 0)
        let digest = Self.digestOfPayload(bytes)
        if verified.value.revision == current.catalog?.value.revision,
           let payloadDigest, payloadDigest != digest { throw Failure.revisionConflict }
        if persist, let cacheURL {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: cacheURL, options: .atomic)
            // Another writer may already have replaced our bytes; leave the
            // persisted file unconsumed until reload reads its own pre-stamp.
            cacheStamp = nil
        }
        current = Snapshot(catalog: verified, source: persist ? .refresh : .cache)
        payloadDigest = digest
        return current
    }

    private static func digestOfPayload(_ bytes: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(FirmwareCatalogEnvelope.self, from: bytes) else { return nil }
        return SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
    }
}
