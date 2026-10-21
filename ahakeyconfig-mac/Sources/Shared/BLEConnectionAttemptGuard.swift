import Foundation

/// CoreBluetooth connect requests have no implicit deadline. Keep a timed-out
/// request quarantined until its cancellation callback, so a late connect cannot
/// publish a ready channel or race a replacement request.
public struct BLEConnectionAttemptGuard {
    public static let deadlineSeconds: TimeInterval = 15
    public struct Ticket: Equatable {
        fileprivate let id = UUID()
        public let target: UUID
        fileprivate let retryAutomatically: Bool
    }
    private enum Phase {
        case idle, connecting(Ticket), connected(Ticket), cancelling(Ticket)
        var ticket: Ticket? {
            switch self {
            case .idle: return nil
            case .connecting(let ticket), .connected(let ticket), .cancelling(let ticket): return ticket
            }
        }
    }
    private var phase: Phase = .idle
    public private(set) var requiresManualRetry = false
    public var mayBegin: Bool { phase.ticket == nil && !requiresManualRetry }
    public init() {}

    public mutating func begin(target: UUID, retryAutomatically: Bool) -> Ticket? {
        guard mayBegin else { return nil }
        let ticket = Ticket(target: target, retryAutomatically: retryAutomatically)
        phase = .connecting(ticket)
        return ticket
    }
    public mutating func connected(target: UUID) -> Bool {
        guard phase.ticket?.target == target else { return false }
        switch phase {
        case .connecting(let ticket): phase = .connected(ticket); return true
        case .connected: return true
        case .idle, .cancelling: return false
        }
    }
    public mutating func timeOut(_ ticket: Ticket) -> Bool {
        guard case .connecting(let current) = phase, current == ticket else { return false }
        phase = .cancelling(ticket)
        requiresManualRetry = !ticket.retryAutomatically
        return true
    }
    @discardableResult
    public mutating func ended(target: UUID) -> Bool {
        guard phase.ticket?.target == target else { return false }
        if case .connecting(let ticket) = phase {
            requiresManualRetry = !ticket.retryAutomatically
        }
        phase = .idle
        return true
    }
    /// User intent cannot bypass an outstanding cancellation.
    public mutating func resumeByUser() -> Bool {
        guard phase.ticket == nil else { return false }
        requiresManualRetry = false
        return true
    }
    public mutating func reset() {
        phase = .idle
        requiresManualRetry = false
    }
}
