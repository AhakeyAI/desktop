import XCTest
@testable import AhaKeyConfigAgent

final class ClaudeHookHandlerTests: XCTestCase {
    func testPreToolUseAllowsOnlyWhenPhysicalLeverIsAuto() {
        let output = ClaudeHookHandler.preToolUseOutput(switchState: 0)
        let hook = output?["hookSpecificOutput"] as? [String: Any]
        XCTAssertEqual(hook?["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(hook?["permissionDecision"] as? String, "allow")

        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(switchState: 1))
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(switchState: nil))
    }
}
