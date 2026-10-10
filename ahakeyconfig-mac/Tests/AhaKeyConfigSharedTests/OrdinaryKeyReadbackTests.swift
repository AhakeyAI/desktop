import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class OrdinaryKeyReadbackTests: XCTestCase {
    func testBinaryActionIsKeptIntact() {
        let frame = Data([
            0xAA, 0xBB, 0x87, 0x00, 0x01, 0x00, 0x74, 0x04,
            0x12, 0xCC, 0xDD, 0x34, 0x02, 0x4B, 0x31, 0xCC, 0xDD,
        ])
        let result = OrdinaryKeyReadbackResult.parse(frame, requestedMode: 1, requestedKeyIndex: 0)
        XCTAssertEqual(result, .value(OrdinaryKeyReadback(
            mode: 1, keyIndex: 0, actionType: 0x74,
            action: Data([0x12, 0xCC, 0xDD, 0x34]), description: Data([0x4B, 0x31])
        )))
    }

    func testWrongKeyAndTruncatedPayloadNeverBecomeAppliedState() {
        let frame = Data([0xAA, 0xBB, 0x87, 0x00, 0, 1, 0x73, 2, 0x3E, 0x00, 0, 0xCC, 0xDD])
        XCTAssertEqual(OrdinaryKeyReadbackResult.parse(frame, requestedMode: 0, requestedKeyIndex: 0), .malformed)
        XCTAssertEqual(OrdinaryKeyReadbackResult.parse(Data(frame.dropFirst()), requestedMode: 0, requestedKeyIndex: 1), .malformed)
    }

    func testOversizeFailureIsNotTruncatedToSuccess() {
        let frame = Data([0xAA, 0xBB, 0x87, 0x03, 0xCC, 0xDD])
        XCTAssertEqual(OrdinaryKeyReadbackResult.parse(frame, requestedMode: 0, requestedKeyIndex: 0), .tooLarge)
    }
}
