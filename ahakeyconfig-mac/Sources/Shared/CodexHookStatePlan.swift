public struct CodexHookStatePlan: Equatable, Sendable {
    public enum Command: Equatable, Sendable {
        case state
        case stateWithReset
    }

    public let command: Command
    public let stateValue: UInt8
    public let resetValue: UInt8?
    public let delayMilliseconds: Int?

    public static func make(stateValue: UInt8) -> CodexHookStatePlan {
        if stateValue == 2 {
            return CodexHookStatePlan(
                command: .stateWithReset,
                stateValue: stateValue,
                resetValue: 5,
                delayMilliseconds: 12_000
            )
        }
        return CodexHookStatePlan(
            command: .state,
            stateValue: stateValue,
            resetValue: nil,
            delayMilliseconds: nil
        )
    }
}
