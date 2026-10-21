import Foundation

/// UI evidence for one resource upload. Connection loss invalidates success,
/// but cannot turn an unfinished write into an empty, reassuring message.
public struct WS3UploadFeedback: Equatable {
    public enum Phase: Equatable { case idle, sending, confirmed, unconfirmed }
    public private(set) var phase: Phase = .idle
    public private(set) var entryID: UInt8?
    public private(set) var unconfirmedEntries: Set<UInt8> = []
    private var attempt: UUID?
    private var generation: UInt64?

    public init() {}

    public mutating func begin(entry: UInt8, generation: UInt64) -> UUID {
        if phase == .sending, let entryID { unconfirmedEntries.insert(entryID) }
        let ticket = UUID()
        attempt = ticket; self.generation = generation; entryID = entry; phase = .sending
        return ticket
    }

    @discardableResult
    public mutating func confirm(_ ticket: UUID, currentGeneration: UInt64) -> Bool {
        connectionChanged(to: currentGeneration)
        guard attempt == ticket else { return false }
        if let entryID { unconfirmedEntries.remove(entryID) }
        attempt = nil; phase = .confirmed
        return true
    }

    @discardableResult
    public mutating func fail(_ ticket: UUID, currentGeneration: UInt64) -> Bool {
        connectionChanged(to: currentGeneration)
        guard attempt == ticket else { return false }
        if let entryID { unconfirmedEntries.insert(entryID) }
        attempt = nil; phase = .unconfirmed
        return true
    }

    public mutating func connectionChanged(to currentGeneration: UInt64) {
        guard generation != currentGeneration else { return }
        generation = currentGeneration
        attempt = nil
        if phase == .sending {
            if let entryID { unconfirmedEntries.insert(entryID) }
            phase = .unconfirmed
        } else if phase == .confirmed { phase = .idle; entryID = nil }
    }

    public mutating func restoredDefault(entry: UInt8) {
        unconfirmedEntries.remove(entry)
        if phase == .unconfirmed, entryID == entry { phase = .idle; entryID = nil }
    }
}
