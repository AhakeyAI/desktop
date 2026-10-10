import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class DeviceNotificationFramerTests: XCTestCase {
    func testSplitStatusAndLegacyResponse() {
        var framer = DeviceNotificationFramer()
        let status = Data([0xAA, 0xBB, 0x00, 80, 0, 1, 0, 2, 3, 1, 35, 0xCC, 0xDD])
        let legacy = Data([0xAA, 0xBB, 0x83, 0, 0xCC, 0xDD])
        XCTAssertEqual(framer.append(Data(status.prefix(3))), [])
        XCTAssertEqual(framer.append(Data(status.dropFirst(3))), [status])
        XCTAssertEqual(framer.append(legacy), [legacy])
    }

    func testLegacyStatusWithoutBrightness() {
        var framer = DeviceNotificationFramer()
        let status = Data([0xAA, 0xBB, 0x00, 80, 0, 1, 0, 2, 3, 1, 0xCC, 0xDD])
        XCTAssertEqual(framer.append(status), [status])
    }

    func testResetDropsPartialFrameAcrossConnections() {
        var framer = DeviceNotificationFramer()
        XCTAssertTrue(framer.append(Data([0xAA, 0xBB, 0x00])).isEmpty)
        framer.reset()
        let legacy = Data([0xAA, 0xBB, 0x81, 0, 0xCC, 0xDD])
        XCTAssertEqual(framer.append(legacy), [legacy])
    }

    func testExpiredFragmentDoesNotConsumeNextNotification() {
        var framer = DeviceNotificationFramer()
        XCTAssertTrue(framer.append(Data([0xAA, 0xBB, 0x00]), at: 10).isEmpty)
        let legacy = Data([0xAA, 0xBB, 0x81, 0, 0xCC, 0xDD])
        XCTAssertEqual(framer.append(legacy, at: 13), [legacy])
    }
}
