import Foundation

/// Serial ownership of a command channel. Cancelling a queued caller never
/// releases the current owner; an old owner's defer cannot release a new turn.
@MainActor
public final class CommandTurnQueue {
    public struct Ticket: Equatable, Sendable {
        public let generation: UInt64
        fileprivate let id: UUID
    }
    public enum Failure: Error, Equatable { case invalidated, reset }
    private struct Waiter {
        let ticket: Ticket
        let continuation: CheckedContinuation<Ticket, Error>
    }
    private var generation: UInt64 = 0
    private var active: Ticket?
    private var waiters: [Waiter] = []
    public private(set) var isInvalidated = false
    public var isOccupied: Bool { active != nil }
    public var waitingCount: Int { waiters.count }

    public init() {}

    public func isCurrent(_ ticket: Ticket) -> Bool { !isInvalidated && active == ticket }

    public func acquire() async throws -> Ticket {
        let ticket = Ticket(generation: generation, id: UUID())
        return try await withTaskCancellationHandler(operation: {
            do {
                try Task.checkCancellation()
                let granted: Ticket = try await withCheckedThrowingContinuation { continuation in
                    if isInvalidated { continuation.resume(throwing: Failure.invalidated) }
                    else if active == nil { active = ticket; continuation.resume(returning: ticket) }
                    else { waiters.append(.init(ticket: ticket, continuation: continuation)) }
                }
                // Cancellation can race with a queue handoff. No transport write
                // has happened yet, so returning this unconsumed turn is safe.
                try Task.checkCancellation()
                return granted
            } catch {
                if active == ticket { release(ticket) }
                throw error
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancelQueued(ticket) }
        })
    }

    private func cancelQueued(_ ticket: Ticket) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    public func release(_ ticket: Ticket) {
        guard active == ticket else { return }
        active = nil
        guard !isInvalidated, !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        active = next.ticket
        next.continuation.resume(returning: next.ticket)
    }
    public func invalidate() {
        isInvalidated = true
        active = nil
        failWaiters(Failure.invalidated)
    }
    public func reset(generation: UInt64) {
        self.generation = generation
        active = nil
        isInvalidated = false
        failWaiters(Failure.reset)
    }
    private func failWaiters(_ error: Error) {
        let previous = waiters
        waiters.removeAll()
        previous.forEach { $0.continuation.resume(throwing: error) }
    }
}
