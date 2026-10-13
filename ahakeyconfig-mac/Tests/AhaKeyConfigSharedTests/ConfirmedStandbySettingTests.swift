import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedStandbySettingTests: XCTestCase {
    @MainActor
    func testWireEncodingOnlyIncludesSelfPersistingSetting() {
        XCTAssertEqual(ConfirmedStandbySetting.request(minutes: 120), Data([0xAA, 0xBB, 0x95, 0x78, 0, 0xCC, 0xDD]))
        XCTAssertEqual(ConfirmedStandbySetting.request(minutes: 0), Data([0xAA, 0xBB, 0x95, 0, 0, 0xCC, 0xDD]))
        XCTAssertNil(ConfirmedStandbySetting.request(minutes: 5))
    }

    @MainActor
    func testReadWriteAckReadSequenceAndNoOp() async throws {
        var values: [UInt16] = [60, 30], events: [String] = []
        let actual = try await ConfirmedStandbySetting.run(target: 30, checkSession: {}, read: {
            events.append("read"); return values.removeFirst()
        }, write: { value in events.append("95 \(value)") })
        XCTAssertEqual(actual, 30)
        XCTAssertEqual(events, ["read", "95 30", "read"])
        events.removeAll()
        _ = try await ConfirmedStandbySetting.run(target: 30, checkSession: {}, read: { 30 }, write: { _ in events.append("unexpected write") })
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testAckWithUnchangedReadbackIsNotSuccess() async {
        do {
            _ = try await ConfirmedStandbySetting.run(target: 30, checkSession: {}, read: { 60 }, write: { _ in })
            XCTFail("ACK alone is insufficient")
        } catch { XCTAssertEqual(error as? ConfirmedStandbySetting.Failure, .mismatch(expected: 30, actual: 60)) }
    }

    @MainActor
    func testRejectedWriteStopsBeforeReadback() async {
        var reads = 0
        do {
            _ = try await ConfirmedStandbySetting.run(target: 0, checkSession: {}, read: { reads += 1; return 60 }, write: { _ in throw CancellationError() })
            XCTFail("failed write cannot be applied")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testInvalidChoiceNeverReadsOrWrites() async {
        var operations = 0
        do {
            _ = try await ConfirmedStandbySetting.run(target: 1, checkSession: {}, read: { operations += 1; return 60 }, write: { _ in operations += 1 })
            XCTFail("unsupported value must fail")
        } catch { XCTAssertEqual(error as? ConfirmedStandbySetting.Failure, .invalidValue) }
        XCTAssertEqual(operations, 0)
    }

    @MainActor
    func testHandoffAfterAckDoesNotReadFromReplacementConnection() async {
        var valid = true, reads = 0
        do {
            _ = try await ConfirmedStandbySetting.run(target: 30, checkSession: { if !valid { throw CancellationError() } }, read: { reads += 1; return 60 }, write: { _ in valid = false })
            XCTFail("stale transaction must fail")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testStandbyGrantDoesNotOpenModeSaveOrUnsupportedValues() {
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let request = ConfirmedStandbySetting.request(minutes: 30)!
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: known))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: known, confirmedWrite: .standby))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: nil, confirmedWrite: .standby))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: known, confirmedWrite: .mode))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x95, 1, 0, 0xCC, 0xDD]), profile: known, confirmedWrite: .standby))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: known, confirmedWrite: .standby))
    }
}
