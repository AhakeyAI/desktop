import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedWS3DisplaySettingTests: XCTestCase {
    func testOnlyCompleteCurrentGenerationReadbackGrantsEditing() throws {
        let resources = try (UInt8(0)..<19).map { id in
            try XCTUnwrap(WS3ResourceReadback(id: id, basic: .resourceBasic(userValid: false, writeState: .empty), integrity: .resourceIntegrity(frames: 0, bytes: 0, crc32: 0)))
        }
        let full = WS3DisplaySnapshot(generation: 2, brightness: 35, resources: resources)
        XCTAssertTrue(full.verifiesDisplaySettings(in: 2))
        XCTAssertFalse(full.verifiesDisplaySettings(in: 3))
        XCTAssertFalse(WS3DisplaySnapshot(generation: 2, brightness: 0, resources: resources).verifiesDisplaySettings(in: 2))
        XCTAssertFalse(WS3DisplaySnapshot(generation: 2, brightness: 35, resources: Array(resources.dropLast())).verifiesDisplaySettings(in: 2))
        XCTAssertFalse(WS3DisplaySnapshot(generation: 2, brightness: 35, resources: Array(repeating: resources[0], count: 19)).verifiesDisplaySettings(in: 2))
    }
    func testWireRangesAndOffIsSaveableButNotPreviewable() {
        XCTAssertEqual(WS3DisplaySetting.brightness(35).saveRequest, Data([0xAA, 0xBB, 0x8E, 0, 35, 0xCC, 0xDD]))
        XCTAssertEqual(WS3DisplaySetting.singleLight(mode: 3, state: 8, effect: 0).saveRequest, Data([0xAA, 0xBB, 0x8E, 1, 3, 8, 0, 0xCC, 0xDD]))
        XCTAssertEqual(WS3DisplayPreview.light(effect: 16, brightness: 100).request, Data([0xAA, 0xBB, 0x89, 1, 16, 100, 0xCC, 0xDD]))
        XCTAssertEqual(WS3DisplayPreview.stop.request, Data([0xAA, 0xBB, 0x89, 2, 0xCC, 0xDD]))
        XCTAssertNil(WS3DisplaySetting.brightness(0).saveRequest)
        XCTAssertNil(WS3DisplaySetting.brightness(101).saveRequest)
        XCTAssertNil(WS3DisplaySetting.singleLight(mode: 4, state: 8, effect: 0).saveRequest)
        XCTAssertNil(WS3DisplaySetting.singleLight(mode: 0, state: 9, effect: 0).saveRequest)
        XCTAssertNil(WS3DisplaySetting.singleLight(mode: 0, state: 0, effect: 17).saveRequest)
        XCTAssertNil(WS3DisplayPreview.light(effect: 0, brightness: 50).request)
        XCTAssertNil(WS3DisplayPreview.brightness(0).request)
    }
    func testCatalogAloneAndWrongGrantsCannotAuthorizeWrites() throws {
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        for request in [try XCTUnwrap(WS3DisplaySetting.brightness(35).saveRequest), try XCTUnwrap(WS3DisplayPreview.brightness(35).request)] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: known, confirmedWrite: .ws3Display))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: known, confirmedWrite: .standby, ws3DisplayReadbackVerified: true))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: nil, confirmedWrite: .ws3Display, ws3DisplayReadbackVerified: true))
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: known, confirmedWrite: .ws3Display, ws3DisplayReadbackVerified: true))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request + Data([0]), profile: known, confirmedWrite: .ws3Display, ws3DisplayReadbackVerified: true))
        }
        for opcode: UInt8 in [0x04, 0x8A, 0x8B, 0x8C, 0x8D, 0x98] {
            XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, opcode, 0xCC, 0xDD]), profile: known, confirmedWrite: .ws3Display, ws3DisplayReadbackVerified: true))
        }
    }
    func testDisplayAcksMustBeExactGenericFrames() throws {
        for request in [try XCTUnwrap(WS3DisplaySetting.brightness(35).saveRequest), try XCTUnwrap(WS3DisplayPreview.stop.request)] {
            let ack = Data([0xAA, 0xBB, request[2], 0, 0xCC, 0xDD])
            XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: request[2], response: ack))
            XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: request[2], response: Data([0xAA, 0xBB, request[2], 0, 1, 0xCC, 0xDD])))
        }
    }
    @MainActor
    func testUnknownBaselineStaysReadOnlyEvenForKnownTarget() async {
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .singleLight(mode: 0, state: 0, effect: 1), baseline: 255, checkSession: {}, read: { _ in XCTFail("unknown baseline must not start"); return 255 }, write: { _ in XCTFail("unknown effect must stay read-only") })
            XCTFail("invalid baseline")
        } catch { XCTAssertEqual(error as? ConfirmedWS3DisplaySetting.Failure, .invalidValue) }
    }
    @MainActor
    func testSaveUsesReadWriteReadAndNeverBroadSave() async throws {
        var values: [UInt8] = [40, 35], events: [String] = []
        let result = try await ConfirmedWS3DisplaySetting.run(target: .brightness(35), baseline: 40, checkSession: {}, read: { item in
            XCTAssertEqual(item, .brightness); events.append("read"); return values.removeFirst()
        }, write: { data in
            XCTAssertEqual(data, WS3DisplaySetting.brightness(35).saveRequest); events.append("8E")
        })
        XCTAssertEqual(result, 35); XCTAssertEqual(events, ["read", "8E", "read"])
    }
    @MainActor
    func testChangedBaselineAndUnknownEffectNeverWrite() async {
        var writes = 0
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .singleLight(mode: 2, state: 4, effect: 5), baseline: 1, checkSession: {}, read: { _ in 2 }, write: { _ in writes += 1 })
            XCTFail("External changes require reread")
        } catch { XCTAssertEqual(error as? ConfirmedWS3DisplaySetting.Failure, .changedBaseline) }
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .singleLight(mode: 0, state: 0, effect: 255), baseline: 255, checkSession: {}, read: { _ in XCTFail("invalid target must not read"); return 255 }, write: { _ in writes += 1 })
            XCTFail("unknown target")
        } catch { XCTAssertEqual(error as? ConfirmedWS3DisplaySetting.Failure, .invalidValue) }
        XCTAssertEqual(writes, 0)
    }
    @MainActor
    func testAckWithoutMatchingReadbackIsFailure() async {
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .brightness(35), baseline: 40, checkSession: {}, read: { _ in 40 }, write: { _ in })
            XCTFail("ACK is not readback")
        } catch { XCTAssertEqual(error as? ConfirmedWS3DisplaySetting.Failure, .mismatch) }
    }
    @MainActor
    func testCancellationAfterWriteAndSessionHandoffStopReadback() async {
        var reads = 0
        let task = Task { @MainActor in
            try await ConfirmedWS3DisplaySetting.run(target: .brightness(35), baseline: 40, checkSession: {}, read: { _ in reads += 1; return 40 }, write: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { _ = try await task.value; XCTFail("cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
        var valid = true
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .brightness(35), baseline: 40, checkSession: { if !valid { throw CancellationError() } }, read: { _ in reads += 1; return 40 }, write: { _ in valid = false })
            XCTFail("stale session")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 2)
    }
    @MainActor
    func testDeviceRejectStopsBeforeReadback() async {
        var reads = 0
        do {
            _ = try await ConfirmedWS3DisplaySetting.run(target: .brightness(35), baseline: 40, checkSession: {}, read: { _ in reads += 1; return 40 }, write: { _ in throw CancellationError() })
            XCTFail("write failed")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }
}
