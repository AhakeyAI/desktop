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
}
