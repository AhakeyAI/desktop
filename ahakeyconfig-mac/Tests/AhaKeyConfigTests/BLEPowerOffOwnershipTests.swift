import AhaKeyConfigShared
import XCTest
@testable import AhaKeyConfig

final class BLEPowerOffOwnershipTests: XCTestCase {
    @MainActor
    func testPowerOffReleasesRetainedHandoffLockWithoutWaitingForOldPeripheral() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("owner.lock")
        let appLock = BLEConnectionLock(lockURL: lockURL)
        let agentLock = BLEConnectionLock(lockURL: lockURL)
        let manager = AhaKeyBLEManager(startServices: false,
            logStore: BLELogStore(verboseLogFileURL: root.appendingPathComponent("verbose.log"), persistentLogFileURL: root.appendingPathComponent("persistent.log")),
            connectionLock: appLock, ideStateDirectoryURL: root.appendingPathComponent("state"))
        manager.setSuppressedForAgentOwningKeyboard(true)
        // Model the retained real flock while native peripheral cancellation is pending.
        XCTAssertTrue(appLock.acquire())
        XCTAssertFalse(agentLock.acquire())
        manager.handleBluetoothPoweredOff()
        XCTAssertFalse(appLock.holdsLock)
        XCTAssertTrue(agentLock.acquire(), "The old peripheral callback is no longer needed to release ownership")
        agentLock.release()
    }

    @MainActor
    func testPowerOffDoesNotYieldWhenAppStillOwnsConnection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = BLEConnectionLock(lockURL: root.appendingPathComponent("owner.lock"))
        let manager = AhaKeyBLEManager(startServices: false,
            logStore: BLELogStore(verboseLogFileURL: root.appendingPathComponent("verbose.log"), persistentLogFileURL: root.appendingPathComponent("persistent.log")),
            connectionLock: lock, ideStateDirectoryURL: root.appendingPathComponent("state"))
        XCTAssertTrue(lock.acquire())
        manager.handleBluetoothPoweredOff()
        XCTAssertTrue(lock.holdsLock)
        lock.release()
    }
}
