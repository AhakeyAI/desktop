import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class FirmwareCapabilityProfileTests: XCTestCase {
    func testAcceptedCatalogEnablesOnlyVerifiedWS2Capabilities() {
        let frame = Data([0xAA, 0xBB, 0x9F, 0x00]
            + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.catalogResponse(frame)
        XCTAssertEqual(profile.identity, .knownWS2Catalog)
        XCTAssertTrue(profile.mayQueryOrdinaryKeys)
        XCTAssertFalse(profile.canWriteWithoutReadback)
        XCTAssertFalse(profile.canUseWS3Presentation)
        XCTAssertFalse(profile.canWriteWS3Resources)
    }

    func testUnknownCatalogDoesNotOpenWrites() {
        let frame = Data([0xAA, 0xBB, 0x9F, 0x00]
            + Array("x1-c582-hw1-p1-1.0.1-r002".utf8) + [0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.catalogResponse(frame)
        XCTAssertEqual(profile.identity, .unknown("x1-c582-hw1-p1-1.0.1-r002"))
        XCTAssertFalse(profile.canWriteWithoutReadback)
        XCTAssertFalse(profile.canWriteWS3Resources)
    }

    func testOnlyExactSuccessAckWithIndependentStatusOpensLegacyWrites() {
        let ack = Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.probeResponse(ack, hasValidStatusReadback: true)
        XCTAssertEqual(profile.identity, .legacy)
        XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: profile))
        let noStatus = FirmwareCapabilityProfile.probeResponse(ack, hasValidStatusReadback: false)
        XCTAssertEqual(noStatus.identity, .unknown(nil))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: noStatus))
    }

    func testAllCatalogErrorStatusesCannotEnableLegacyWritesOrAutoApproval() {
        let save = Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])
        for status: UInt8 in 1...255 {
            let error = Data([0xAA, 0xBB, 0x9F, status, 0xCC, 0xDD])
            let profile = FirmwareCapabilityProfile.probeResponse(error, hasValidStatusReadback: true)
            XCTAssertEqual(profile.identity, .unknown(nil), "status=\(status)")
            XCTAssertFalse(ConfigurationCommandPolicy.permits(save, profile: profile), "status=\(status)")
            XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: nil))
        }
    }

    func testMalformedOrWrongCommandAckAndMissingStatusRemainUnknown() {
        for frame in [Data(), Data([0xAA, 0xBB, 0x9F, 0, 0xCC]),
                      Data([0xAA, 0xBB, 0x95, 0, 0xCC, 0xDD]),
                      Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD, 0])] {
            XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: true).identity, .unknown(nil))
        }
        let known = Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD])
        XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(known, hasValidStatusReadback: false).identity, .unknown(nil))
        XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(known, hasValidStatusReadback: true).identity, .knownWS2Catalog)
    }

    func testLegacyIsOnlyAnExplicitFallback() {
        let error = Data([0xAA, 0xBB, 0x9F, 0x01, 0xCC, 0xDD])
        XCTAssertEqual(FirmwareCapabilityProfile.catalogResponse(error).identity, .unknown(nil))
        XCTAssertEqual(FirmwareCapabilityProfile.legacyAfterStatusReadback().identity, .legacy)
    }
}
