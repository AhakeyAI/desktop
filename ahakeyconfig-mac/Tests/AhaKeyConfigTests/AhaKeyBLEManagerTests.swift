import CoreBluetooth
import XCTest
@testable import AhaKeyConfig

final class AhaKeyBLEManagerTests: XCTestCase {
    func testBluetoothAuthorizationRequiresExplicitGrant() {
        XCTAssertFalse(AhaKeyBLEManager.isBluetoothAuthorizationGranted(.notDetermined))
        XCTAssertFalse(AhaKeyBLEManager.isBluetoothAuthorizationGranted(.restricted))
        XCTAssertFalse(AhaKeyBLEManager.isBluetoothAuthorizationGranted(.denied))
        XCTAssertTrue(AhaKeyBLEManager.isBluetoothAuthorizationGranted(.allowedAlways))
    }

    func testDeviceNameValidationRejectsEmptyAndOverlongNames() {
        XCTAssertEqual(AhaKeyCommand.validateDeviceName(""), .failure(.empty))
        XCTAssertEqual(AhaKeyCommand.validateDeviceName(" \n\t "), .failure(.empty))
        XCTAssertEqual(AhaKeyCommand.validateDeviceName("  AhaKey 507C "), .success("AhaKey 507C"))
        XCTAssertEqual(AhaKeyCommand.validateDeviceName(String(repeating: "a", count: 15)), .success(String(repeating: "a", count: 15)))
        XCTAssertEqual(AhaKeyCommand.validateDeviceName(String(repeating: "a", count: 16)), .failure(.tooLong(byteCount: 16)))
        // 中文按 UTF-8 计 3 字节：5 个字 = 15 字节可用，6 个字 = 18 字节拒绝（不再截断半个字符）。
        XCTAssertEqual(AhaKeyCommand.validateDeviceName("我的小键盘"), .success("我的小键盘"))
        XCTAssertEqual(AhaKeyCommand.validateDeviceName("我的小键盘呀"), .failure(.tooLong(byteCount: 18)))
        XCTAssertEqual(
            AhaKeyCommand.changeName("AhaKey"),
            Data([0xAA, 0xBB, 0x01] + Array("AhaKey".utf8) + [0xCC, 0xDD])
        )
    }

    func testLegacyStatusDoesNotAdvertiseConfigurableLighting() throws {
        let legacy = Data([
            0xAA, 0xBB, 0x00,
            74, 50, 1, 0, 0, 2, 1, 0,
            0xCC, 0xDD,
        ])
        let status = try XCTUnwrap(AhaKeyResponseParser.parseDeviceStatus(legacy))

        XCTAssertEqual(status.brightness, 0)
        XCTAssertFalse(AhaKeyBLEManager.statusAdvertisesConfigurableLighting(brightness: status.brightness))
    }

    func testModernStatusAdvertisesConfigurableLighting() throws {
        let modern = Data([
            0xAA, 0xBB, 0x00,
            74, 50, 1, 0, 0, 12, 1, 35,
            0xCC, 0xDD,
        ])
        let status = try XCTUnwrap(AhaKeyResponseParser.parseDeviceStatus(modern))

        XCTAssertEqual(status.lightMode, 12)
        XCTAssertEqual(status.brightness, 35)
        XCTAssertTrue(AhaKeyBLEManager.statusAdvertisesConfigurableLighting(brightness: status.brightness))
    }

    func testLightingCommandsMatchFirmwareProtocol() {
        XCTAssertEqual(
            AhaKeyCommand.setLightMapping(mode: 2, stateEffects: Array(7...15)),
            Data([0xAA, 0xBB, 0x84, 2, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0xCC, 0xDD])
        )
        XCTAssertEqual(AhaKeyCommand.setBrightness(0), Data([0xAA, 0xBB, 0x85, 1, 0xCC, 0xDD]))
        XCTAssertEqual(AhaKeyCommand.previewLightEffect(16), Data([0xAA, 0xBB, 0x91, 16, 0xCC, 0xDD]))
        XCTAssertEqual(AhaKeyCommand.saveConfig(), Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]))
    }

    func testShortLegacyStatusDoesNotAssumeBrightnessSupport() throws {
        let legacy = Data([0xAA, 0xBB, 0x00, 74, 50, 1, 0, 0, 2, 1, 0xCC, 0xDD])
        let status = try XCTUnwrap(AhaKeyResponseParser.parseDeviceStatus(legacy))
        XCTAssertEqual(status.brightness, 0)
        XCTAssertFalse(AhaKeyBLEManager.statusAdvertisesConfigurableLighting(brightness: status.brightness))
    }

    func testCP4DReadOnlyQueriesMatchAcceptedContract() {
        XCTAssertEqual(AhaKeyCommand.queryFirmwareCatalog(), Data([0xAA, 0xBB, 0x9F, 0xCC, 0xDD]))
        XCTAssertEqual(AhaKeyCommand.queryOrdinaryKey(mode: 3, keyIndex: 0),
                       Data([0xAA, 0xBB, 0x87, 3, 0, 0xCC, 0xDD]))
        XCTAssertNil(AhaKeyCommand.queryOrdinaryKey(mode: 4, keyIndex: 0))
        XCTAssertNil(AhaKeyCommand.queryOrdinaryKey(mode: 0, keyIndex: 4))
        XCTAssertEqual(AhaKeyCommand.queryStandby(), Data([0xAA, 0xBB, 0x95, 0xCC, 0xDD]))
        XCTAssertEqual(AhaKeyCommand.queryVoiceOnboarding(), Data([0xAA, 0xBB, 0x96, 0xCC, 0xDD]))
        XCTAssertEqual(AhaKeyCommand.querySideSwitch(), Data([0xAA, 0xBB, 0x97, 0xCC, 0xDD]))
    }

    @MainActor
    func testOLEDChunkTimeoutIsRetriedUntilSuccess() async throws {
        var attempts: [Int] = []
        var retries: [Int] = []
        try await AhaKeyBLEManager.retryingOLEDTimeouts(
            maxAttempts: 3,
            canRetry: { true },
            onRetry: { next, _ in retries.append(next) }
        ) { attempt in
            attempts.append(attempt)
            if attempt < 3 { throw OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult) }
        }
        XCTAssertEqual(attempts, [1, 2, 3])
        XCTAssertEqual(retries, [2, 3])
    }

    @MainActor
    func testOLEDChunkRetryStopsOnRejectionDisconnectOrLimit() async {
        var attempts = 0
        do {
            try await AhaKeyBLEManager.retryingOLEDTimeouts(maxAttempts: 3, canRetry: { true }, onRetry: { _, _ in }) { _ in
                attempts += 1
                throw OLEDUploadError.deviceRejected(command: AhaKeyCommand.cmdWriteResult, status: 1)
            }
            XCTFail("expected rejection")
        } catch {}
        XCTAssertEqual(attempts, 1)

        attempts = 0
        do {
            try await AhaKeyBLEManager.retryingOLEDTimeouts(maxAttempts: 3, canRetry: { false }, onRetry: { _, _ in }) { _ in
                attempts += 1
                throw OLEDUploadError.timeout(command: AhaKeyCommand.cmdPrepareWrite)
            }
            XCTFail("expected timeout")
        } catch {}
        XCTAssertEqual(attempts, 1)

        attempts = 0
        do {
            try await AhaKeyBLEManager.retryingOLEDTimeouts(maxAttempts: 3, canRetry: { true }, onRetry: { _, _ in }) { _ in
                attempts += 1
                throw OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult)
            }
            XCTFail("expected timeout")
        } catch {}
        XCTAssertEqual(attempts, 3)
    }

    func testOLEDTransferFailureNamesStagePositionAndRetry() {
        let error = OLEDUploadError.transferFailed(
            stage: .dataWrite, mode: 1,
            frame: 3, totalFrames: 12,
            chunk: 2, totalChunks: 7,
            attempts: 3, reason: OLEDUploadError.timeout(command: AhaKeyCommand.cmdWriteResult).localizedDescription
        )
        let message = error.localizedDescription
        XCTAssertTrue(message.contains("数据写入确认（0x81）"), message)
        XCTAssertTrue(message.contains("第 3/12 帧、第 2/7 块"), message)
        XCTAssertTrue(message.contains("已自动重试 2 次"), message)
        XCTAssertTrue(message.contains("等待设备响应超时: 0x81"), message)
        XCTAssertTrue(message.contains("重新写入"), message)
    }
}
