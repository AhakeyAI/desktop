import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class WS3ResourceUploadTests: XCTestCase {
    private final class Firmware {
        let payload: WS3ResourcePayload
        var requests: [Data] = []
        var committed = false
        var reject: UInt8?
        var crcMismatch = false
        var epoch: UInt64 = 7
        var intercept: ((Data) throws -> Void)?
        init(_ payload: WS3ResourcePayload) { self.payload = payload }
        var baseline: WS3DisplaySnapshot {
            .init(generation: 7, brightness: 35, resources: (UInt8(0)..<19).map {
                WS3ResourceReadback(id: $0, basic: .resourceBasic(userValid: false, writeState: .empty),
                    integrity: .resourceIntegrity(frames: 0, bytes: 0, crc32: 0))!
            })
        }
        func exchange(_ request: Data) throws -> Data {
            requests.append(request)
            try intercept?(request)
            let b = [UInt8](request)
            if b[2] == reject { return Data([0xAA, 0xBB, b[2], 1, 0xCC, 0xDD]) }
            if b[2] == 0x8C { committed = true }
            if b[2] == 0x88 {
                if b[3] == 2 { return Data([0xAA, 0xBB, 0x88, 0, 2, b[4], committed ? 1 : 0, committed ? 2 : 0, 0xCC, 0xDD]) }
                let frames = committed ? payload.frameCount : 0
                let bytes = committed ? UInt32(payload.bytes.count) : 0
                let crc = committed ? payload.crc32 ^ (crcMismatch ? 1 : 0) : 0
                var result = Data([0xAA, 0xBB, 0x88, 0, 3, b[4], UInt8(truncatingIfNeeded: frames), UInt8(truncatingIfNeeded: frames >> 8)])
                for value in [bytes, crc] { result.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
                result.append(contentsOf: [0xCC, 0xDD]); return result
            }
            return Data([0xAA, 0xBB, b[2], 0, 0xCC, 0xDD])
        }
        func run(mtu: Int = 64, baseline: WS3DisplaySnapshot? = nil, progress: (Int, Int) -> Void = { _, _ in }) async throws -> WS3ResourceReadback {
            try await ConfirmedWS3ResourceUpload.run(payload: payload, baseline: baseline ?? self.baseline,
                generation: 7, maximumWriteLength: mtu, checkSession: {
                    guard self.epoch == 7 else { throw WS3ResourceUploadError.unverifiedConnection }
                }, exchange: { try self.exchange($0) }, progress: progress)
        }
    }
    private func payload(_ entry: UInt8 = 8) throws -> WS3ResourcePayload {
        try .init(entryID: entry, frames: [Data((0..<25_600).map { UInt8(truncatingIfNeeded: $0) })])
    }

    func testPaddingChecksumCapacityAndNoSilentTruncation() throws {
        XCTAssertEqual(WS3ResourcePayload.checksum(Data("123456789".utf8)), 0xCBF43926)
        let image = try payload()
        XCTAssertEqual(image.bytes.count, 28_672)
        XCTAssertEqual(image.bytes.suffix(3072), Data(repeating: 0xFF, count: 3072))
        for id: UInt8 in 0..<19 {
            let expected = [0, 4, 8, 12].contains(Int(id)) ? 8 : 12
            XCTAssertEqual(Int(WS3ResourceReadback.maximumFrames(id)), expected)
            XCTAssertThrowsError(try WS3ResourcePayload(entryID: id, frames: Array(repeating: Data(count: 25_600), count: expected + 1)))
        }
        XCTAssertThrowsError(try WS3ResourcePayload(entryID: 19, frames: [Data(count: 25_600)]))
        XCTAssertThrowsError(try WS3ResourcePayload(entryID: 0, frames: [Data(count: 25_599)]))
        XCTAssertThrowsError(try WS3ResourcePayload(entryID: 0, frames: []))
    }

    func testCommandEncodingAndScopedWriteGrant() throws {
        let image = try payload(16), begin = WS3ResourceUploadCommand.begin(image).request
        XCTAssertEqual(Array(begin.prefix(10)), [0xAA, 0xBB, 0x8A, 16, 0, 0x70, 0, 0, 1, 0])
        XCTAssertTrue(WS3ResourceUploadCommand.validRequest(begin))
        XCTAssertFalse(WS3ResourceUploadCommand.validRequest(Data([0xAA, 0xBB, 0x8D, 16, 0xCC, 0xDD])))
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(begin, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(begin, profile: profile, confirmedWrite: .ws3Resource))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(begin, profile: profile, confirmedWrite: .ws3Resource, ws3DisplayReadbackVerified: true))
        var wrong = begin; wrong[4] = 1
        XCTAssertFalse(WS3ResourceUploadCommand.validRequest(wrong))
        XCTAssertFalse(WS3ResourceUploadCommand.validRequest(WS3ResourceUploadCommand.chunk(entry: 0, offset: 0, bytes: Data(count: 49)).request))
    }

    func testUploadSerializesOffsetsAndVerifiesMetadataAfterCommit() async throws {
        let io = try Firmware(payload())
        var progress: [Int] = []
        let result = try await io.run { done, total in XCTAssertEqual(total, 28_672); progress.append(done) }
        XCTAssertTrue(result.reportsValidUserResource)
        XCTAssertEqual(result.crc32, io.payload.crc32)
        XCTAssertEqual(Array(io.requests.prefix(2)).map { $0[2] }, [0x88, 0x88])
        XCTAssertEqual(Array(io.requests.suffix(3)).map { $0[2] }, [0x8C, 0x88, 0x88])
        var reconstructed = Data(), offset = 0
        for chunk in io.requests.filter({ $0[2] == 0x8B }) {
            let b = [UInt8](chunk)
            let actual = (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[4 + $1]) << ($1 * 8) }
            XCTAssertEqual(actual, UInt32(offset))
            XCTAssertLessThanOrEqual(b[8], 48)
            reconstructed.append(contentsOf: b[9..<(9 + Int(b[8]))]); offset += Int(b[8])
        }
        XCTAssertEqual(reconstructed, io.payload.bytes)
        XCTAssertEqual(progress.first, 0); XCTAssertEqual(progress.last, 28_672)
        XCTAssertFalse(io.requests.contains { [0x04, 0x80, 0x81, 0x8D, 0x8E].contains($0[2]) })
    }

    func testSmallMTUAccountsForEveryByteOfCommandOverhead() async throws {
        let io = try Firmware(payload())
        _ = try await io.run(mtu: 20)
        XCTAssertTrue(io.requests.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(io.requests.first { $0[2] == 0x8B }?[8], 9)
        let invalid = try Firmware(payload())
        do { _ = try await invalid.run(mtu: 15); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceUploadError, .invalidMTU) }
        XCTAssertTrue(invalid.requests.isEmpty)
    }

    func testConflictAndOldConnectionNeverBeginUpload() async throws {
        let io = try Firmware(payload())
        let changed = WS3ResourceReadback(id: 8, basic: .resourceBasic(userValid: true, writeState: .valid),
            integrity: .resourceIntegrity(frames: 1, bytes: 28_672, crc32: 99))!
        let stale = WS3DisplaySnapshot(generation: 7, brightness: 35, resources: io.baseline.resources.map { $0.id == 8 ? changed : $0 })
        do { _ = try await io.run(baseline: stale); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceUploadError, .conflict) }
        XCTAssertFalse(io.requests.contains { $0[2] != 0x88 })
        let wrongEpoch = WS3DisplaySnapshot(generation: 6, brightness: 35, resources: io.baseline.resources)
        io.requests = []
        do { _ = try await io.run(baseline: wrongEpoch); XCTFail() } catch {}
        XCTAssertTrue(io.requests.isEmpty)
    }

    func testRejectOrCancellationStopsWithoutRetryCommitOrClear() async throws {
        for canceled in [false, true] {
            let io = try Firmware(payload())
            if canceled { io.intercept = { if $0[2] == 0x8B { throw CancellationError() } } }
            else { io.reject = 0x8B }
            do { _ = try await io.run(); XCTFail() } catch {}
            XCTAssertEqual(io.requests.filter { $0[2] == 0x8B }.count, 1)
            XCTAssertFalse(io.requests.contains { [0x8C, 0x8D].contains($0[2]) })
        }
    }

    func testConnectionChangeAfterChunkStopsBeforeAnyNextWrite() async throws {
        let io = try Firmware(payload())
        io.intercept = { if $0[2] == 0x8B { io.epoch = 8 } }
        do { _ = try await io.run(); XCTFail() } catch {}
        XCTAssertEqual(io.requests.filter { $0[2] == 0x8B }.count, 1)
        XCTAssertFalse(io.requests.contains { $0[2] == 0x8C })
    }

    func testCommitACKAloneCannotReportUploadSuccess() async throws {
        let io = try Firmware(payload())
        io.crcMismatch = true
        do { _ = try await io.run(); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceUploadError, .verificationMismatch) }
        XCTAssertTrue(io.committed)
    }

    func testSplitAndOversizedACKsAreNotMisassociated() {
        let request = WS3ResourceUploadCommand.commit(entry: 8).request
        var decoder = DeviceFrameDecoder()
        XCTAssertTrue(decoder.append(Data([0xAA, 0xBB, 0x8C])).isEmpty)
        let reply = decoder.append(Data([0, 0xCC, 0xDD]))
        XCTAssertEqual(reply.count, 1)
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x8C, response: reply[0]))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x8C, response: Data([0xAA, 0xBB, 0x8C, 0, 99, 0xCC, 0xDD])))
    }
}
