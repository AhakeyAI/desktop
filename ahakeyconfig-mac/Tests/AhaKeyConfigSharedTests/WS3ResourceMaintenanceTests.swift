import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class WS3ResourceMaintenanceTests: XCTestCase {
    nonisolated private static func resource(_ id: UInt8, state: WS3ResourceWriteState = .valid, crc: UInt32 = 0x1234) -> WS3ResourceReadback {
        let valid = state == .valid
        return WS3ResourceReadback(id: id, basic: .resourceBasic(userValid: valid, writeState: state),
            integrity: .resourceIntegrity(frames: valid ? 1 : 0, bytes: valid ? 28_672 : 0, crc32: valid ? crc : 0))!
    }
    private final class Firmware {
        var current = WS3ResourceMaintenanceTests.resource(18)
        var epoch: UInt64 = 7
        var requests: [Data] = []
        var rejected = false, badPostState = false
        var override: ((Data) throws -> Data?)?
        var baseline: WS3DisplaySnapshot {
            .init(generation: 7, brightness: 35, resources: (UInt8(0)..<19).map {
                if $0 == 8 { return WS3ResourceMaintenanceTests.resource(8, crc: 0xCAFEBABE) }
                return $0 == 18 ? current : WS3ResourceMaintenanceTests.resource($0, state: .empty)
            })
        }
        func exchange(_ request: Data) throws -> Data {
            requests.append(request)
            if let replacement = try override?(request) { return replacement }
            let b = [UInt8](request)
            if b[2] == 0x8D {
                if rejected { return Data([0xAA, 0xBB, 0x8D, 1, 0xCC, 0xDD]) }
                current = WS3ResourceMaintenanceTests.resource(18, state: badPostState ? .invalid : .empty)
                return Data([0xAA, 0xBB, 0x8D, 0, 0xCC, 0xDD])
            }
            if b[3] == 2 {
                return Data([0xAA, 0xBB, 0x88, 0, 2, b[4], current.userValid ? 1 : 0, current.writeState.rawValue, 0xCC, 0xDD])
            }
            var reply = Data([0xAA, 0xBB, 0x88, 0, 3, b[4], UInt8(truncatingIfNeeded: current.frames), UInt8(truncatingIfNeeded: current.frames >> 8)])
            for value in [current.payloadBytes, current.crc32] { reply.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
            reply.append(contentsOf: [0xCC, 0xDD]); return reply
        }
        func restore(baseline: WS3DisplaySnapshot? = nil) async throws -> WS3ResourceReadback {
            try await ConfirmedWS3ResourceMaintenance.restoreDefault(entry: 18, baseline: baseline ?? self.baseline,
                generation: 7, checkSession: { guard self.epoch == 7 else { throw WS3ResourceMaintenanceError.unverifiedConnection } },
                exchange: { try self.exchange($0) })
        }
    }

    func testMetadataComparisonDoesNotRequireOrWriteFlashBytes() throws {
        let payload = try WS3ResourcePayload(entryID: 18, frames: [Data(count: 25_600)])
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: Self.resource(18, crc: payload.crc32)), .matches)
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: Self.resource(18, crc: payload.crc32 ^ 1)), .different)
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: Self.resource(17, crc: payload.crc32)), .different)
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: Self.resource(18, state: .empty)), .noValidCustomResource)
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: Self.resource(18, state: .invalid)), .noValidCustomResource)
    }

    func testReadOnlyVerificationHasOnlyTwo88Queries() async throws {
        let io = Firmware(), before = io.current
        let actual = try await ConfirmedWS3ResourceMaintenance.read(entry: 18, baseline: io.baseline, generation: 7,
            checkSession: {}, exchange: { try io.exchange($0) })
        XCTAssertEqual(actual, before)
        XCTAssertEqual(io.requests, [WS3DisplayItem.resourceBasic(18).request!, WS3DisplayItem.resourceIntegrity(18).request!])
        XCTAssertEqual(io.current, before)
    }

    func testRestoreWritesOnlyTargetThenRequiresExactEmptyMetadata() async throws {
        let io = Firmware(), photoBefore = io.baseline.resources[8]
        let actual = try await io.restore()
        XCTAssertTrue(WS3ResourceRestoreCommand.reportsDefault(actual))
        XCTAssertEqual(io.requests.map { $0[2] }, [0x88, 0x88, 0x8D, 0x88, 0x88])
        XCTAssertEqual(io.requests[2], Data([0xAA, 0xBB, 0x8D, 18, 0xCC, 0xDD]))
        XCTAssertEqual(io.baseline.resources[8], photoBefore)
        XCTAssertFalse(io.requests.contains { [0x04, 0x8A, 0x8B, 0x8C, 0x8E].contains($0[2]) })
    }

    func testFreshDefaultIsNoWriteButInvalidMarkerCanBeRepaired() async throws {
        let io = Firmware(); io.current = Self.resource(18, state: .empty)
        _ = try await io.restore()
        XCTAssertEqual(io.requests.count, 2)
        XCTAssertTrue(io.requests.allSatisfy { $0[2] == 0x88 })
        io.requests = []; io.current = Self.resource(18, state: .invalid)
        _ = try await io.restore()
        XCTAssertEqual(io.requests.filter { $0[2] == 0x8D }.count, 1)
    }

    func testStaleBaselineOrWritingResourceCannotBeCleared() async {
        let io = Firmware(), original = io.baseline
        io.current = Self.resource(18, crc: 0x9999)
        do { _ = try await io.restore(baseline: original); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceMaintenanceError, .conflict) }
        XCTAssertFalse(io.requests.contains { $0[2] == 0x8D })
        io.requests = []; io.current = Self.resource(18, state: .writing)
        do { _ = try await io.restore(); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceMaintenanceError, .busy) }
        XCTAssertFalse(io.requests.contains { $0[2] == 0x8D })
    }

    func testOldGenerationAndIncompleteProofNeverAccessTransport() async {
        let io = Firmware()
        for snapshot in [WS3DisplaySnapshot(generation: 6, brightness: 35, resources: io.baseline.resources),
                         WS3DisplaySnapshot(generation: 7, brightness: 35, resources: Array(io.baseline.resources.dropLast()))] {
            do { _ = try await io.restore(baseline: snapshot); XCTFail() }
            catch { XCTAssertEqual(error as? WS3ResourceMaintenanceError, .unverifiedConnection) }
        }
        XCTAssertTrue(io.requests.isEmpty)
    }

    func testRejectedClearDoesNotRetryOrClaimRestored() async {
        let io = Firmware(); io.rejected = true
        do { _ = try await io.restore(); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceMaintenanceError, .rejected(1)) }
        XCTAssertEqual(io.requests.map { $0[2] }, [0x88, 0x88, 0x8D])
        XCTAssertTrue(io.current.reportsValidUserResource)
    }

    func testAcceptedACKWithInvalidPostStateIsNotSuccess() async {
        let io = Firmware(); io.badPostState = true
        do { _ = try await io.restore(); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceMaintenanceError, .verificationMismatch) }
        XCTAssertEqual(io.current.writeState, .invalid)
    }

    func testCancellationAndGenerationChangeStopBeforeAnyLaterWrite() async {
        for cancel in [true, false] {
            let io = Firmware()
            io.override = { request in
                if request[2] == 0x8D {
                    if cancel { throw CancellationError() }
                    io.epoch = 8
                }
                return nil
            }
            do { _ = try await io.restore(); XCTFail() } catch {}
            XCTAssertEqual(io.requests.map { $0[2] }, [0x88, 0x88, 0x8D])
        }
    }

    func testScopedRestorePermissionAndSplitACK() throws {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        let request = try XCTUnwrap(WS3ResourceRestoreCommand.request(entry: 18))
        XCTAssertNil(WS3ResourceRestoreCommand.request(entry: 19))
        var prefixed = Data(repeating: 0, count: 10); prefixed.append(request)
        XCTAssertTrue(WS3ResourceRestoreCommand.validRequest(prefixed.suffix(6)))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .ws3Resource, ws3DisplayReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .ws3ResourceRestore))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .ws3ResourceRestore, ws3DisplayReadbackVerified: true))
        var decoder = DeviceFrameDecoder()
        XCTAssertTrue(decoder.append(Data([0xAA, 0xBB, 0x8D])).isEmpty)
        let frames = decoder.append(Data([0, 0xCC, 0xDD]))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x8D, response: frames[0]))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x8D, response: Data([0xAA, 0xBB, 0x8D, 0, 4, 0xCC, 0xDD])))
    }
}
