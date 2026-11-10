import XCTest
@testable import AhaKeyConfigShared

final class CompactResourceProtocolTests: XCTestCase {
    private func photographicPayload() throws -> WS3ResourcePayload {
        let frames = (0..<12).map { frame -> Data in
            var pixels = Data()
            for i in 0..<12800 {
                let color = UInt16(truncatingIfNeeded: i*37+frame*513)
                pixels.append(contentsOf: [UInt8(color >> 8), UInt8(color & 255)])
            }
            return pixels
        }
        return try WS3ResourcePayload(entryID: 15, frames: frames)
    }
    func testAutomaticSpatialCompressionKeepsAllTwelveFramesWithinBudget() throws {
        let payload = try photographicPayload(), original = payload.bytes
        let compact = CompactResourceObject(payload: payload)
        XCTAssertGreaterThan(ACR4ResourceObject(payload: payload).bytes.count, 50000)
        XCTAssertEqual(compact.frames, 12); XCTAssertEqual(compact.scale, 4)
        XCTAssertEqual(compact.width, 40); XCTAssertEqual(compact.height, 20)
        XCTAssertEqual(compact.bytes.count, 19240)
        // Independent Python struct/zlib golden: average RGB565 source blocks,
        // nearest-neighbour firmware expansion and AT03/100ms descriptors.
        XCTAssertEqual(WS3ResourcePayload.checksum(compact.bytes), 4144442838)
        XCTAssertEqual(compact.expandedCRC, 2775044983)
        XCTAssertEqual(payload.compactCRC32, compact.expandedCRC)
        XCTAssertEqual(compact.previewPixels.prefix(2), Data([0x1C, 0xE7]))
        XCTAssertEqual(payload.bytes, original)
        let metadata = WS3ResourceReadback(id: 15, basic: .resourceBasic(userValid: true, writeState: .valid),
            integrity: .resourceIntegrity(frames: 12, bytes: 344064, crc32: compact.expandedCRC))!
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: metadata), .matches)
    }

    func testSelectHighestResolutionWithoutDroppingAnimationFrames() throws {
        for (count, scale) in [(1, 1), (2, 2), (7, 2), (8, 4), (12, 4)] {
            let object = CompactResourceObject(payload: try WS3ResourcePayload(entryID: 15,
                frames: Array(repeating: Data(repeating: 0xFF, count: 25600), count: count)))
            XCTAssertEqual(object.frames, UInt16(count)); XCTAssertEqual(object.scale, scale)
            XCTAssertLessThanOrEqual(object.bytes.count, 50000)
            XCTAssertEqual(object.previewPixels, Data(repeating: 0xFF, count: 25600))
            let fields = Data([15]) + ACR4Command.le(UInt32(object.bytes.count)) +
                ACR4Command.le(WS3ResourcePayload.checksum(object.bytes)) + object.bytes.prefix(16)
            XCTAssertNotNil(CompactResourceCommand(request: CompactResourceCommand(.begin, token: 7, fields: fields).request))
            XCTAssertNil(ACR4Command(request: CompactResourceCommand(.begin, token: 7, fields: fields).request))
        }
    }

    func testNineByteChunkACKCannotBeMistakenForFiveByteACR4ACK() {
        let command = CompactResourceCommand(.chunk, token: 0xDDCCBBAA,
            fields: ACR4Command.le(16) + Data([1, 0]))
        let fields = ACR4Command.le(17) + Data([1]) + ACR4Command.le(0xDDCC)
        var frame = Data([0xAA, 0xBB, 0x9E, 0, 3, 0x42, 9])
        frame.append(ACR4Command.le(command.token)); frame.append(fields); frame.append(contentsOf: [0xCC, 0xDD])
        XCTAssertNotNil(CompactResourceReply(frame: frame, command: command))
        XCTAssertNil(ACR4Reply(frame: frame, command: ACR4Command(.chunk, token: command.token, fields: command.fields)))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: command.request, expectedCommand: 0x9E, response: frame))
        for split in 1..<frame.count {
            var decoder = DeviceNotificationFramer(); decoder.expectResponse(to: command.request)
            let first = decoder.append(Data(frame.prefix(split)), at: 1)
            XCTAssertEqual(first + decoder.append(Data(frame.dropFirst(split)), at: 1.1), [frame])
        }
        var truncated = frame; truncated[6] = 5; truncated.removeSubrange(16..<20)
        XCTAssertNil(CompactResourceReply(frame: truncated, command: command))
    }

    func testCompactWritesRequireTheirOwnProofAndCannotBorrowACR4Proof() throws {
        let command = CompactResourceCommand(.cancel, token: 1)
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(command.request, profile: profile, confirmedWrite: .negotiatedResource,
            ws3DisplayReadbackVerified: true, acr4ReadbackVerified: true))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(command.request, profile: profile, confirmedWrite: .negotiatedResource,
            ws3DisplayReadbackVerified: true, compactReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(command.request, profile: nil, confirmedWrite: .negotiatedResource,
            ws3DisplayReadbackVerified: true, compactReadbackVerified: true))
    }

    func testDerivedIntegrityIsSafeAcrossPreparationAndReadbackQueues() async throws {
        let payload = try photographicPayload()
        let checksums = await withTaskGroup(of: [UInt32].self) { group in
            for _ in 0..<12 { group.addTask { [payload.losslessCRC32, payload.compactCRC32] } }
            var results: [[UInt32]] = []
            for await value in group { results.append(value) }
            return results
        }
        XCTAssertEqual(checksums.count, 12)
        XCTAssertTrue(checksums.allSatisfy { $0 == checksums[0] })
        XCTAssertEqual(checksums[0][1], 2775044983)
        XCTAssertEqual(payload, try photographicPayload(), "Derived cache state must not change draft equality")
    }

    @MainActor
    func testLargeArtworkNegotiatesCompactAndLegacyFallbackNeverBegins() async throws {
        let payload = try photographicPayload()
        var versions: [UInt8] = []
        let selected = try await ConfirmedNegotiatedResourceUpload.prepare(payload: payload) { wire in
            versions.append(wire[3])
            let command = try XCTUnwrap(CompactResourceCommand(request: wire))
            let fields = Data(Array("ACR3".utf8) + [15, 0]) + ACR4Command.le(50000) + Data([128, 7, 8, 12])
            return Data([0xAA, 0xBB, 0x9E, 0, 3, 0x40, 14]) + ACR4Command.le(command.token) + fields + Data([0xCC, 0xDD])
        }
        XCTAssertEqual(selected?.object.format, .compact)
        XCTAssertLessThanOrEqual(selected?.object.bytes.count ?? Int.max, 50000)
        XCTAssertEqual(versions, [3])
        versions = []
        let small = try WS3ResourcePayload(entryID: 0, frames: [Data(count: 25600)])
        let unsupported = try await ConfirmedNegotiatedResourceUpload.prepare(payload: small) { wire in
            versions.append(wire[3]); XCTAssertEqual(wire[4], 0x40)
            return Data([0xAA, 0xBB, 0x9E, 1, wire[3], 0x40]) + wire.subdata(in: 5..<9) + Data([0xCC, 0xDD])
        }
        XCTAssertNil(unsupported); XCTAssertEqual(versions, [4, 3])
    }
}
