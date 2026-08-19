import XCTest
@testable import AhaKeyConfigShared

final class CodexHookStatePlanTests: XCTestCase {
    func testPostToolUseSchedulesStopFallback() {
        XCTAssertEqual(
            CodexHookStatePlan.make(stateValue: 2),
            CodexHookStatePlan(
                command: .stateWithReset,
                stateValue: 2,
                resetValue: 5,
                delayMilliseconds: 12_000
            )
        )
    }

    func testPreToolUseCancelsFallbackWithOrdinaryStateCommand() {
        XCTAssertEqual(
            CodexHookStatePlan.make(stateValue: 3),
            CodexHookStatePlan(
                command: .state,
                stateValue: 3,
                resetValue: nil,
                delayMilliseconds: nil
            )
        )
    }
}
