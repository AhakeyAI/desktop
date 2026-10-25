import Foundation

/// Historical component facts inform draft preservation, never authorize a write.
struct StudioKeyBaselines: Codable {
    struct Entry: Codable {
        let deviceID: String
        let mode: AhaKeyModeSlot
        let key: AhaKeyKeyDraft
    }
    private(set) var entries: [Entry] = []
    static let storageKey = "ahakey.studio.key-baselines.v1"
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var value: (data: Data, record: StudioKeyBaselines)?
    }
    private static let cache = Cache()
    var lastDeviceID: String? { entries.last?.deviceID }

    func overlay(on draft: AhaKeyStudioDraft, deviceID: String?) -> AhaKeyStudioDraft {
        guard let deviceID else { return draft }
        var result = draft
        for entry in entries where entry.deviceID == deviceID {
            var mode = result.draft(for: entry.mode)
            mode.updateKey(entry.key); result.updateMode(mode)
        }
        return result
    }

    func key(deviceID: String, mode: AhaKeyModeSlot, role: AhaKeyKeyRole) -> AhaKeyKeyDraft? {
        entries.first { $0.deviceID == deviceID && $0.mode == mode && $0.key.role == role }?.key
    }
    func preservesDraft(_ draft: AhaKeyKeyDraft, deviceID: String, mode: AhaKeyModeSlot) -> Bool {
        guard let previous = key(deviceID: deviceID, mode: mode, role: draft.role) else { return true }
        return previous != draft
    }
    mutating func observe(_ key: AhaKeyKeyDraft, deviceID: String, mode: AhaKeyModeSlot) {
        guard !deviceID.isEmpty, deviceID.utf8.count <= 128 else { return }
        entries.removeAll { $0.deviceID == deviceID && $0.mode == mode && $0.key.role == key.role }
        entries.append(.init(deviceID: deviceID, mode: mode, key: key))
        // Bound retained history; evict oldest facts, never local drafts.
        if entries.count > 256 { entries.removeFirst(entries.count - 256) }
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey), data.count <= 2_000_000 else { return .init() }
        cache.lock.lock()
        if let cached = cache.value, cached.data == data {
            cache.lock.unlock()
            return cached.record
        }
        cache.lock.unlock()
        var result = (try? JSONDecoder().decode(Self.self, from: data)) ?? .init()
        if result.entries.count > 256 || !result.entries.allSatisfy({ !$0.deviceID.isEmpty && $0.deviceID.utf8.count <= 128 }) {
            result = .init()
        }
        cache.lock.lock()
        cache.value = (data, result)
        cache.lock.unlock()
        return result
    }
    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
            Self.cache.lock.lock()
            Self.cache.value = (data, self)
            Self.cache.lock.unlock()
        }
    }
}
