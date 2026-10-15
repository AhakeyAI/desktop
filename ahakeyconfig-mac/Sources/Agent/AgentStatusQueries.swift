import Foundation

/// Tracks outstanding BLE reads. A timeout resolves only its own request as
/// unknown; neither an old deadline nor a cached display value can authorize it.
struct AgentStatusQueries {
    private var waiters: [UUID: (AgentDeviceStatus?) -> Void] = [:]

    var isEmpty: Bool { waiters.isEmpty }

    mutating func append(_ completion: @escaping (AgentDeviceStatus?) -> Void) -> UUID {
        let id = UUID()
        waiters[id] = completion
        return id
    }

    mutating func timeOut(_ id: UUID) {
        let completion = waiters.removeValue(forKey: id)
        completion?(nil)
    }

    mutating func resolveAll(with status: AgentDeviceStatus?) {
        let completions = Array(waiters.values)
        waiters.removeAll()
        for completion in completions { completion(status) }
    }
}
