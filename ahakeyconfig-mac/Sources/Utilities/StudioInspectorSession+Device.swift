import Foundation

extension StudioInspectorSession {
    /// Called by the Inspector for read/save/explicit preview only, never for
    /// selecting a component or changing a local draft.
    convenience init(bleManager: AhaKeyBLEManager) {
        self.init(bleManager: bleManager, agentManager: .shared)
    }

    convenience init(bleManager: AhaKeyBLEManager, agentManager: AgentManager) {
        self.init(access: Access(begin: {
            guard !bleManager.isConfigurationOperationInProgress else { throw Failure.busy }
            agentManager.setBluetoothConnectionOwner(.ahaKeyStudio, bleManager: bleManager)
            let revision = agentManager.bluetoothOwnershipRevision
            if !bleManager.isConnected && !bleManager.isScanning {
                bleManager.userInitiatedConnect()
            }
            return revision
        }, isCurrent: { revision in
            agentManager.bluetoothConnectionOwner == .ahaKeyStudio &&
                agentManager.bluetoothOwnershipRevision == revision
        }, isReady: {
            bleManager.isConnected && bleManager.commandCharReady && bleManager.notifyCharReady
        }, generation: {
            bleManager.configurationSnapshot.generation
        }, deviceID: {
            bleManager.bleDeviceUUID
        }, release: { _ in
            agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        }, pause: {
            // Bounded readiness observation only; no RPC, file scan or refresh.
            try await Task.sleep(for: .milliseconds(100))
        }, prepare: {
            await bleManager.studioPresentation.quiesce()
        }))
    }
}
