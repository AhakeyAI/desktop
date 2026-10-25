import XCTest
@testable import AhaKeyConfigShared

final class K1OutputRouteProtocolTests: XCTestCase {
    private let nonce: UInt32 = 0x04030201
    private func reply(_ sub: UInt8, _ fields: [UInt8], status: UInt8 = 0) -> Data {
        Data([0xAA, 0xBB, 0x9E, status, 1, sub] + fields + [0xCC, 0xDD])
    }
    func testConsumerVoiceAndOrdinaryRoutesFollowFirmwareRecordValidation() throws {
        let voice = try XCTUnwrap(K1OutputRoute(kind: .consumer, action: Data([0xCF, 0])))
        XCTAssertEqual(Array(voice.serialized.prefix(4)), [1, 2, 0xCF, 0])
        XCTAssertEqual(voice.serialized.count, 102)
        XCTAssertEqual(K1OutputRoute(serialized: voice.serialized), voice)
        XCTAssertNotNil(K1OutputRoute(kind: .ordinary, action: Data([0x73, 1, 0x6D]))) // F18
        XCTAssertNotNil(K1OutputRoute(kind: .ordinary, action: Data())) // Disabled K1
        XCTAssertNil(K1OutputRoute(kind: .consumer, action: Data([0, 0])))
        XCTAssertNil(K1OutputRoute(kind: .consumer, action: Data([0, 4])))
        XCTAssertNil(K1OutputRoute(kind: .ordinary, action: Data([0x73, 2, 0x6D])))
        var dirty = voice.serialized; dirty[101] = 1
        XCTAssertNil(K1OutputRoute(serialized: dirty))
    }
    func testCapabilityRequiresExactChallengeAndRejectsLegacyAck() {
        let command = K1OutputRouteCommand.capability(nonce: nonce)
        XCTAssertEqual(command.request, Data([0xAA, 0xBB, 0x9E, 1, 0, 1, 2, 3, 4, 0xCC, 0xDD]))
        let valid = reply(0, [1, 2, 3, 4, 3, 4])
        XCTAssertEqual(K1OutputRouteReply.parse(valid, for: command), .capability)
        XCTAssertNil(K1OutputRouteReply.parse(Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]), for: command))
        for index in [3, 4, 5, 6, 10, 11] {
            var changed = valid; changed[index] ^= 0x80
            XCTAssertNil(K1OutputRouteReply.parse(changed, for: command))
        }
        for length in 0..<valid.count { XCTAssertNil(K1OutputRouteReply.parse(valid.prefix(length), for: command)) }
    }
    func testRouteSliceChecksModeOffsetLengthAndWholeRecordCRCIdentity() {
        let command = K1OutputRouteCommand.read(nonce: nonce, mode: 2, offset: 84, count: 18)
        let bytes = Array(repeating: UInt8(0), count: 18)
        let frame = reply(0x10, [1, 2, 3, 4, 2, 84, 102, 0, 0x78, 0x56, 0x34, 0x12] + bytes)
        XCTAssertEqual(K1OutputRouteReply.parse(frame, for: command), .slice(checksum: 0x12345678, bytes: Data(bytes)))
        XCTAssertNil(K1OutputRouteReply.parse(frame, for: .read(nonce: nonce, mode: 1, offset: 84, count: 18)))
        XCTAssertNil(K1OutputRouteCommand.read(nonce: nonce, mode: 2, offset: 85, count: 18).request)
        XCTAssertNil(K1OutputRouteCommand.read(nonce: nonce, mode: 2, offset: 0, count: 43).request)
    }
    func testBeginUsesFirmwareFieldOrderAndRetainsResumeOffset() {
        let command = K1OutputRouteCommand.begin(nonce: nonce, selector: 2, length: 102, checksum: 0x12345678)
        XCTAssertEqual(command.request, Data([0xAA, 0xBB, 0x9E, 1, 0x20, 2, 102, 0, 0x78, 0x56, 0x34, 0x12, 1, 2, 3, 4, 0xCC, 0xDD]))
        XCTAssertEqual(K1OutputRouteReply.parse(reply(0x20, [1, 2, 3, 4, 1, 2, 3, 4, 47, 0]), for: command), .begun(nextOffset: 47))
        XCTAssertNil(K1OutputRouteCommand.begin(nonce: nonce, selector: 0xFF, length: 102, checksum: 0).request)
        XCTAssertNil(K1OutputRouteCommand.begin(nonce: 0, selector: 0, length: 102, checksum: 0).request)
    }
    func testChunkFits62ByteEnvelopeAndOnlyAdvancesOnExactAck() throws {
        let command = K1OutputRouteCommand.chunk(token: nonce, selector: 2, offset: 47, bytes: Data(repeating: 7, count: 47))
        XCTAssertEqual(try XCTUnwrap(command.request).count, 62)
        let ack = reply(0x21, [1, 2, 3, 4, 2, 94, 0, 47])
        XCTAssertEqual(K1OutputRouteReply.parse(ack, for: command), .chunkAccepted(nextOffset: 94))
        var gap = ack; gap[11] = 95
        XCTAssertNil(K1OutputRouteReply.parse(gap, for: command))
        XCTAssertNil(K1OutputRouteCommand.chunk(token: nonce, selector: 2, offset: 94, bytes: Data(repeating: 7, count: 9)).request)
    }
    func testCommitChecksSelectorAndExposesChecksumForReadbackVerification() {
        let command = K1OutputRouteCommand.commit(token: nonce, selector: 2)
        let ack = reply(0x22, [1, 2, 3, 4, 2, 0x78, 0x56, 0x34, 0x12])
        XCTAssertEqual(K1OutputRouteReply.parse(ack, for: command), .committed(checksum: 0x12345678))
        XCTAssertNil(K1OutputRouteReply.parse(ack, for: .commit(token: nonce, selector: 3)))
        XCTAssertEqual(K1OutputRouteReply.parse(reply(0x22, [1, 2, 3, 4], status: 1), for: command), .rejected)
    }
    func testRestoreHandledDoesNotMeanCompleteAndRefusalRetainsActualState() {
        let command = K1OutputRouteCommand.startRestore(nonce: nonce)
        XCTAssertEqual(K1OutputRouteReply.parse(reply(0x31, [1, 2, 3, 4, 1, 5, 0, 0, 0]), for: command),
                       .restore(handled: true, state: .inProgress, attempt: 5))
        XCTAssertEqual(K1OutputRouteReply.parse(reply(0x31, [1, 2, 3, 4, 2, 5, 0, 0, 0], status: 1), for: command),
                       .restore(handled: false, state: .incomplete, attempt: 5))
        XCTAssertNil(K1OutputRouteReply.parse(reply(0x31, [1, 2, 3, 4, 6, 5, 0, 0, 0]), for: command))
        XCTAssertNil(K1OutputRouteReply.parse(reply(0x31, [1, 2, 3, 4, 3, 5, 0, 0, 0]), for: .restoreStatus(nonce: nonce)))
    }
}
