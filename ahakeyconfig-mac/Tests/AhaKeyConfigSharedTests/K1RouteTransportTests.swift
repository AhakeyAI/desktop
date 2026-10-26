import XCTest
@testable import AhaKeyConfigShared

final class K1RouteTransportTests: XCTestCase {
    private let profile = FirmwareCapabilityProfile(identity: .knownWS2Catalog)
    func testRequestDecodeRoundTripsEveryRegisteredSubcommandAndRejectsTruncation() throws {
        let commands: [K1OutputRouteCommand] = [.capability(nonce: 1), .read(nonce: 2, mode: 3, offset: 84, count: 18),
            .begin(nonce: 3, selector: 2, length: 102, checksum: 0x12345678),
            .chunk(token: 3, selector: 2, offset: 0, bytes: Data([1, 2, 3])), .commit(token: 3, selector: 2),
            .restoreStatus(nonce: 4), .startRestore(nonce: 5)]
        for command in commands {
            let request = try XCTUnwrap(command.request)
            XCTAssertEqual(K1OutputRouteCommand(request: request), command)
            for length in 0..<request.count { XCTAssertNil(K1OutputRouteCommand(request: request.prefix(length))) }
            var trailing = request; trailing.insert(0, at: trailing.count - 2)
            XCTAssertNil(K1OutputRouteCommand(request: trailing))
        }
    }
    func testOrdinaryCatalogNeverAloneAuthorizesNewRouteReadsOrWrites() throws {
        let begin = try XCTUnwrap(K1OutputRouteCommand.begin(nonce: 1, selector: 2, length: 102, checksum: 0).request)
        XCTAssertFalse(ConfigurationCommandPolicy.permits(begin, profile: profile, confirmedWrite: .k1Route))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(begin, profile: profile, k1RouteReadbackVerified: true))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(begin, profile: profile, confirmedWrite: .k1Route, k1RouteReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(begin, profile: .legacyAfterStatusReadback(), confirmedWrite: .k1Route, k1RouteReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(K1OutputRouteCommand.read(nonce: 1, mode: 0, offset: 0, count: 42).request!, profile: profile))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(K1OutputRouteCommand.capability(nonce: 1).request!, profile: profile))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(K1OutputRouteCommand.restoreStatus(nonce: 1).request!, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(K1OutputRouteCommand.startRestore(nonce: 1).request!, profile: profile, confirmedWrite: .k1Route, k1RouteReadbackVerified: true))
    }
    func testSliceFramingUsesRequestLengthDespiteEmbeddedMarkersAtEverySplit() throws {
        let command = K1OutputRouteCommand.read(nonce: 0x04030201, mode: 2, offset: 0, count: 42)
        let request = try XCTUnwrap(command.request)
        let pattern: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        let payload = Array(repeating: pattern, count: 11).flatMap { $0 }.prefix(42)
        var frame = Data([0xAA, 0xBB, 0x9E, 0, 1, 0x10, 1, 2, 3, 4, 2, 0, 102, 0, 0, 0, 0, 0])
        frame.append(contentsOf: payload); frame.append(contentsOf: [0xCC, 0xDD])
        XCTAssertEqual(frame.count, 62)
        for split in 1..<frame.count {
            var framer = DeviceNotificationFramer(); framer.expectResponse(to: request)
            XCTAssertTrue(framer.append(frame.prefix(split), at: 1).isEmpty)
            XCTAssertEqual(framer.append(frame.dropFirst(split), at: 1.1), [frame])
        }
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x9E, response: frame))
    }
    func testCorrelatedErrorFramesAndRestoreRefusalAreNotTruncatedIntoLegacyErrors() throws {
        let cases: [(K1OutputRouteCommand, Data)] = [
            (.commit(token: 0x04030201, selector: 2), Data([0xAA, 0xBB, 0x9E, 1, 1, 0x22, 1, 2, 3, 4, 0xCC, 0xDD])),
            (.restoreStatus(nonce: 0x04030201), Data([0xAA, 0xBB, 0x9E, 1, 1, 0x30, 1, 2, 3, 4, 4, 0, 0, 0, 0, 0xCC, 0xDD]))]
        for (command, frame) in cases {
            let request = try XCTUnwrap(command.request)
            var decoder = DeviceFrameDecoder(); decoder.expectResponse(to: request)
            XCTAssertTrue(decoder.append(frame.prefix(6)).isEmpty)
            XCTAssertEqual(decoder.append(frame.dropFirst(6)), [frame])
            XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x9E, response: frame))
            var stale = frame; stale[6] ^= 1
            XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x9E, response: stale))
        }
    }
    func testGenericACKCompletesOnlyCapabilityProbeAndNeverEstablishesSupport() throws {
        let frame = Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD])
        let probe = K1OutputRouteCommand.capability(nonce: 9)
        XCTAssertTrue(DeviceResponseMatcher.matches(request: probe.request!, expectedCommand: 0x9E, response: frame))
        XCTAssertNil(K1OutputRouteReply.parse(frame, for: probe))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: K1OutputRouteCommand.commit(token: 9, selector: 0).request!, expectedCommand: 0x9E, response: frame))
    }
    func testFourModeBootstrapNeedsItsOwnUnavailableRecordProofAndGrant() throws {
        let commands: [K1OutputRouteCommand] = [
            .begin(nonce: 1, selector: 0xFF, length: 408, checksum: 0),
            .chunk(token: 1, selector: 0xFF, offset: 0, bytes: Data([1])),
            .commit(token: 1, selector: 0xFF)
        ]
        for command in commands {
            let request = try XCTUnwrap(command.request)
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .k1Route,
                k1RouteReadbackVerified: true, k1InitializationReadbackVerified: true))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .k1Initialization,
                k1RouteReadbackVerified: true))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .k1Initialization,
                k1InitializationReadbackVerified: true))
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .k1Initialization,
                k1RouteReadbackVerified: true, k1InitializationReadbackVerified: true))
        }
        let single = try XCTUnwrap(K1OutputRouteCommand.commit(token: 1, selector: 0).request)
        XCTAssertFalse(ConfigurationCommandPolicy.permits(single, profile: profile, confirmedWrite: .k1Initialization,
            k1RouteReadbackVerified: true, k1InitializationReadbackVerified: true))
    }
}
