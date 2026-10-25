import XCTest
@testable import AhaKeyConfigShared

final class RestoreTransportPolicyTests: XCTestCase {
    private let profile = FirmwareCapabilityProfile(identity: .knownWS2Catalog)
    func testOnlyDedicatedRestoreGrantAndFreshRestoreProofPermitStart() throws {
        let request = try XCTUnwrap(K1OutputRouteCommand.startRestore(nonce: 5).request)
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, restoreReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .restoreInitialization))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .k1Route,
            k1RouteReadbackVerified: true, restoreReadbackVerified: true))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .restoreInitialization,
            restoreReadbackVerified: true))
        for unsupported: FirmwareCapabilityProfile? in [nil, .legacyAfterStatusReadback()] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: unsupported,
                confirmedWrite: .restoreInitialization, restoreReadbackVerified: true))
        }
    }
    func testRestoreGrantCannotBeUsedForUnrelatedWrites() throws {
        let commands = [
            K1OutputRouteCommand.begin(nonce: 1, selector: 0, length: 102, checksum: 0).request!,
            Data([0xAA, 0xBB, 0x85, 35, 0xCC, 0xDD]), Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])
        ]
        for request in commands {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile,
                confirmedWrite: .restoreInitialization, k1RouteReadbackVerified: true,
                restoreReadbackVerified: true))
        }
    }
    func testLegacyRestoreStatusACKCompletesNegativeProbeButNeverProvesSupport() throws {
        let status = K1OutputRouteCommand.restoreStatus(nonce: 4)
        let request = try XCTUnwrap(status.request)
        for byte: UInt8 in [0, 1] {
            let ack = Data([0xAA, 0xBB, 0x9E, byte, 0xCC, 0xDD])
            for split in 1..<ack.count {
                var decoder = DeviceFrameDecoder()
                decoder.expectResponse(to: request)
                XCTAssertTrue(decoder.append(ack.prefix(split)).isEmpty)
                XCTAssertEqual(decoder.append(ack.dropFirst(split)), [ack])
            }
            XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x9E, response: ack))
            XCTAssertNil(K1OutputRouteReply.parse(ack, for: status))
            XCTAssertFalse(DeviceResponseMatcher.matches(
                request: K1OutputRouteCommand.startRestore(nonce: 4).request!, expectedCommand: 0x9E, response: ack))
        }
    }
}
