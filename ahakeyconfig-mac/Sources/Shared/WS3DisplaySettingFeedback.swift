import Foundation

/// Session-local receipts. A read proves the current value, not that an earlier
/// interrupted save persisted it. Only a confirmed save of the same item clears it.
public struct WS3DisplaySettingFeedback {
    public enum Key: Hashable {
        case brightness
        case singleLight(mode: UInt8, state: UInt8)
    }
    public struct Ticket: Equatable {
        fileprivate let id: UUID
        fileprivate let generation: UInt64
        fileprivate let save: WS3DisplaySetting?
    }
    public private(set) var unconfirmed: [Key: WS3DisplaySetting] = [:]
    private var generation: UInt64?
    private var active: Ticket?
    private var started = false

    public init() {}

    public mutating func begin(generation: UInt64, save: WS3DisplaySetting? = nil) -> Ticket {
        connectionChanged(to: generation)
        invalidate()
        let ticket = Ticket(id: UUID(), generation: generation, save: save)
        active = ticket
        return ticket
    }

    /// Check before starting I/O as well as after awaiting its result.
    public mutating func start(_ ticket: Ticket, currentGeneration: UInt64) -> Bool {
        connectionChanged(to: currentGeneration)
        guard active == ticket else { return false }
        started = true
        return true
    }

    public mutating func succeed(_ ticket: Ticket, currentGeneration: UInt64) -> Bool {
        connectionChanged(to: currentGeneration)
        guard active == ticket, started else { return false }
        if let save = ticket.save { unconfirmed.removeValue(forKey: save.feedbackKey) }
        active = nil; started = false
        return true
    }

    public mutating func fail(_ ticket: Ticket, currentGeneration: UInt64, mayHaveApplied: Bool) -> Bool {
        connectionChanged(to: currentGeneration)
        guard active == ticket else { return false }
        if mayHaveApplied { invalidate() }
        else { active = nil; started = false }
        return true
    }

    @discardableResult
    public mutating func connectionChanged(to generation: UInt64) -> Bool {
        guard self.generation != generation else { return false }
        invalidate()
        self.generation = generation
        return true
    }

    public mutating func invalidate() {
        if started, let save = active?.save { unconfirmed[save.feedbackKey] = save }
        active = nil; started = false
    }
}

extension WS3DisplaySetting {
    public var feedbackKey: WS3DisplaySettingFeedback.Key {
        switch self {
        case .brightness: return .brightness
        case .singleLight(let mode, let state, _): return .singleLight(mode: mode, state: state)
        }
    }
}
