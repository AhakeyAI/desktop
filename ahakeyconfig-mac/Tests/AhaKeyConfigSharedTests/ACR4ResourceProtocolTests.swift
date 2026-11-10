import XCTest
@testable import AhaKeyConfigShared

final class ACR4ResourceProtocolTests: XCTestCase {
    private func reply(_ command: ACR4Command, status: UInt8 = 0, fields: Data) -> Data {
        var data = Data([0xAA, 0xBB, 0x9E, status, 4, command.operation.rawValue, UInt8(fields.count)])
        data.append(ACR4Command.le(command.token)); data.append(fields); data.append(contentsOf: [0xCC, 0xDD]); return data
    }

    func testTwelveFrameGoldenMatchesFrozenPythonReferenceWithoutDroppingPixels() throws {
        let colors: [[UInt8]] = [[0xF8, 0], [7, 0xE0], [0, 0x1F], [0xFF, 0xFF]]
        let frames = (0..<12).map { index -> Data in
            var frame = Data()
            for y in 0..<80 { for _ in 0..<160 { frame.append(contentsOf: colors[(y / 10 + index) % 4]) } }
            return frame
        }
        let payload = try WS3ResourcePayload(entryID: 15, frames: frames)
        let object = ACR4ResourceObject(payload: payload)
        // Independent upstream reference tool, archived CA240DC1/pattern12.cp2.
        XCTAssertEqual(object.bytes.count, 3784)
        XCTAssertEqual(object.expandedBytes, 344064)
        XCTAssertEqual(object.expandedCRC, 2931802504)
        XCTAssertEqual(WS3ResourcePayload.checksum(object.bytes), 2622512252)
        XCTAssertEqual(object.frames, 12)
        let raw = ACR4ResourceObject(payload: payload, forceRaw: true)
        XCTAssertEqual(raw.bytes.count, 307240)
        XCTAssertEqual(raw.expandedCRC, object.expandedCRC)
        XCTAssertEqual(raw.bytes[4], 1); XCTAssertEqual(object.bytes[4], 3)
        for i in 0..<12 {
            let start = 16 + i * 25602
            XCTAssertEqual(raw.bytes.subdata(in: (start+2)..<(start+25602)), frames[i])
        }
        XCTAssertNotEqual(object.expandedCRC, payload.crc32, "AT03 descriptor participates in the expanded checksum")
    }

    func testCapabilityIsBoundToVersionTokenShapeAndAllRequiredFlags() throws {
        let command = ACR4Command(.caps, token: 0xDDCCBBAA)
        let fields = Data(Array("ACR4".utf8) + [15, 0]) + ACR4Command.le(307240) + Data([128, 1, 8, 12])
        let frame = reply(command, fields: fields)
        XCTAssertEqual(ACR4Reply(frame: frame, command: command)?.capabilityChunk, 128)
        for offset in [4, 5, 6, 7, 10] {
            var corrupt = frame; corrupt[offset] ^= 1
            XCTAssertNil(ACR4Reply(frame: corrupt, command: command))
        }
        for offset in [0, 4, 6, 10, 11, 12, 13] {
            var corrupt = fields; corrupt[offset] ^= 1
            XCTAssertNil(ACR4Reply(frame: reply(command, fields: corrupt), command: command)?.capabilityChunk)
        }
        XCTAssertNil(K1OutputRouteCommand(request: command.request))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: command.request, expectedCommand: 0x9E, response: frame))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: command.request, expectedCommand: 0x9E,
            response: reply(ACR4Command(.caps, token: 7), fields: fields)))
    }

    func testNotificationFragmentsUseLengthEvenWhenTokenAndCRCContainTrailers() {
        let command = ACR4Command(.metadata, token: 0xDDCCBBAA, fields: Data([18]))
        let fields = Data([2, 1]) + ACR4Command.le(28672) + Data([0xAA, 0xBB, 0xCC, 0xDD])
        let frame = reply(command, fields: fields)
        for split in 1..<frame.count {
            var decoder = DeviceNotificationFramer(); decoder.expectResponse(to: command.request)
            var result = decoder.append(Data(frame.prefix(split)), at: 1)
            result += decoder.append(Data(frame.dropFirst(split)), at: 1.1)
            XCTAssertEqual(result, [frame], "split \(split)")
        }
        var decoder = DeviceFrameDecoder(); decoder.expectResponse(to: command.request)
        XCTAssertEqual(decoder.append(frame + frame), [frame, frame])
        XCTAssertEqual(ACR4Reply(frame: frame, command: command)?.resource(entry: 18)?.crc32, 0xDDCCBBAA)
    }

    func testCommandBoundsAndVersionSeparation() throws {
        let object = ACR4ResourceObject(payload: try WS3ResourcePayload(entryID: 0, frames: [Data(count: 25600)]))
        let begin = ACR4Command(.begin, token: 1, fields: Data([0]) + ACR4Command.le(UInt32(object.bytes.count)) +
            ACR4Command.le(WS3ResourcePayload.checksum(object.bytes)) + object.bytes.prefix(16))
        XCTAssertEqual(ACR4Command(request: begin.request), begin)
        var wrong = begin.request; wrong[25] = 9 // frame count exceeds the default slot's eight-frame limit
        XCTAssertNil(ACR4Command(request: wrong))
        for version: UInt8 in [1, 2, 3, 5] {
            var data = begin.request; data[3] = version; XCTAssertNil(ACR4Command(request: data))
        }
        let chunk = ACR4Command(.chunk, token: 1, fields: ACR4Command.le(16) + Data([128]) + Data(count: 128))
        XCTAssertEqual(chunk.request.count, 145)
        XCTAssertNotNil(ACR4Command(request: chunk.request))
        var bad = chunk.request; bad[14] = 127; XCTAssertNil(ACR4Command(request: bad))
        XCTAssertNil(ACR4Command(request: ACR4Command(.caps, token: 0).request))
        XCTAssertNil(ACR4Command(request: ACR4Command(.metadata, token: 1, fields: Data([19])).request))
    }

    func testNegativeReplyIsCorrelatedAndCannotBecomeCapabilityOrValidMetadata() {
        let command = ACR4Command(.caps, token: 1)
        let frame = reply(command, status: 2, fields: ACR4Command.le(0))
        XCTAssertEqual(ACR4Reply(frame: frame, command: command)?.status, 2)
        XCTAssertNil(ACR4Reply(frame: frame, command: command)?.capabilityChunk)
        XCTAssertNil(ACR4Reply(frame: frame, command: command)?.resource(entry: 0))
        XCTAssertNil(ACR4Reply(frame: reply(command, status: 12, fields: ACR4Command.le(0)), command: command))
    }

    func testF99DUnknownVersionErrorIsOnlyNegativeCapabilityEvidence() {
        let command = ACR4Command(.caps, token: 0x12345678)
        // Production 5fc01cf command_k1_route_error(version, sub, read_u32(d+3)).
        let frame = Data([0xAA, 0xBB, 0x9E, 1, 4, 0x40, 0, 0x78, 0x56, 0x34, 0xCC, 0xDD])
        XCTAssertTrue(command.isLegacyUnsupportedReply(frame))
        XCTAssertNil(ACR4Reply(frame: frame, command: command))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: command.request, expectedCommand: 0x9E, response: frame))
        for split in 1..<frame.count {
            var decoder = DeviceNotificationFramer(); decoder.expectResponse(to: command.request)
            XCTAssertEqual(decoder.append(Data(frame.prefix(split)), at: 1) + decoder.append(Data(frame.dropFirst(split)), at: 1.1), [frame])
        }
        XCTAssertFalse(ACR4Command(.caps, token: 7).isLegacyUnsupportedReply(frame))
        XCTAssertFalse(ACR4Command(.commit, token: command.token).isLegacyUnsupportedReply(frame))
    }
}
