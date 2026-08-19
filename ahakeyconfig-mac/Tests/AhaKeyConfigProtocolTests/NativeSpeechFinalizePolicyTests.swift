import XCTest
@testable import AhaKeyConfig

final class NativeSpeechFinalizePolicyTests: XCTestCase {
    func testShortPressNeverBypassesTheGlobalAhaTypeSetting() {
        XCTAssertFalse(
            NativeSpeechFinalizePolicy.shouldBypassAhaType(
                for: .shortPress,
                longPressAhaTypeEnabled: false
            )
        )
    }

    func testLongPressKeepsItsIndependentFastSendChoice() {
        XCTAssertTrue(
            NativeSpeechFinalizePolicy.shouldBypassAhaType(
                for: .longPress,
                longPressAhaTypeEnabled: false
            )
        )
        XCTAssertFalse(
            NativeSpeechFinalizePolicy.shouldBypassAhaType(
                for: .longPress,
                longPressAhaTypeEnabled: true
            )
        )
    }
}
