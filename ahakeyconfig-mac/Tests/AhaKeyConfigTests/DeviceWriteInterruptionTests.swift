import AhaKeyConfigShared
import XCTest
@testable import AhaKeyConfig

/// Issue #131：写入过程中断连后，等待设备回应的写入必须立即结束，界面才能退出「写入中」。
final class DeviceWriteInterruptionTests: XCTestCase {
    func testCommandWithoutChannelFailsImmediatelyInsteadOfWaitingForTimeout() async throws {
        let fixture = try await MainActor.run { try makeManager() }
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let start = Date()
        do {
            _ = try await fixture.manager.readPictureState(mode: 0)
            XCTFail("expected the read to fail without a BLE channel")
        } catch OLEDUploadError.disconnected {
            // 5 s protocol timeout would mean the write button stays in 「写入中」 after every disconnect.
            XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        }
    }

    func testFailingPendingOperationsWithNothingPendingIsSilent() async throws {
        try await MainActor.run {
            let fixture = try makeManager()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            fixture.manager.failPendingDeviceOperations()
            XCTAssertTrue(fixture.manager.logStore.entries.isEmpty)
        }
    }

    func testDisconnectFailureAsksForFullRewrite() {
        let interrupted = AhaKeyStudioView.deviceWriteFailureMessage(for: OLEDUploadError.disconnected)
        XCTAssertTrue(interrupted.hasPrefix("写入中断"))
        XCTAssertTrue(interrupted.contains("重新连接"))

        let timeout = AhaKeyStudioView.deviceWriteFailureMessage(for: OLEDUploadError.timeout(command: 0x04))
        XCTAssertTrue(timeout.hasPrefix("写入键盘失败"))
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
            connectionLock: BLEConnectionLock(lockURL: directory.appendingPathComponent("owner.lock")),
            ideStateDirectoryURL: directory.appendingPathComponent("state")
        )
        return (manager, directory)
    }
}
