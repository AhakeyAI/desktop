import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class DeviceFrameDecoderTests: XCTestCase {
    func testSplitAndCombinedCP4DResponses() {
        var decoder = DeviceFrameDecoder()
        let identity = Data([0xAA, 0xBB, 0x9F, 0x00] + Array("x1-c582-hw1-p1-1.0.0-r001".utf8) + [0xCC, 0xDD])
        let onboarding = Data([0xAA, 0xBB, 0x96, 0x00, 0x02, 0xCC, 0xDD])

        XCTAssertTrue(decoder.append(Data(identity.prefix(5))).isEmpty)
        XCTAssertTrue(decoder.append(Data(identity.dropFirst(5).dropLast(1))).isEmpty)
        XCTAssertEqual(decoder.append(Data([0xDD]) + onboarding), [identity, onboarding])
    }

    func testOrdinaryKeyPayloadMayContainFrameTrailerBytes() {
        var decoder = DeviceFrameDecoder()
        let key = Data([
            0xAA, 0xBB, 0x87, 0x00, 0x01, 0x00, 0x74, 0x04,
            0x12, 0xCC, 0xDD, 0x34, 0x02, 0x4B, 0x31, 0xCC, 0xDD,
        ])
        XCTAssertTrue(decoder.append(Data(key.prefix(11))).isEmpty)
        XCTAssertEqual(decoder.append(Data(key.dropFirst(11))), [key])
    }

    func testSideSwitchReadbackUsesEmbeddedActionLengths() {
        var decoder = DeviceFrameDecoder()
        let switchConfig = Data([
            0xAA, 0xBB, 0x97, 0x00, 0x01, 0x02,
            0x02, 0x04, 0x73, 0x02, 0xCC, 0xDD,
            0x00, 0x00, 0xCC, 0xDD,
        ])
        XCTAssertEqual(decoder.append(switchConfig), [switchConfig])
    }

    func testMalformedLengthDoesNotConsumeFollowingFrame() {
        var decoder = DeviceFrameDecoder()
        let invalidKey = Data([0xAA, 0xBB, 0x87, 0x00, 0x00, 0x00, 0x74, 0xFF])
        let error = Data([0xAA, 0xBB, 0x87, 0x03, 0xCC, 0xDD])
        XCTAssertEqual(decoder.append(invalidKey + error), [error])
    }
}
