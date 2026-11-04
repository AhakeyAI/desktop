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


    func clear() {
        if animation != nil { animation = nil }
        revision = nil
    }

    func observe(_ overview: WS3TaskOverview?, revision: UInt64, at time: TimeInterval) {
        guard let overview, overview.connected, overview.requestedMode == .multi else { clear(); return }
        if self.revision != revision { clear(); self.revision = revision }
        var slots: [WS3TaskSlot?] = Array(repeating: nil, count: 4)
        for task in overview.tasks where (0..<4).contains(task.slot) {
            slots[task.slot] = .init(state: task.state)
        }
        var value = animation ?? .init()
        value.observe(WS3TaskSnapshot(slots: slots)!, at: time)
        if animation != value { animation = value }
    }
}
