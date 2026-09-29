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

    @MainActor
    private func makeManager() throws -> (manager: AhaKeyBLEManager, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logs = BLELogStore(
            verboseLogFileURL: directory.appendingPathComponent("verbose.log"),
            persistentLogFileURL: directory.appendingPathComponent("persistent.log")
        )
        let manager = AhaKeyBLEManager(
            startServices: false, logStore: logs,
            connectionLock: BLEConnectionLock(lockURL: directory.appendingPathComponent("owner.lock"))
        )
        return (manager, directory)
    }
}
