import XCTest
@testable import AhaKeyConfigShared

final class WS3PresentationProtocolTests: XCTestCase {
    func testModeSingleAndHeartbeatWireContracts() {
        XCTAssertEqual(WS3PresentationCommand.setMode(.single).request, Data([0xAA, 0xBB, 0x98, 0, 0xCC, 0xDD]))
        XCTAssertEqual(WS3PresentationCommand.setMode(.multi).request, Data([0xAA, 0xBB, 0x98, 1, 0xCC, 0xDD]))
        XCTAssertEqual(WS3PresentationCommand.single(state: 8).request, Data([0xAA, 0xBB, 0x90, 8, 0xCC, 0xDD]))
        XCTAssertNil(WS3PresentationCommand.single(state: 9).request)
        XCTAssertNil(WS3PresentationCommand.single(state: 255).request)
        XCTAssertEqual(WS3PresentationCommand.heartbeat.request, Data([0xAA, 0xBB, 0x9A, 0xCC, 0xDD]))
    }

    func testMultiAlwaysSendsVersionOneFullFourSlotTruth() throws {
        let snapshot = try XCTUnwrap(WS3TaskSnapshot(slots: [
            .init(state: .running), nil, .init(state: .waiting, foreground: true), .init(state: .done)
        ]))
        let frame = Data([0xAA, 0xBB, 0x99, 1, 1, 1, 0, 0, 0, 0, 1, 2, 1, 1, 3, 0, 0xCC, 0xDD])
        XCTAssertEqual(WS3PresentationCommand.multi(snapshot).request, frame)
        XCTAssertEqual(WS3TaskSnapshot(request: frame), snapshot)
        XCTAssertNil(WS3TaskSnapshot(slots: []))
        XCTAssertNil(WS3TaskSnapshot(slots: [nil, nil, nil]))
        XCTAssertNil(WS3TaskSnapshot(slots: [nil, nil, nil, nil, nil]))
    }

    func testAllEmptyAndMultipleForegroundRemainLegal() throws {
        let empty = try XCTUnwrap(WS3TaskSnapshot(slots: [nil, nil, nil, nil]))
        XCTAssertEqual(WS3TaskSnapshot(request: try XCTUnwrap(WS3PresentationCommand.multi(empty).request)), empty)
        let two = try XCTUnwrap(WS3TaskSnapshot(slots: [.init(state: .running, foreground: true),
            .init(state: .waiting, foreground: true), nil, nil]))
        XCTAssertEqual(WS3TaskSnapshot(request: try XCTUnwrap(WS3PresentationCommand.multi(two).request)), two)
    }

    func testRejectsLegacyPartialUnsupportedAndOutOfRangeSnapshots() {
        let empty: [UInt8] = [0xAA, 0xBB, 0x99, 1] + Array(repeating: 0, count: 12) + [0xCC, 0xDD]
        for (index, value): (Int, UInt8) in [(0, 0), (2, 0x98), (3, 2), (4, 2), (16, 0)] {
            var changed = empty; changed[index] = value
            XCTAssertNil(WS3TaskSnapshot(request: Data(changed)))
        }
        for (state, foreground): (UInt8, UInt8) in [(0, 0), (4, 0), (1, 2)] {
            var changed = empty; changed[4] = 1; changed[5] = state; changed[6] = foreground
            XCTAssertNil(WS3TaskSnapshot(request: Data(changed)))
        }
        XCTAssertNil(WS3TaskSnapshot(request: Data([0xAA, 0xBB, 0x99, 0, 1, 1, 0, 0xCC, 0xDD])))
        XCTAssertNil(WS3TaskSnapshot(request: Data(empty.dropLast())))
        XCTAssertNil(WS3TaskSnapshot(request: Data(empty + [0])))
    }

    func testEmptySlotIgnoresUnusedBytesAsFirmwareDoes() throws {
        var raw: [UInt8] = [0xAA, 0xBB, 0x99, 1] + Array(repeating: 0, count: 12) + [0xCC, 0xDD]
        raw[5] = 255; raw[6] = 255
        let snapshot = try XCTUnwrap(WS3TaskSnapshot(request: Data(raw)))
        XCTAssertEqual(snapshot.slots, [nil, nil, nil, nil])
        let canonical = try XCTUnwrap(WS3PresentationCommand.multi(snapshot).request)
        XCTAssertEqual(Array(canonical)[5...6], [0, 0])
    }

    func testAckOnlyReportsTransportReceiptNotPresentationOrLiveness() {
        let command = WS3PresentationCommand.heartbeat
        XCTAssertEqual(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x9A, 0, 0xCC, 0xDD]), for: command), .received)
        XCTAssertEqual(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x9A, 2, 0xCC, 0xDD]), for: command), .rejected(2))
        XCTAssertNil(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x98, 0, 0xCC, 0xDD]), for: command))
        XCTAssertNil(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x9A, 0, 0, 0xCC, 0xDD]), for: command))
        XCTAssertNil(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x9A, 0, 0xCC, 0xDD]), for: .single(state: 9)))
        // Firmware also returns OK for 0x99 ignored in SINGLE mode.
        XCTAssertEqual(WS3PresentationAcknowledgement.parse(Data([0xAA, 0xBB, 0x99, 0, 0xCC, 0xDD]),
            for: .multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!)), .received)
    }

    func testCodecDoesNotOpenProductionConfigurationWrites() throws {
        let snapshot = try XCTUnwrap(WS3TaskSnapshot(slots: [nil, nil, nil, nil]))
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]
            + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        XCTAssertEqual(known.identity, .knownWS2Catalog)
        XCTAssertFalse(known.canUseWS3Presentation)
        for command in [WS3PresentationCommand.setMode(.multi), .multi(snapshot), .heartbeat] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(try XCTUnwrap(command.request), profile: nil))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(try XCTUnwrap(command.request), profile: known))
        }
    }
}
