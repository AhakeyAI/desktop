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
