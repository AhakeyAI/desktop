/// Single-task Hook writes share the BLE channel with approval reads.
/// Owned by the Agent main queue; MULTI is delivered by WS3PresentationSession.
struct AgentHookStateDelivery {
    private var pending: UInt8?

    mutating func submit(_ state: UInt8, presentationBlocked: Bool, approvalBusy: Bool,
                         write: (UInt8) -> Void) {
        // A newer MULTI/mode transition must not replay a stale SINGLE state.
        pending = nil
        guard !presentationBlocked else { return }
        guard !approvalBusy else { pending = state; return }
        write(state)
    }

    mutating func takePending() -> UInt8? {
        defer { pending = nil }
        return pending
    }

    mutating func reset() { pending = nil }
}
