import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class ACR4ResourceUploadTests: XCTestCase {
    private final class Firmware {
        let object: ACR4ResourceObject
        var requests: [ACR4Command] = []
        var stored = Data()
        var state: UInt8 = 0
        var committed = false
        var cancelled = false
        var drop: ACR4Command.Operation?
        var dropBeforeAccept = false
        var rejectChunks = false
        var cleanupFault = false
        var corruptCRC = false
        var generationValid = true
        var afterChunk: (() -> Void)?
        init() throws {
            object = ACR4ResourceObject(payload: try WS3ResourcePayload(entryID: 15, frames: [Data(count: 25600)]))
        }
        var baseline: WS3DisplaySnapshot {
            .init(generation: 8, brightness: 35, resources: (UInt8(0)..<19).map {
                WS3ResourceReadback(id: $0, basic: .resourceBasic(userValid: false, writeState: .empty),
                    integrity: .resourceIntegrity(frames: 0, bytes: 0, crc32: 0))!
            })
        }
        func exchange(_ wire: Data) throws -> Data {
            let command = try XCTUnwrap(ACR4Command(request: wire)); requests.append(command)
            var fields = Data(), status: UInt8 = 0
            if drop == command.operation && dropBeforeAccept { drop = nil; throw ACR4UploadFailure.timeout }
            switch command.operation {
            case .caps:
                fields = Data(Array("ACR4".utf8) + [15, 0]) + ACR4Command.le(307240) + Data([128, 1, 8, 12])
            case .begin:
                XCTAssertEqual(command.fields[0], object.entry)
                XCTAssertEqual(ACR4Command.u32([UInt8](command.fields), 1), UInt32(object.bytes.count))
                XCTAssertEqual(ACR4Command.u32([UInt8](command.fields), 5), WS3ResourcePayload.checksum(object.bytes))
                stored = Data(command.fields.suffix(16)); state = 1
                fields = ACR4Command.le(16) + ACR4Command.le(object.expandedBytes)
            case .chunk:
                if rejectChunks { status = 10; fields = ACR4Command.le(UInt32(stored.count)); break }
                XCTAssertEqual(ACR4Command.u32([UInt8](command.fields), 0), UInt32(stored.count))
                stored.append(command.fields.dropFirst(5))
                fields = ACR4Command.le(UInt32(stored.count)) + Data([command.fields[4]])
                afterChunk?()
            case .commit:
                XCTAssertEqual(stored, object.bytes)
                committed = true; state = 0
                fields = Data([object.entry, UInt8(object.frames)]) + ACR4Command.le(object.expandedBytes) + ACR4Command.le(object.expandedCRC)
            case .cancel:
                if cleanupFault { status = 10; fields = ACR4Command.le(0); break }
                cancelled = true; state = 0; committed = false
                fields = Data([0, object.entry]) + ACR4Command.le(0)
            case .status:
                fields = Data([cleanupFault ? 4 : state, object.entry]) + ACR4Command.le(UInt32(stored.count)) + ACR4Command.le(0) + Data([0])
            case .metadata:
                fields = Data([committed ? 2 : (cancelled ? 3 : 0), committed ? UInt8(object.frames) : 0]) +
                    ACR4Command.le(committed ? object.expandedBytes : 0) +
                    ACR4Command.le(committed ? object.expandedCRC ^ (corruptCRC ? 1 : 0) : 0)
            }
            if drop == command.operation { drop = nil; throw ACR4UploadFailure.timeout }
            var reply = Data([0xAA, 0xBB, 0x9E, status, 4, command.operation.rawValue, UInt8(fields.count)])
            reply.append(ACR4Command.le(command.token)); reply.append(fields); reply.append(contentsOf: [0xCC, 0xDD]); return reply
        }
        func run(progress: (Int, Int) -> Void = { _, _ in }) async throws -> WS3ResourceReadback {
            try await ConfirmedACR4ResourceUpload.run(object: object, baseline: baseline, generation: 8, chunkSize: 128,
                checkSession: { if !self.generationValid { throw WS3ResourceUploadError.unverifiedConnection } },
                exchange: { try self.exchange($0) }, progress: progress)
        }
    }

    func testUploadConfirmsDurableMetadataAndCreditsEncodedBytesOnly() async throws {
        let io = try Firmware(); var progress: [Int] = []
        let value = try await io.run { bytes, total in progress.append(bytes); XCTAssertEqual(total, io.object.bytes.count) }
        XCTAssertEqual(value.crc32, io.object.expandedCRC)
        XCTAssertEqual(value.payloadBytes, io.object.expandedBytes)
        XCTAssertEqual(io.stored, io.object.bytes)
        XCTAssertEqual(io.requests.first?.operation, .metadata)
        XCTAssertEqual(io.requests.last?.operation, .metadata)
        XCTAssertEqual(progress.first, 16); XCTAssertEqual(progress.last, io.object.bytes.count)
        XCTAssertEqual(progress, Array(Set(progress)).sorted())
        XCTAssertFalse(io.cancelled)
    }

    func testLostBeginChunkAndCommitACKsNeverBlindlyReplayBeginOrDoubleCredit() async throws {
        for operation: ACR4Command.Operation in [.begin, .chunk, .commit] {
            let io = try Firmware(); io.drop = operation
            _ = try await io.run()
            XCTAssertEqual(io.requests.filter { $0.operation == .begin }.count, 1)
            XCTAssertEqual(io.stored, io.object.bytes)
            if operation != .commit { XCTAssertTrue(io.requests.contains { $0.operation == .status }) }
        }
    }

    func testUnacceptedChunkResendsIdenticalBytesAfterStatusOnly() async throws {
        let io = try Firmware(); io.drop = .chunk; io.dropBeforeAccept = true
        _ = try await io.run()
        let chunks = io.requests.filter { $0.operation == .chunk }
        XCTAssertEqual(chunks[0], chunks[1]); XCTAssertEqual(io.stored, io.object.bytes)
        XCTAssertEqual(io.requests.filter { $0.operation == .begin }.count, 1)
    }

    func testStorageFailureUsesTokenCancelAndNeverDestructiveDefaultRestore() async throws {
        let io = try Firmware(); io.rejectChunks = true
        do { _ = try await io.run(); XCTFail() }
        catch { XCTAssertEqual(error as? ACR4UploadFailure, .rejected(10)) }
        XCTAssertTrue(io.cancelled)
        XCTAssertFalse(io.requests.contains { $0.operation == .commit })
        XCTAssertEqual(io.requests.filter { $0.operation == .begin }.first?.token,
                       io.requests.filter { $0.operation == .cancel }.first?.token)
    }

    func testCRCDisagreementCannotBecomeSuccessAndUncertainCleanupIsVisible() async throws {
        let io = try Firmware(); io.corruptCRC = true
        do { _ = try await io.run(); XCTFail() }
        catch { XCTAssertEqual(error as? WS3ResourceUploadError, .verificationMismatch) }
        XCTAssertTrue(io.cancelled)
        let fault = try Firmware(); fault.rejectChunks = true; fault.cleanupFault = true
        do { _ = try await fault.run(); XCTFail() }
        catch { XCTAssertEqual(error as? ACR4UploadFailure, .uncertain) }
    }

    func testGenerationLossStopsAllFurtherCommandsIncludingCleanup() async throws {
        let io = try Firmware(); io.afterChunk = { io.generationValid = false }
        do { _ = try await io.run(); XCTFail() }
        catch { XCTAssertEqual(error as? ACR4UploadFailure, .uncertain) }
        XCTAssertEqual(io.requests.last?.operation, .chunk)
        XCTAssertFalse(io.requests.contains { $0.operation == .commit || $0.operation == .cancel })
    }

    func testCancellationDrainsWithNonCancelledCleanupTask() async throws {
        let io = try Firmware()
        io.afterChunk = { withUnsafeCurrentTask { $0?.cancel() } }
        let operation = Task { try await io.run() }
        do { _ = try await operation.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(io.cancelled)
        XCTAssertFalse(io.requests.contains { $0.operation == .commit })
    }

    func testLegacyCapabilityACKAndUnsupportedReplyAllowOnlyNoBeginFallback() async throws {
        let capability = try await ConfirmedACR4ResourceUpload.capability { _ in Data([0xAA, 0xBB, 0x9E, 0, 0xCC, 0xDD]) }
        XCTAssertNil(capability)
        let oldFirmware = try await ConfirmedACR4ResourceUpload.capability { wire in
            Data([0xAA, 0xBB, 0x9E, 1, 4, 0x40]) + wire.subdata(in: 5..<9) + Data([0xCC, 0xDD])
        }
        XCTAssertNil(oldFirmware)
        let io = try Firmware()
        let supported = try await ConfirmedACR4ResourceUpload.capability { try io.exchange($0) }
        XCTAssertEqual(supported, 128)
        XCTAssertEqual(io.requests.map(\.operation), [.caps])
    }

    func testReadbackProofAndScopedGrantAreRequiredForEveryACR4Write() throws {
        let io = try Firmware()
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]))
        let command = ACR4Command(.begin, token: 9, fields: Data([io.object.entry]) + ACR4Command.le(UInt32(io.object.bytes.count)) +
            ACR4Command.le(WS3ResourcePayload.checksum(io.object.bytes)) + io.object.bytes.prefix(16))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(command.request, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(command.request, profile: profile, confirmedWrite: .acr4Resource, ws3DisplayReadbackVerified: true))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(command.request, profile: profile, confirmedWrite: .acr4Resource,
            ws3DisplayReadbackVerified: true, acr4ReadbackVerified: true))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(command.request, profile: nil, confirmedWrite: .acr4Resource,
            ws3DisplayReadbackVerified: true, acr4ReadbackVerified: true))
        let payload = try WS3ResourcePayload(entryID: 15, frames: [Data(count: 25600)])
        let resource = WS3ResourceReadback(id: 15, basic: .resourceBasic(userValid: true, writeState: .valid),
            integrity: .resourceIntegrity(frames: 1, bytes: 28672, crc32: io.object.expandedCRC))!
        XCTAssertEqual(WS3ResourceMetadataComparison(payload: payload, resource: resource), .matches)
    }
}
