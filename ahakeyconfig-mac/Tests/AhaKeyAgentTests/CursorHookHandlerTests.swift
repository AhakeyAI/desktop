import XCTest
@testable import AhaKeyConfigAgent

final class CursorHookHandlerTests: XCTestCase {
    func testAutomaticSwitchExplicitlyAllows() {
        XCTAssertEqual(CursorHookHandler.standardOutput(for: 0), #"{"permission":"allow"}"#)
    }

    func testManualAndUnavailableDeferToCursorNativePermissions() {
        for state in [1, 2, nil] as [Int?] {
            XCTAssertNil(CursorHookHandler.standardOutput(for: state))
        }
    }
}
