import XCTest
@testable import AhaKeyConfigShared

final class StateCommandWritePolicyTests: XCTestCase {
    func testPrefersAcknowledgedWriteWhenBothKindsAreAvailable() {
        XCTAssertEqual(
            StateCommandWritePolicy.choose(
                supportsWrite: true,
                supportsWriteWithoutResponse: true
            ),
            .withResponse
        )
    }

    func testFallsBackToUnacknowledgedWriteWhenRequired() {
        XCTAssertEqual(
            StateCommandWritePolicy.choose(
                supportsWrite: false,
                supportsWriteWithoutResponse: true
            ),
            .withoutResponse
        )
    }

    func testParsesFirmwareStateCommandAcknowledgement() {
        XCTAssertEqual(
            StateCommandAcknowledgement.parse(
                Data([0xAA, 0xBB, 0x90, 0x00, 0xCC, 0xDD])
            ),
            StateCommandAcknowledgement(stateCommand: 0x90, resultCode: 0)
        )
    }

    func testRejectsOtherCommandAcknowledgements() {
        XCTAssertNil(
            StateCommandAcknowledgement.parse(
                Data([0xAA, 0xBB, 0x91, 0x00, 0xCC, 0xDD])
            )
        )
    }
}
