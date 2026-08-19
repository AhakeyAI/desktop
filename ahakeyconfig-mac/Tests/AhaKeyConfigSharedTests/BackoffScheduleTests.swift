import XCTest
@testable import AhaKeyConfigShared

final class BackoffScheduleTests: XCTestCase {

    /// 默认序列：4s → 8s → 15s → 30s 封顶，持续空转保持 30s。
    func testDefaultSequenceCapsAtThirty() {
        var schedule = BackoffSchedule()
        XCTAssertEqual(schedule.currentInterval, 4)
        XCTAssertEqual(schedule.next(), 4)
        XCTAssertEqual(schedule.next(), 8)
        XCTAssertEqual(schedule.next(), 15)
        XCTAssertEqual(schedule.next(), 30)
        XCTAssertEqual(schedule.next(), 30)
        XCTAssertEqual(schedule.next(), 30)
        XCTAssertEqual(schedule.currentInterval, 30)
    }

    /// reset 后回到第一级 4s。
    func testResetReturnsToFirstInterval() {
        var schedule = BackoffSchedule()
        _ = schedule.next()
        _ = schedule.next()
        _ = schedule.next()
        XCTAssertEqual(schedule.currentInterval, 30)
        schedule.reset()
        XCTAssertEqual(schedule.currentInterval, 4)
        XCTAssertEqual(schedule.next(), 4)
        XCTAssertEqual(schedule.next(), 8)
    }

    /// 间隔序列可注入：自定义序列同样逐级推进并在末值封顶。
    func testCustomIntervals() {
        var schedule = BackoffSchedule(intervals: [1, 2])
        XCTAssertEqual(schedule.next(), 1)
        XCTAssertEqual(schedule.next(), 2)
        XCTAssertEqual(schedule.next(), 2)
        schedule.reset()
        XCTAssertEqual(schedule.next(), 1)
    }

    /// 空序列注入时回落到默认序列，不崩溃。
    func testEmptyIntervalsFallBackToDefault() {
        let schedule = BackoffSchedule(intervals: [])
        XCTAssertEqual(schedule.intervals, [4, 8, 15, 30])
    }
}
