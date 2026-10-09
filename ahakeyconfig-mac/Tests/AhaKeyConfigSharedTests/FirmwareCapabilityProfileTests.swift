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

    func testLegacyIsOnlyAnExplicitFallback() {
        let error = Data([0xAA, 0xBB, 0x9F, 0x01, 0xCC, 0xDD])
        XCTAssertEqual(FirmwareCapabilityProfile.catalogResponse(error).identity, .unknown(nil))
        XCTAssertEqual(FirmwareCapabilityProfile.legacyAfterStatusReadback().identity, .legacy)
    }
}
