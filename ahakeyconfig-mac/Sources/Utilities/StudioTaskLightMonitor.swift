import Foundation
import Combine
import AhaKeyConfigShared

/// Read-only live snapshots. The view owns a cancellable, foreground-only poll;
/// no hook events, approval requests or keyboard writes are generated here.
@MainActor
final class StudioTaskLightMonitor: ObservableObject {
    @Published private(set) var animation: WS3TaskLightAnimation?
    private var observation: UUID?
    private var revision: UInt64?

    func beginObservation() -> UUID {
        let token = UUID()
        observation = token
        clear()
        return token
    }

    func endObservation(_ token: UUID) {
        guard observation == token else { return }
        observation = nil
        clear()
    }

    private var references: [String?] = Array(repeating: nil, count: 4)

    func clear() {
        if animation != nil { animation = nil }
        revision = nil
        references = Array(repeating: nil, count: 4)
    }

    func observe(_ overview: WS3TaskOverview?, revision: UInt64, at time: TimeInterval) {
        guard let overview, overview.connected, overview.requestedMode == .multi else { clear(); return }
        if self.revision != revision { clear(); self.revision = revision }
        var slots: [WS3TaskSlot?] = Array(repeating: nil, count: 4)
        var nextReferences: [String?] = Array(repeating: nil, count: 4)
        for task in overview.tasks where (0..<4).contains(task.slot) {
            slots[task.slot] = .init(state: task.state)
            nextReferences[task.slot] = task.reference
        }
        var value = animation ?? .init()
        // A reused slot is a new session even when it has the same state.
        if nextReferences != references {
            var boundary = value.snapshot.slots
            for slot in 0..<4 where nextReferences[slot] != references[slot] { boundary[slot] = nil }
            value.observe(WS3TaskSnapshot(slots: boundary)!, at: time)
        }
        value.observe(WS3TaskSnapshot(slots: slots)!, at: time)
        references = nextReferences
        if animation != value { animation = value }
    }
}
