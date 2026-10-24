import AhaKeyConfigShared
import XCTest
@testable import AhaKeyConfig

/// AHK-061：图片数据块的 0x81 确认等待必须在超时 / 断线 / 设备回包任一路径上及时结束。
@MainActor
final class OLEDDataWriteResultTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingWriteResultTimesOutInsteadOfHanging() async {
        let manager = makeManager()
        let start = Date()

        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 0.2) {}
            XCTFail("expected timeout")
        } catch OLEDUploadError.timeout(let command) {
            XCTAssertEqual(command, AhaKeyCommand.cmdWriteResult)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testTimeoutStartsAfterPacketsAreHandedOff() async throws {
        let manager = makeManager()
        let ack = Data([0xAA, 0xBB, AhaKeyCommand.cmdWriteResult, 0x00, 0xCC, 0xDD])

        // 分包耗时 0.4s 大于 0.3s 的确认窗口；设备在分包完成后 0.1s 回 0x81，应判为成功。
        try await manager.awaitDataWriteResult(timeoutSeconds: 0.3) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                manager.parseProtocolResponse(ack)
            }
        }
    }

    func testDeviceRejectionIsReported() async {
        let manager = makeManager()
        let reject = Data([0xAA, 0xBB, AhaKeyCommand.cmdWriteResult, 0x02, 0xCC, 0xDD])

        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 5) {
                manager.parseProtocolResponse(reject)
            }
            XCTFail("expected rejection")
        } catch OLEDUploadError.deviceRejected(let command, let status) {
            XCTAssertEqual(command, AhaKeyCommand.cmdWriteResult)
            XCTAssertEqual(status, 0x02)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDisconnectFailsPendingWriteImmediately() async {
        let manager = makeManager()
        let start = Date()

        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 5) {
                manager.failPendingResponses(with: OLEDUploadError.deviceDisconnected)
            }
            XCTFail("expected disconnect")
        } catch OLEDUploadError.deviceDisconnected {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testLateWriteResultAfterTimeoutIsIgnored() async {
        let manager = makeManager()
        let ack = Data([0xAA, 0xBB, AhaKeyCommand.cmdWriteResult, 0x00, 0xCC, 0xDD])

        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 0.1) {}
            XCTFail("expected timeout")
        } catch {}
        manager.parseProtocolResponse(ack)
        manager.finishDataWrite(.success(()))
    }

    func testTimedOutConnectionRejectsRetryBeforeLateAckCanConfirmIt() async {
        let manager = makeManager()
        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 0.01) {}
            XCTFail("expected timeout")
        } catch {}
        XCTAssertTrue(manager.dataWriteRequiresReconnect)
        var sentRetry = false
        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 1) {
                sentRetry = true
                manager.parseProtocolResponse(Data([0xAA, 0xBB, 0x81, 0x00, 0xCC, 0xDD]))
            }
            XCTFail("must reconnect before retry")
        } catch OLEDUploadError.reconnectRequired {
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertFalse(sentRetry)
    }

    func testPacketSendFailureEndsWaitAndRequiresReconnect() async {
        let manager = makeManager()
        do {
            try await manager.awaitDataWriteResult(timeoutSeconds: 5) {
                throw OLEDUploadError.dataWriteFailed("stalled transport")
            }
            XCTFail("expected send failure")
        } catch OLEDUploadError.dataWriteFailed {
        } catch { XCTFail("unexpected error: \(error)") }
        XCTAssertTrue(manager.dataWriteRequiresReconnect)
    }

    func testWriteResultTimeoutMessageOffersRetry() {
        let message = OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult).errorDescription ?? ""
        XCTAssertTrue(message.contains("0x81"))
        XCTAssertTrue(message.contains("重新写入"))
        XCTAssertEqual(OLEDUploadError.timeout(command: 0x99).errorDescription, "等待设备响应超时: 0x99")
    }

    private func makeManager() -> AhaKeyBLEManager {
        AhaKeyBLEManager(
            startServices: false,
            logStore: BLELogStore(
                verboseLogFileURL: directory.appendingPathComponent("verbose.log"),
                persistentLogFileURL: directory.appendingPathComponent("persistent.log")
            ),
            connectionLock: BLEConnectionLock(lockURL: directory.appendingPathComponent("owner.lock")),
            ideStateDirectoryURL: directory.appendingPathComponent("state")
        )
    }
}
