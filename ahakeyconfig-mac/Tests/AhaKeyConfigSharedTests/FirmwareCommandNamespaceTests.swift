import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class FirmwareCommandNamespaceTests: XCTestCase {
    func testAllCommandBytesKeepSDKAndFactoryOutOfConfigurationTransport() {
        let profiles: [FirmwareCapabilityProfile?] = [nil, .legacyAfterStatusReadback(),
            .catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))]
        let grants: [ConfigurationCommandPolicy.ConfirmedWrite] = [.none, .mode, .standby, .sideSwitch, .ordinaryKey,
            .voiceHandoff, .ws3Display, .ws3Resource, .ws3ResourceRestore, .ws3Presentation]
        for raw in 0...255 {
            let command = UInt8(raw)
            let expected: FirmwareCommandNamespace = raw <= 0x9F ? .official : (raw <= 0xEF ? .userSDK : .systemFactory)
            XCTAssertEqual(FirmwareCommandNamespace(command: command), expected)
            if raw >= 0xA0 {
                for profile in profiles {
                    for grant in grants {
                        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, command, 0xCC, 0xDD]),
                            profile: profile, confirmedWrite: grant, ws3DisplayReadbackVerified: true))
                    }
                }
            }
        }
    }
    func testPresentationWritesNeedCurrentDisplayProofAndExactShape() {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let mode = WS3PresentationCommand.setMode(.multi).request!
        XCTAssertFalse(ConfigurationCommandPolicy.permits(mode, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(mode, profile: profile, confirmedWrite: .ws3Presentation))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(mode, profile: profile, confirmedWrite: .ws3Presentation, ws3DisplayReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x98, 9, 0xCC, 0xDD]), profile: profile, confirmedWrite: .ws3Presentation, ws3DisplayReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x99, 0xCC, 0xDD]), profile: profile, confirmedWrite: .ws3Presentation, ws3DisplayReadbackVerified: true))
    }
    func testLegacyOfficialCompatibilityAndUnknownReadOnlyProbesRemain() {
        XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: .legacyAfterStatusReadback()))
        for command: UInt8 in [0x00, 0x9F] {
            XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, command, 0xCC, 0xDD]), profile: nil))
        }
        for command: UInt8 in [0x04, 0x73, 0x8D, 0x8F, 0x92, 0x98, 0x99, 0x9A] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, command, 0xCC, 0xDD]), profile: nil))
        }
    }
}
