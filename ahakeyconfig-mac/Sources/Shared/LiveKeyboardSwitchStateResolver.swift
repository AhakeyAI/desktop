/// Resolves the keyboard lever value from whichever process currently owns BLE.
/// The main app's cached value must not mask the Agent's live value while the Agent owns the connection.
public enum LiveKeyboardSwitchStateResolver {
    public static func resolve(
        optimisticOverride: Int?,
        appIsConnected: Bool,
        appState: Int?,
        agentState: Int?
    ) -> Int? {
        if let optimisticOverride { return optimisticOverride }
        if appIsConnected { return appState }
        return agentState
    }
}
