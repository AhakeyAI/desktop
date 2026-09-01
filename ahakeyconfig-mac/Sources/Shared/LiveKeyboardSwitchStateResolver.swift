/// Resolves the keyboard lever value from the Runtime process that currently owns BLE.
/// The main app's cached value must not mask Runtime's live value while Runtime owns the connection.
public enum LiveKeyboardSwitchStateResolver {
    public static func resolve(
        optimisticOverride: Int?,
        appIsConnected: Bool,
        appState: Int?,
        runtimeState: Int?
    ) -> Int? {
        if let optimisticOverride { return optimisticOverride }
        if appIsConnected { return appState }
        return runtimeState
    }
}
