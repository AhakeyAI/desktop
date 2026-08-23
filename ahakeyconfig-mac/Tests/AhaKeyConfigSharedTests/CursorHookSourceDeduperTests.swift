import XCTest
@testable import AhaKeyConfigShared

final class CursorHookSourceDeduperTests: XCTestCase {
    func testNativeCursorPreToolUseQueriesRuntime() {
        XCTAssertEqual(
            CursorHookSourceDeduper.route(event: "preToolUse", environment: [:]),
            .queryRuntime
        )
    }

    func testLegacyCursorPermissionEventsAreNeutralNoOps() {
        XCTAssertEqual(
            CursorHookSourceDeduper.route(event: "beforeShellExecution", environment: [:]),
            .noOp
        )
        XCTAssertEqual(
            CursorHookSourceDeduper.route(event: "beforeMCPExecution", environment: [:]),
            .noOp
        )
    }

    func testClaudePreToolUseMappedIntoCursorIsNeutralNoOp() {
        XCTAssertEqual(
            CursorHookSourceDeduper.route(
                event: "PreToolUse",
                environment: ["CURSOR_VERSION": "3.17.8"]
            ),
            .noOp
        )
    }

    func testClaudeProjectDirectoryAloneDoesNotIdentifyCursor() {
        XCTAssertEqual(
            CursorHookSourceDeduper.route(
                event: "PreToolUse",
                environment: ["CLAUDE_PROJECT_DIR": "/tmp/project"]
            ),
            .passthrough
        )
    }
}
