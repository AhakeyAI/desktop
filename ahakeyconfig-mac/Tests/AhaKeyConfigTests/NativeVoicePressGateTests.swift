import XCTest
@testable import AhaKeyConfig

final class NativeVoicePressGateTests: XCTestCase {
    func testOverlappingAliasCannotReplaceOwnerOrReleaseIt() throws {
        var gate = NativeVoicePressGate()
        let owner = try XCTUnwrap(gate.begin(code: 79))
        XCTAssertNil(gate.begin(code: 80))
        XCTAssertNil(gate.begin(code: 79))
        XCTAssertFalse(gate.end(code: 80))
        XCTAssertTrue(gate.isCurrent(owner))
        XCTAssertTrue(gate.end(code: 79))
        XCTAssertFalse(gate.isCurrent(owner))
        XCTAssertFalse(gate.end(code: 79))
    }

    func testCancelInvalidatesQueuedThresholdAfterTwoDowns() throws {
        var gate = NativeVoicePressGate()
        let pending = try XCTUnwrap(gate.begin(code: 79))
        XCTAssertNil(gate.begin(code: 80))
        gate.cancel()
        // This is the same validity check used before a queued threshold starts audio.
        XCTAssertFalse(gate.isCurrent(pending))
        XCTAssertFalse(gate.end(code: 79))
        XCTAssertFalse(gate.end(code: 80))
    }

    func testOldThresholdCannotStartAfterNewPressWithSameCode() throws {
        var gate = NativeVoicePressGate()
        let old = try XCTUnwrap(gate.begin(code: 79))
        gate.cancel()
        let current = try XCTUnwrap(gate.begin(code: 79))
        XCTAssertFalse(gate.isCurrent(old))
        XCTAssertTrue(gate.isCurrent(current))
        XCTAssertTrue(gate.end(code: 79))
        XCTAssertFalse(gate.isCurrent(current))
    }
}
