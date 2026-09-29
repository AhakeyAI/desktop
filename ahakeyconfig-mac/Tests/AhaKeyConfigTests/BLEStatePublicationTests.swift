import AhaKeyConfigShared
import Combine
import XCTest
@testable import AhaKeyConfig

final class BLEStatePublicationTests: XCTestCase {
    func testIdenticalProductionStatusFramesDoNotPublishOrGrowLogs() async throws {
        try await MainActor.run {
            let fixture = try makeManager()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let manager = fixture.manager
            let frame = statusFrame(mode: 1, lever: 1)
            manager.parseProtocolResponse(frame)
            let logCount = manager.logStore.entries.count
            var publications = 0
            let subscription = manager.objectWillChange.sink { publications += 1 }
            for _ in 0..<100 { manager.parseProtocolResponse(frame) }
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(manager.logStore.entries.count, logCount)
            XCTAssertEqual(manager.batteryLevel, 80)
            XCTAssertEqual(manager.workMode, 1)
            XCTAssertEqual(manager.switchState, 1)
            XCTAssertEqual(manager.supportsConfigurableLighting, true)

            manager.parseProtocolResponse(statusFrame(mode: 2, lever: 0))
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(manager.workMode, 2)
            XCTAssertEqual(manager.switchState, 0)
            withExtendedLifetime(subscription) {}
        }
    }

    func testLogsAndDiagnosticsDoNotInvalidateTheStudioManager() async throws {
        try await MainActor.run {
            let fixture = try makeManager()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let manager = fixture.manager
            var publications = 0
            let subscription = manager.objectWillChange.sink { publications += 1 }
            manager.appendCommLogLine("test diagnostic")
            manager.diagnosticsStore.snapshot.signalStrength = -60
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(manager.logStore.entries.count, 1)
            XCTAssertEqual(manager.signalStrength, -60)
            withExtendedLifetime(subscription) {}
        }
    }

    private func statusFrame(mode: UInt8, lever: UInt8) -> Data {
        Data([0xAA, 0xBB, 0x00, 80, 0, 1, 2, mode, 1, lever, 35, 0xCC, 0xDD])
    }

    func testAgentHandoffRejectsConnectionCallbacksAfterAnotherOwnerAcquiresLock() async throws {
        try await MainActor.run {
            let fixture = try makeManager()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            XCTAssertFalse(fixture.manager.acceptsConnectionCallbacks)
            XCTAssertTrue(fixture.lock.acquire())
            XCTAssertTrue(fixture.manager.acceptsConnectionCallbacks)
            fixture.manager.setSuppressedForAgentOwningKeyboard(true)
            XCTAssertFalse(fixture.manager.acceptsConnectionCallbacks)
            let nextOwner = BLEConnectionLock(lockURL: fixture.directory.appendingPathComponent("owner.lock"))
            XCTAssertTrue(nextOwner.acquire())
            // A queued discovery cannot attach merely because the GUI's flag changes back.
            fixture.manager.setSuppressedForAgentOwningKeyboard(false)
            XCTAssertFalse(fixture.manager.acceptsConnectionCallbacks)
            nextOwner.release()
        }
    }

    func testDirectoryReplacementReattachesMonitorAndReceivesLaterAtomicWrites() async throws {
        let fixture = try await MainActor.run { try makeManager() }
        let stateDirectory = fixture.directory.appendingPathComponent("state")
        let stateFile = stateDirectory.appendingPathComponent("current-ide-state.json")
        let received = expectation(description: "new directory state is consumed")
        received.assertForOverFulfill = false
        let subscription = await MainActor.run {
            fixture.manager.startIDEStateMonitoring()
            return fixture.manager.$agentSwitchState.sink { value in
                if value == 1 { received.fulfill() }
            }
        }
        try FileManager.default.moveItem(at: stateDirectory, to: fixture.directory.appendingPathComponent("old-state"))
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try Data("{\"switchState\":1,\"lightMode\":1,\"workMode\":1}".utf8).write(to: stateFile, options: .atomic)
        await fulfillment(of: [received], timeout: 3)

        // A second event proves the source follows the new inode, rather than just reading once.
        let updated = expectation(description: "subsequent atomic write is consumed")
        updated.assertForOverFulfill = false
        let nextSubscription = await MainActor.run {
            fixture.manager.$agentSwitchState.sink { value in
                if value == 0 { updated.fulfill() }
            }
        }
        try Data("{\"switchState\":0,\"lightMode\":1,\"workMode\":1}".utf8).write(to: stateFile, options: .atomic)
        await fulfillment(of: [updated], timeout: 3)
        await MainActor.run {
            fixture.manager.stopIDEStateMonitoring()
            subscription.cancel()
            nextSubscription.cancel()
        }
        try FileManager.default.removeItem(at: fixture.directory)
    }

    @MainActor
    private func makeManager() throws -> (manager: AhaKeyBLEManager, directory: URL, lock: BLEConnectionLock) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logs = BLELogStore(
            verboseLogFileURL: directory.appendingPathComponent("verbose.log"),
            persistentLogFileURL: directory.appendingPathComponent("persistent.log")
        )
        let lock = BLEConnectionLock(lockURL: directory.appendingPathComponent("owner.lock"))
        let manager = AhaKeyBLEManager(
            startServices: false, logStore: logs,
            connectionLock: lock, ideStateDirectoryURL: directory.appendingPathComponent("state")
        )
        return (manager, directory, lock)
    }
}
