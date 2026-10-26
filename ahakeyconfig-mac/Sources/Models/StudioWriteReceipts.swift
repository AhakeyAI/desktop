import Foundation

/// Uncertain sends survive a process restart. These opaque scoped identifiers
/// are warnings, not device facts or authorization to retry a write.
enum StudioWriteReceipts {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var value: (Data, Set<String>)?
    }
    private static let cache = Cache()
    static func decode(_ data: Data) -> Set<String> {
        guard !data.isEmpty, data.count <= 2_000_000 else { return [] }
        cache.lock.lock()
        if let value = cache.value, value.0 == data {
            cache.lock.unlock(); return value.1
        }
        cache.lock.unlock()
        guard let values = try? JSONDecoder().decode(Set<String>.self, from: data),
              values.count <= 4096, values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else { return [] }
        cache.lock.lock(); cache.value = (data, values); cache.lock.unlock()
        return values
    }
    static func encode(_ values: Set<String>) -> Data {
        (try? JSONEncoder().encode(values)) ?? Data()
    }
}
