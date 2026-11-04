import XCTest
@testable import AhaKeyConfigShared

final class FirmwareIdentityDisplayTests: XCTestCase {
    func testOnlyFramedSuccessfulCatalogReplyCanSupplyAnIdentity() {
        let key = FirmwareCapabilityProfile.hw1SaveRepairCatalogKey
        let frame = Data([0xAA, 0xBB, 0x9F, 0]) + Data(key.utf8) + Data([0xCC, 0xDD])
        XCTAssertEqual(FirmwareIdentityDisplay.catalogKey(from: frame), key)
        for invalid in [Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD]),
                        Data([0xAA, 0xBB, 0x9F, 1]) + Data(key.utf8) + Data([0xCC, 0xDD]),
                        frame.dropLast(), Data([0xAA, 0xBB, 0x00, 0]) + Data(key.utf8) + Data([0xCC, 0xDD])] {
            XCTAssertNil(FirmwareIdentityDisplay.catalogKey(from: Data(invalid)))
        }
    }

    func testDisplayNeverGuessesAHexBuildOrVersionForUnknownKeyFormats() {
        XCTAssertEqual(FirmwareIdentityDisplay.label(catalogKey: FirmwareCapabilityProfile.hw1SaveRepairCatalogKey, statusVersion: "v1.0"), "1.0.1-r001")
        XCTAssertEqual(FirmwareIdentityDisplay.label(catalogKey: "future-device-contract", statusVersion: "v1.0"), "future-device-contract")
        for invalid in ["", "a\nb", "a b", String(repeating: "x", count: 129), "中文"] {
            XCTAssertEqual(FirmwareIdentityDisplay.label(catalogKey: invalid, statusVersion: "v1.0"), "v1.0")
        }
        XCTAssertNil(FirmwareIdentityDisplay.label(catalogKey: nil, statusVersion: nil))
        XCTAssertNil(FirmwareIdentityDisplay.validKey(true))
    }
}
