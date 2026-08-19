import XCTest
@testable import AhaKeyConfigShared

final class HookStateWatchdogTests: XCTestCase {
    typealias Input = HookStateWatchdog.Input
    typealias Decision = HookStateWatchdog.Decision

    /// 进程活着 + 已超时（长思考场景）：不归位，保持灯效。
    func testTimeoutWithProcessAliveHoldsLight() {
        let decision = HookStateWatchdog.decide(Input(
            lastSentState: 3, elapsedSinceLastHook: 600, timeout: 60,
            isTargetProcessRunning: true
        ))
        XCTAssertEqual(decision, .heldProcessAlive)
    }

    /// 进程死了 + 已超时（崩溃导致 end hook 丢失）：归位。
    func testTimeoutWithProcessGoneResets() {
        let decision = HookStateWatchdog.decide(Input(
            lastSentState: 3, elapsedSinceLastHook: 600, timeout: 60,
            isTargetProcessRunning: false
        ))
        XCTAssertEqual(decision, .resetToIdle)
    }

    /// 未超时：无论进程死活都不归位。
    func testWithinTimeoutNeverResets() {
        XCTAssertEqual(
            HookStateWatchdog.decide(Input(
                lastSentState: 1, elapsedSinceLastHook: 29, timeout: 30,
                isTargetProcessRunning: true
            )),
            .withinTimeout
        )
        XCTAssertEqual(
            HookStateWatchdog.decide(Input(
                lastSentState: 1, elapsedSinceLastHook: 29, timeout: 30,
                isTargetProcessRunning: false
            )),
            .withinTimeout
        )
    }

    /// 非活跃态（Stop=5 / Notification=0）：看门狗不介入，即使超时且进程退出。
    func testNonActiveStateIgnored() {
        for state: UInt8 in [0, 5] {
            XCTAssertEqual(
                HookStateWatchdog.decide(Input(
                    lastSentState: state, elapsedSinceLastHook: 3600, timeout: 60,
                    isTargetProcessRunning: false
                )),
                .notActiveState
            )
        }
    }

    /// 所有活跃态（1/2/3/4/6/7）在超时 + 进程退出时都会归位。
    func testAllActiveStatesResetWhenProcessGone() {
        for state: UInt8 in [1, 2, 3, 4, 6, 7] {
            XCTAssertTrue(HookStateWatchdog.isActiveState(state))
            XCTAssertEqual(
                HookStateWatchdog.decide(Input(
                    lastSentState: state, elapsedSinceLastHook: 61, timeout: 60,
                    isTargetProcessRunning: false
                )),
                .resetToIdle,
                "state \(state) 超时且进程退出应归位"
            )
        }
    }

    /// 恰好到达阈值视为超时（与 Agent 原有 elapsed >= threshold 语义一致）。
    func testExactThresholdCountsAsTimeout() {
        XCTAssertEqual(
            HookStateWatchdog.decide(Input(
                lastSentState: 7, elapsedSinceLastHook: 30, timeout: 30,
                isTargetProcessRunning: false
            )),
            .resetToIdle
        )
        XCTAssertEqual(
            HookStateWatchdog.decide(Input(
                lastSentState: 7, elapsedSinceLastHook: 30, timeout: 30,
                isTargetProcessRunning: true
            )),
            .heldProcessAlive
        )
    }
}
