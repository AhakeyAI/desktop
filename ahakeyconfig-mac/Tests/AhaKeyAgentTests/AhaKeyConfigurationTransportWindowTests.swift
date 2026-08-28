import XCTest
@testable import AhaKeyConfigAgent

/// C-1R1：0x90 暂缓窗口的独立状态机。隔离由 `@MainActor` 表达。
@MainActor
final class AhaKeyConfigurationTransportWindowTests: XCTestCase {

    private func makeWindow() -> AhaKeyConfigurationTransportWindow {
        AhaKeyConfigurationTransportWindow()
    }

    func testSuccessReplaysLastDeferredStateOnce() {
        let window = makeWindow()
        XCTAssertTrue(window.begin())
        XCTAssertEqual(window.evaluateSend(3), .deferAndLog(3))
        XCTAssertEqual(window.evaluateSend(5), .deferAndLog(5))
        XCTAssertEqual(window.end(), .replayAndLog(5))
        XCTAssertEqual(window.evaluateSend(5), .sendNow)
        XCTAssertFalse(window.isActive)
    }

    func testThrowingWorkStillClosesAndReplays() async {
        let window = makeWindow()
        XCTAssertTrue(window.begin())
        XCTAssertEqual(window.evaluateSend(2), .deferAndLog(2))
        struct WorkFailed: Error {}
        do {
            throw WorkFailed()
        } catch {
            XCTAssertEqual(window.end(), .replayAndLog(2))
        }
        XCTAssertFalse(window.isActive)
        XCTAssertEqual(window.evaluateSend(2), .sendNow)
    }

    func testCancelPathClosesLikeThrow() {
        let window = makeWindow()
        XCTAssertTrue(window.begin())
        XCTAssertEqual(window.evaluateSend(7), .deferAndLog(7))
        // 取消与抛错共用同一条 end 收尾：窗口归零时补发最后一次。
        XCTAssertEqual(window.end(), .replayAndLog(7))
        XCTAssertFalse(window.isActive)
    }

    func testConsecutiveStatesKeepOnlyTheLast() {
        let window = makeWindow()
        _ = window.begin()
        XCTAssertEqual(window.evaluateSend(1), .deferAndLog(1))
        XCTAssertEqual(window.evaluateSend(2), .deferAndLog(2))
        XCTAssertEqual(window.evaluateSend(3), .deferAndLog(3))
        XCTAssertEqual(window.end(), .replayAndLog(3))
    }

    func testIdleCloseDoesNotReplay() {
        let window = makeWindow()
        XCTAssertTrue(window.begin())
        XCTAssertEqual(window.end(), .idle)
        XCTAssertEqual(window.evaluateSend(4), .sendNow)
    }

    func testNestedWindowsReplayOnlyOnLastEnd() {
        let window = makeWindow()
        XCTAssertTrue(window.begin())
        XCTAssertFalse(window.begin())
        XCTAssertEqual(window.evaluateSend(9), .deferAndLog(9))
        XCTAssertEqual(window.end(), .stillOpen)
        XCTAssertTrue(window.isActive)
        XCTAssertEqual(window.end(), .replayAndLog(9))
        XCTAssertFalse(window.isActive)
    }

    func testUnmatchedEndIsNotSilentAndDoesNotReplay() {
        let window = makeWindow()
        XCTAssertEqual(window.end(), .unmatchedEnd)
        XCTAssertEqual(window.evaluateSend(1), .sendNow)
        _ = window.begin()
        XCTAssertEqual(window.evaluateSend(1), .deferAndLog(1))
        XCTAssertEqual(window.end(), .replayAndLog(1))
        XCTAssertEqual(window.end(), .unmatchedEnd)
        XCTAssertFalse(window.isActive)
    }

    func testDuplicateDeferredStateIsSilent() {
        let window = makeWindow()
        _ = window.begin()
        XCTAssertEqual(window.evaluateSend(5), .deferAndLog(5))
        XCTAssertEqual(window.evaluateSend(5), .deferSilent)
        XCTAssertEqual(window.evaluateSend(5), .deferSilent)
        XCTAssertEqual(window.evaluateSend(3), .deferAndLog(3))
        XCTAssertEqual(window.evaluateSend(3), .deferSilent)
        XCTAssertEqual(window.end(), .replayAndLog(3))
    }

    func testInactiveEvaluateDoesNotDefer() {
        let window = makeWindow()
        XCTAssertEqual(window.evaluateSend(8), .sendNow)
        XCTAssertFalse(window.isActive)
    }
}
