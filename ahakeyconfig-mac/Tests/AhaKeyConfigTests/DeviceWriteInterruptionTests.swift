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
    func testSupersededCommandDoesNotClearNewWaiter() async throws {
        let fixture = try makeManager()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let manager = fixture.manager
        let firstStarted = expectation(description: "first command registered")
        let first = Task { @MainActor in
            try await manager.awaitProtocolResponse(expectedCommand: 0x04, timeoutSeconds: 0.05) {
                firstStarted.fulfill()
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        let secondStarted = expectation(description: "second command registered")
        let second = Task { @MainActor in
            try await manager.awaitProtocolResponse(expectedCommand: 0x04, timeoutSeconds: 1) {
                secondStarted.fulfill()
            }
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("first command must be superseded")
        } catch OLEDUploadError.superseded(let command) { XCTAssertEqual(command, 0x04) }
        try await Task.sleep(nanoseconds: 100_000_000)
        manager.parseProtocolResponse(Data([0xAA, 0xBB, 0x04, 0x00, 0xCC, 0xDD]))
        let response = try await second.value
        XCTAssertEqual(response.status, 0)
    }

    @MainActor
    func testDisconnectEndsRegisteredCommandImmediately() async throws {
        let fixture = try makeManager()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let start = Date()
        do {
            _ = try await fixture.manager.awaitProtocolResponse(expectedCommand: 0x04, timeoutSeconds: 5) {
                fixture.manager.failPendingDeviceOperations()
            }
            XCTFail("expected disconnected")
        } catch OLEDUploadError.disconnected {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    @MainActor
    func testCancelledCommandDoesNotWaitForTimeout() async throws {
        let fixture = try makeManager()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let started = expectation(description: "command registered")
        let task = Task { @MainActor in
            try await fixture.manager.awaitProtocolResponse(expectedCommand: 0x04, timeoutSeconds: 5) {
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let start = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
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
