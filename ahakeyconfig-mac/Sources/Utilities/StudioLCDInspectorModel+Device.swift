import Foundation
import AhaKeyConfigShared

extension StudioLCDInspectorModel.Access {
    @MainActor
    static func production(ble: AhaKeyBLEManager) -> Self {
        let manager = AgentManager.shared, bridge = TaskForegroundBridge.shared
        return .init(revision: { manager.bluetoothOwnershipRevision }, available: {
            manager.bluetoothConnectionOwner == .ahaKeyStudio
                ? (ble.isConnected && !ble.isConfigurationOperationInProgress) : manager.isRunning
        }, read: {
            if manager.bluetoothConnectionOwner == .ahaKeyStudio { return ble.studioPresentation.readOverview().supportingTargetedModeWrites() }
            return await manager.readTaskOverview()
        }, apply: { mode, deviceID, generation in
            if manager.bluetoothConnectionOwner == .ahaKeyStudio {
                guard ble.bleDeviceUUID == deviceID, ble.configurationSnapshot.generation == generation else {
                    throw WS3PresentationError.connectionChanged
                }
                return try await ble.studioPresentation.activate(mode).supportingTargetedModeWrites()
            }
            return try await manager.applyPresentationMode(mode, expectedDeviceID: deviceID, expectedGeneration: generation)
        }, followEnabled: { bridge.enabled }, setFollow: { bridge.enabled = $0 })
    }
}
