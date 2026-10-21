import XCTest
@testable import AhaKeyConfigShared

@MainActor
final class ConfirmedWS3PresentationTests: XCTestCase {
    private func reply(_ request: Data) -> Data {
        let b = [UInt8](request)
        if b[2] == 0x9F { return Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]) }
        if b[2] == 0x88 {
            if b[3] == 0 { return Data([0xAA, 0xBB, 0x88, 0, 0, 35, 0xCC, 0xDD]) }
            if b[3] == 2 { return Data([0xAA, 0xBB, 0x88, 0, 2, b[4], 0, 0, 0xCC, 0xDD]) }
            return Data([0xAA, 0xBB, 0x88, 0, 3, b[4]] + Array(repeating: 0, count: 10) + [0xCC, 0xDD])
        }
        return Data([0xAA, 0xBB, b[2], 0, 0xCC, 0xDD])
    }

    func testCompleteFreshProbePrecedesModeAndEmptyMultiBoundary() async throws {
        var requests: [Data] = []
        try await ConfirmedWS3Presentation.activate(.multi, generation: 1, checkSession: {}, exchange: {
            requests.append($0); return self.reply($0)
        })
        XCTAssertEqual(requests.count, 42)
        XCTAssertEqual(requests[40], WS3PresentationCommand.setMode(.multi).request)
        XCTAssertEqual(requests[41], WS3PresentationCommand.multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!).request)
        XCTAssertEqual(requests[1], WS3DisplayItem.brightness.request)
        XCTAssertFalse(requests.contains { [UInt8(0x04), 0x8A, 0x8B, 0x8C, 0x8D, 0x8E].contains($0[2]) })
    }

    func testSingleDoesNotSendMultiOrAwaitUncorrelatedLegacyStateAck() async throws {
        var requests: [Data] = []
        try await ConfirmedWS3Presentation.activate(.single, generation: 1, checkSession: {}, exchange: {
            requests.append($0); return self.reply($0)
        })
        XCTAssertEqual(requests.count, 41)
        XCTAssertEqual(requests.last, WS3PresentationCommand.setMode(.single).request)
    }

    func testGenericShortAckAndIncompleteReadbackCannotAuthorizeWrites() async {
        for failedCommand: UInt8 in [0x9F, 0x88] {
            var writes: [UInt8] = []
            do {
                try await ConfirmedWS3Presentation.activate(.multi, generation: 1, checkSession: {}, exchange: { request in
                    writes.append(request[2])
                    return request[2] == failedCommand ? Data([0xAA, 0xBB, failedCommand, 0, 0xCC, 0xDD]) : self.reply(request)
                })
                XCTFail("short ACK must not prove support")
            } catch {}
            XCTAssertFalse(writes.contains(0x98)); XCTAssertFalse(writes.contains(0x99))
        }
        var writes: [UInt8] = []
        do {
            try await ConfirmedWS3Presentation.activate(.multi, generation: 1, checkSession: {}, exchange: { request in
                writes.append(request[2])
                if request == WS3DisplayItem.resourceIntegrity(18).request { return Data([0xAA, 0xBB, 0x88, 1, 0xCC, 0xDD]) }
                return self.reply(request)
            })
            XCTFail("the last resource also must verify")
        } catch {}
        XCTAssertFalse(writes.contains(0x98))
    }

    func testChangedSessionAndRejectionCannotContinueSending() async {
        var valid = true, requests: [Data] = []
        do {
            try await ConfirmedWS3Presentation.activate(.multi, generation: 1, checkSession: {
                if !valid { throw WS3PresentationError.connectionChanged }
            }, exchange: { request in
                requests.append(request)
                if requests.count == 40 { valid = false }
                return self.reply(request)
            })
            XCTFail("session changed before mode write")
        } catch {}
        XCTAssertEqual(requests.count, 40)
        requests = []
        do {
            try await ConfirmedWS3Presentation.activate(.multi, generation: 1, checkSession: {}, exchange: { request in
                requests.append(request)
                return request[2] == 0x98 ? Data([0xAA, 0xBB, 0x98, 2, 0xCC, 0xDD]) : self.reply(request)
            })
            XCTFail("rejected mode cannot send a snapshot")
        } catch {}
        XCTAssertFalse(requests.contains { $0[2] == 0x99 })
    }

    func testNewPresentationAckFramesReassembleAndMatchExactly() {
        for opcode: UInt8 in [0x90, 0x98, 0x99, 0x9A] {
            var framer = DeviceNotificationFramer()
            XCTAssertTrue(framer.append(Data([0xAA, 0xBB, opcode, 0])).isEmpty)
            let frames = framer.append(Data([0xCC, 0xDD]))
            XCTAssertEqual(frames, [Data([0xAA, 0xBB, opcode, 0, 0xCC, 0xDD])])
            XCTAssertFalse(DeviceResponseMatcher.matches(request: Data([0xAA, 0xBB, opcode, 0xCC, 0xDD]),
                expectedCommand: opcode, response: Data([0xAA, 0xBB, opcode, 0, 0, 0xCC, 0xDD])))
        }
    }
}
