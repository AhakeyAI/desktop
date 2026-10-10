import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class DeviceResponseMatcherTests: XCTestCase {
    func testPictureReplyMustEchoRequestedMode() {
        let request = Data([0xAA, 0xBB, 0x83, 2, 0xCC, 0xDD])
        let wrong = Data([0xAA, 0xBB, 0x83, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0xCC, 0xDD])
        var right = wrong
        right[4] = 2
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x83, response: wrong))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x83, response: right))
    }

    func testOrdinaryKeyReplyMustEchoModeAndKey() {
        let request = Data([0xAA, 0xBB, 0x87, 2, 1, 0xCC, 0xDD])
        let reply = Data([0xAA, 0xBB, 0x87, 0, 2, 1, 0, 0, 0, 0xCC, 0xDD])
        var stale = reply
        stale[5] = 0
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x87, response: stale))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x87, response: reply))
    }

    func testReadbackDoesNotAcceptWriteAck() {
        let request = Data([0xAA, 0xBB, 0x95, 0xCC, 0xDD])
        let ack = Data([0xAA, 0xBB, 0x95, 0, 0xCC, 0xDD])
        let readback = Data([0xAA, 0xBB, 0x95, 0, 30, 0, 0xCC, 0xDD])
        XCTAssertFalse(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x95, response: ack))
        XCTAssertTrue(DeviceResponseMatcher.matches(request: request, expectedCommand: 0x95, response: readback))
    }
}
