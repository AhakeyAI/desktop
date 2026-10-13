import XCTest
@testable import AhaKeyConfigShared

final class ConfirmedModeChangeTests: XCTestCase {
    @MainActor
    func testRequiresAckAndFreshMatchingReadback() async throws {
        var events: [String] = [], reads: [UInt8] = [0, 2]
        let actual = try await ConfirmedModeChange.run(target: 2, checkSession: {}, readMode: {
            events.append("read"); return reads.removeFirst()
        }, writeMode: { target in events.append("ack \(target)") })
        XCTAssertEqual(actual, 2)
        XCTAssertEqual(events, ["read", "ack 2", "read"])
    }

    @MainActor
    func testAckWithoutMatchingReadbackIsFailure() async {
        var reads: [UInt8] = [0, 1]
        do {
            _ = try await ConfirmedModeChange.run(target: 2, checkSession: {}, readMode: { reads.removeFirst() }, writeMode: { _ in })
            XCTFail("ACK cannot establish the device mode")
        } catch {
            XCTAssertEqual(error as? ConfirmedModeChange.Failure, .mismatch(expected: 2, actual: 1))
        }
    }

    @MainActor
    func testLostAckDoesNotProceedOrReportSuccess() async {
        var reads = 0
        do {
            _ = try await ConfirmedModeChange.run(target: 1, checkSession: {}, readMode: { reads += 1; return 0 }, writeMode: { _ in throw CancellationError() })
            XCTFail("lost ACK must fail")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testHandoffDuringInitialReadCannotWriteToNewSession() async {
        var valid = true, writes = 0
        do {
            _ = try await ConfirmedModeChange.run(target: 1, checkSession: { if !valid { throw CancellationError() } }, readMode: { valid = false; return 0 }, writeMode: { _ in writes += 1 })
            XCTFail("old session must be invalidated")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testAlreadyAppliedModeDoesNotWrite() async throws {
        var writes = 0
        _ = try await ConfirmedModeChange.run(target: 3, checkSession: {}, readMode: { 3 }, writeMode: { _ in writes += 1 })
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testHandoffAfterAckCannotConfirmThroughNewConnection() async {
        var valid = true, reads = 0
        do {
            _ = try await ConfirmedModeChange.run(target: 1, checkSession: { if !valid { throw CancellationError() } }, readMode: { reads += 1; return 0 }, writeMode: { _ in valid = false })
            XCTFail("ACK from old connection must not establish success")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }

    func testModeGrantDoesNotOpenOtherWritesOrUnknownFirmware() {
        let known = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let mode = Data([0xAA, 0xBB, 0x92, 2, 0xCC, 0xDD])
        XCTAssertFalse(ConfigurationCommandPolicy.permits(mode, profile: known))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(mode, profile: known, confirmedWrite: .mode))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(mode, profile: nil, confirmedWrite: .mode))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: known, confirmedWrite: .mode))
    }
}
