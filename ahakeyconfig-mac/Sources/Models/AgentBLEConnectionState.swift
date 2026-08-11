import Foundation

/// 主 App 从 Agent socket 收到的 BLE 连接快照。
///
/// Agent 拥有键盘时，主 App 的 `AhaKeyBLEManager` 会被刻意暂停，不能再用它的
/// "连接中" 或缓存设备名代表实际连接状态。
struct AgentBLEConnectionState: Equatable {
    let isConnected: Bool
    let deviceName: String?
    let deviceUUID: String?
    let commandReady: Bool
    let notifyReady: Bool

    init(
        isConnected: Bool,
        deviceName: String?,
        deviceUUID: String?,
        commandReady: Bool,
        notifyReady: Bool
    ) {
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.deviceUUID = deviceUUID
        self.commandReady = commandReady
        self.notifyReady = notifyReady
    }

    static let disconnected = AgentBLEConnectionState(
        isConnected: false,
        deviceName: nil,
        deviceUUID: nil,
        commandReady: false,
        notifyReady: false
    )

    /// 兼容旧 Agent：旧回包没有 `isConnected` 时，沿用已有的 switchState 语义。
    init(socketReply: [String: Any]) {
        let legacyConnected = !(socketReply["switchState"] is NSNull)
            && socketReply["switchState"] != nil

        isConnected = socketReply["isConnected"] as? Bool ?? legacyConnected
        deviceName = socketReply["deviceName"] as? String
        deviceUUID = socketReply["deviceUUID"] as? String
        commandReady = socketReply["commandReady"] as? Bool ?? false
        notifyReady = socketReply["notifyReady"] as? Bool ?? false
    }
}
