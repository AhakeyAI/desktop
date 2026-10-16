import Foundation

/// Tracks outstanding BLE reads. A timeout resolves only its own request as
/// unknown; neither an old deadline nor a cached display value can authorize it.
struct AgentStatusQueries {
    private var waiters: [UUID: (AgentDeviceStatus?) -> Void] = [:]

    private(set) var acceptsResponses = true

    var isEmpty: Bool { waiters.isEmpty }

    mutating func append(_ completion: @escaping (AgentDeviceStatus?) -> Void) -> UUID {
        let id = UUID()
        guard acceptsResponses else { completion(nil); return id }
        waiters[id] = completion
        return id
    }

    @discardableResult
    mutating func timeOut(_ id: UUID) -> Bool {
        guard let completion = waiters.removeValue(forKey: id) else { return false }
        // Status frames carry no request ID: after any timeout this connection
        // cannot distinguish a late reply from a new query's response.
        acceptsResponses = false
        completion(nil)
        resolveAll(with: nil)
        return true
    }

    mutating func resolveAll(with status: AgentDeviceStatus?) {
        let completions = Array(waiters.values)
        waiters.removeAll()
        for completion in completions { completion(acceptsResponses ? status : nil) }
    }
}
