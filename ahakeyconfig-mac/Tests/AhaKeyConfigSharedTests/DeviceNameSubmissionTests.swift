import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class DeviceNameSubmissionTests: XCTestCase {
    private let ack = Data([0xAA, 0xBB, 0x01, 0, 0xCC, 0xDD])
    func testNameValidationUsesUTF8BytesWithoutTruncation() throws {
        XCTAssertEqual(try DeviceNameSubmission.validate("  AhaKey  \n").get(), "AhaKey")
        XCTAssertThrowsError(try DeviceNameSubmission.request(" \n"))
        XCTAssertThrowsError(try DeviceNameSubmission.request("Test\0Name"))
        XCTAssertNoThrow(try DeviceNameSubmission.request("中文中文中"))
        XCTAssertThrowsError(try DeviceNameSubmission.request("中文中文中文"))
    }
    func testDeviceAckReportsAcceptanceAndDoesNotSendUnrelatedSave() async throws {
        var requests: [Data] = []
        let result = try await DeviceNameSubmission.submit(" Test ", checkSession: {}, exchange: {
            requests.append($0); return self.ack
        })
        XCTAssertEqual(result.acceptedName, "Test")
        XCTAssertEqual(requests, [try DeviceNameSubmission.request("Test")])
    }
    func testLostReplyNeverReturnsReceiptOrRetries() async {
        enum Lost: Error { case reply }
        var requests = 0
        do {
            _ = try await DeviceNameSubmission.submit("Test", checkSession: {}, exchange: { _ in
                requests += 1; throw Lost.reply
            })
            XCTFail("unconfirmed write cannot be accepted")
        } catch { XCTAssertTrue(error is DeviceNameSubmission.Failure) }
        XCTAssertEqual(requests, 1)
    }
    func testRefusalAndWrongOpcodeCannotConfirmName() async {
        for reply in [Data([0xAA, 0xBB, 0x01, 1, 0xCC, 0xDD]), Data([0xAA, 0xBB, 0x04, 0, 0xCC, 0xDD])] {
            do {
                _ = try await DeviceNameSubmission.submit("Test", checkSession: {}, exchange: { _ in reply })
                XCTFail("not a successful rename ACK")
            } catch {}
        }
    }
    func testChangedConnectionStopsBeforeSend() async {
        enum Changed: Error { case session }
        var sent = false
        do {
            _ = try await DeviceNameSubmission.submit("Test", checkSession: { throw Changed.session },
                exchange: { _ in sent = true; return self.ack })
            XCTFail("stale device")
        } catch {}
        XCTAssertFalse(sent)
    }
    func testDedicatedGrantAndExactNameShapeAreRequired() throws {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) +
            Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let request = try DeviceNameSubmission.request("Test")
        for profile in [profile, .legacyAfterStatusReadback()] {
            XCTAssertTrue(ConfigurationCommandPolicy.permits(request, profile: profile, confirmedWrite: .deviceName))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: profile))
            XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x01, 0xFF, 0xCC, 0xDD]),
                profile: profile, confirmedWrite: .deviceName))
        }
        XCTAssertFalse(ConfigurationCommandPolicy.permits(request, profile: nil, confirmedWrite: .deviceName))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]),
            profile: profile, confirmedWrite: .deviceName))
    }
    func testSplitRenameAckIsReassembled() {
        var decoder = DeviceFrameDecoder()
        XCTAssertTrue(DeviceFrameDecoder.recognizes(0x01))
        let request = try! DeviceNameSubmission.request("Test")
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x01, response: ack))
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x01,
            response: Data(ack.dropLast(2)) + Data([0, 0xCC, 0xDD])))
        XCTAssertTrue(decoder.append(Data(ack.prefix(4))).isEmpty)
        XCTAssertEqual(decoder.append(Data(ack.suffix(2))), [ack])
    }
}
