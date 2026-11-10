import XCTest
@testable import AhaKeyConfigShared

final class WS3CommandOwnershipTests: XCTestCase {
    func testBothCapabilityProbesCanReachMailboxBeforeAnyWriteProofExists() throws {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        for request in [ACR4Command(.caps, token: 123).request, CompactResourceCommand(.caps, token: 123).request] {
            // The native build576 failure: schema allowed this read, but the
            // display mailbox silently dropped the unowned request and timed out.
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile))
            XCTAssertFalse(WS3CommandOwnership.permits(request, uploading: true, updating: false, grant: .none))
            let grant = try XCTUnwrap(WS3CommandOwnership.negotiatedGrant(for: request))
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: grant))
            XCTAssertTrue(WS3CommandOwnership.permits(request, uploading: true, updating: false, grant: grant))
        }
    }
    func testOrdinaryQueuedWritesCannotPassDisplayOwnerOrBorrowResourceGrant() {
        let mode = Data([0xAA, 0xBB, 0x92, 3, 0xCC, 0xDD])
        XCTAssertNil(WS3CommandOwnership.negotiatedGrant(for: mode))
        XCTAssertFalse(WS3CommandOwnership.permits(mode, uploading: true, updating: false, grant: .mode))
        XCTAssertFalse(WS3CommandOwnership.permits(mode, uploading: false, updating: true, grant: .mode))
        XCTAssertTrue(WS3CommandOwnership.permits(mode, uploading: false, updating: false, grant: .mode))
        XCTAssertTrue(WS3CommandOwnership.permits(Data([0xAA, 0xBB, 0x88, 0, 0xCC, 0xDD]), uploading: true, updating: false, grant: .none))
    }
}
