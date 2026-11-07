import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class AgentStartupFallbackTests: XCTestCase {
    func testSelectingAlreadyRequestedAgentRetriesAfterAppFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ble = AhaKeyBLEManager(startServices: false,
            logStore: BLELogStore(verboseLogFileURL: root.appendingPathComponent("verbose.log"), persistentLogFileURL: root.appendingPathComponent("persistent.log")),
            connectionLock: BLEConnectionLock(lockURL: root.appendingPathComponent("owner.lock")),
            ideStateDirectoryURL: root.appendingPathComponent("state"))
        let manager = AgentManager(startServices: false)
        XCTAssertEqual(manager.bluetoothConnectionOwner, .agentDaemon)
        manager.fallBackToAppForAgent(bleManager: ble)
        let revision = manager.bluetoothOwnershipRevision
        manager.setBluetoothConnectionOwner(.agentDaemon, bleManager: ble)
        XCTAssertEqual(manager.bluetoothOwnershipRevision, revision + 1,
                       "An Agent selection must retry a failed handoff instead of requiring App -> Agent toggling")
        // This fixture has no installed job or CoreBluetooth central; it cannot
        // start the user's Agent. Drain its bounded connection fallback task.
        try await Task.sleep(nanoseconds: 650_000_000)
    }

    func testAlreadySelectedAgentWithoutFallbackDoesNotRestartOwnership() {
        let manager = AgentManager(startServices: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ble = AhaKeyBLEManager(startServices: false,
            logStore: BLELogStore(verboseLogFileURL: root.appendingPathComponent("verbose.log"), persistentLogFileURL: root.appendingPathComponent("persistent.log")),
            connectionLock: BLEConnectionLock(lockURL: root.appendingPathComponent("owner.lock")),
            ideStateDirectoryURL: root.appendingPathComponent("state"))
        manager.setBluetoothConnectionOwner(.agentDaemon, bleManager: ble)
        XCTAssertEqual(manager.bluetoothOwnershipRevision, 0)
    }
}
