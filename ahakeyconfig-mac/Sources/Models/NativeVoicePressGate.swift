import CoreGraphics
import Foundation

/// Native recording has one physical gesture owner, even when several aliases route to it.
struct NativeVoicePressGate {
    struct Ticket: Equatable {
        fileprivate let code: CGKeyCode
        fileprivate let id = UUID()
    }

    private var active: Ticket?

    mutating func begin(code: CGKeyCode) -> Ticket? {
        guard active == nil else { return nil }
        let ticket = Ticket(code: code)
        active = ticket
        return ticket
    }

    mutating func end(code: CGKeyCode) -> Bool {
        guard active?.code == code else { return false }
        active = nil
        return true
    }

    func isCurrent(_ ticket: Ticket) -> Bool { active == ticket }

    mutating func cancel() { active = nil }
}
