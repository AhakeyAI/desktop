import XCTest
@testable import AhaKeyConfigShared

final class VerboseLogSessionControllerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// 默认会话时长为 15 分钟。
    func testDefaultDurationIs15Minutes() {
        let session = VerboseLogSessionController()
        XCTAssertEqual(session.duration, 15 * 60)
    }

    /// 开启后激活，到期时间为 now + duration。
    func testStartActivatesSession() {
        var session = VerboseLogSessionController()
        XCTAssertFalse(session.isActive)
        session.start(now: t0)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.endDate, t0.addingTimeInterval(15 * 60))
    }

    /// 注入时钟推进：15 分钟到期自动关闭；差 1 秒不到期不关闭。
    func testAutoStopsAfter15Minutes() {
        var session = VerboseLogSessionController()
        session.start(now: t0)

        XCTAssertFalse(session.advance(to: t0.addingTimeInterval(15 * 60 - 1)))
        XCTAssertTrue(session.isActive)

        XCTAssertTrue(session.advance(to: t0.addingTimeInterval(15 * 60)))
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.endDate)
    }

    /// 手动关闭立即生效，之后的时钟推进不再报自动关闭。
    func testManualStopTakesEffectImmediately() {
        var session = VerboseLogSessionController()
        session.start(now: t0)
        session.stop()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.endDate)
        XCTAssertFalse(session.advance(to: t0.addingTimeInterval(15 * 60)))
    }

    /// 重复开启顺延到期时间。
    func testRestartExtendsExpiry() {
        var session = VerboseLogSessionController()
        session.start(now: t0)
        session.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(session.endDate, t0.addingTimeInterval(20 * 60))
    }
}
