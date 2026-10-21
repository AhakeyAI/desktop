import Foundation
import AhaKeyConfigShared

/// Legacy writes have no transaction identifier. Before starting an advanced
/// exchange, drain their replies instead of racing the firmware's one ready slot.
/// A lost reply makes this connection unsuitable for advanced traffic; ordinary
/// legacy operation retains its existing fire-and-forget behavior.
// Owned by the same main queue as Agent BLE delegates.
final class AgentLegacyCommandDrain {
    private var pending: [(UUID, UInt8)] = []
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var uncertain = false
    private struct QueuedWrite {
        let command: UInt8
        let send: (UUID) -> Void
        let abandon: () -> Void
    }
    private var queued: [QueuedWrite] = []

    func sent(_ command: UInt8) -> UUID {
        let id = UUID()
        if pending.count < 128 { pending.append((id, command)) }
        else { fail() }
        return id
    }

    /// Serialize ordinary writes too: the firmware drops a second command
    /// while its first ready slot is occupied. Begin the deadline at wire send.
    func submit(_ command: UInt8, onAbandon: @escaping () -> Void = {}, send: @escaping (UUID) -> Void) {
        if pending.contains(where: { $0.1 != 0xFE }) {
            guard queued.count < 128 else { fail(); onAbandon(); return }
            queued.append(.init(command: command, send: send, abandon: onAbandon))
        } else { send(sent(command)) }
    }

    /// Approval is a multi-read chain on this same channel. Its own bounded
    /// lifecycle releases this reservation, without treating normal busy as fault.
    func reserveApproval() -> UUID { sent(0xFE) }
    func complete(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.0 == id }) else { return }
        pending.remove(at: index)
        advance()
    }

    private func advance() {
        if !pending.contains(where: { $0.1 != 0xFE }), !queued.isEmpty {
            let next = queued.removeFirst()
            next.send(sent(next.command))
        }
        if pending.isEmpty && queued.isEmpty && !uncertain { finish(nil) }
    }

    func received(_ frame: Data) {
        guard frame.count >= 5, frame.starts(with: [0xAA, 0xBB]), frame.suffix(2) == Data([0xCC, 0xDD]),
              (frame[2] == 0x00 && AhaKeyAgent.parseDeviceStatus(frame) != nil) || (frame[2] == 0x90 && frame.count == 6),
              let index = pending.firstIndex(where: { $0.1 == frame[2] }) else { return }
        pending.remove(at: index)
        advance()
    }

    func expired(_ id: UUID) {
        guard pending.contains(where: { $0.0 == id }) else { return }
        fail()
    }

    @MainActor
    func waitUntilIdle() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if uncertain { continuation.resume(throwing: WS3PresentationError.timedOut) }
                else if pending.isEmpty { continuation.resume() }
                else { waiters[id] = continuation }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        })
    }

    func reset() {
        pending.removeAll(); uncertain = false
        let canceled = queued; queued.removeAll()
        canceled.forEach { $0.abandon() }
        finish(WS3PresentationError.connectionChanged)
    }

    private func fail() {
        pending.removeAll(); uncertain = true
        let abandoned = queued; queued.removeAll()
        finish(WS3PresentationError.timedOut)
        for item in abandoned { item.send(UUID()) }
    }

    private func finish(_ error: Error?) {
        let previous = waiters; waiters.removeAll()
        for continuation in previous.values {
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }
}
