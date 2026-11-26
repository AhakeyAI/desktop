import XCTest
@testable import AhaKeyConfigShared

final class StudioKeyboardPreviewStateTests: XCTestCase {
    func testModeChangeShowsDailyThenOnlySelectedArtwork() throws {
        var state = StudioKeyboardPreviewState(mode: 2)
        let timer = try XCTUnwrap(state.send(.selectMode(0)))
        XCTAssertEqual(timer.milliseconds, 1100)
        XCTAssertEqual(state.scene, .daily)
        XCTAssertEqual(state.mode, 0)
        XCTAssertNil(state.send(.advance(revision: timer.revision)))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 0)
        let revision = state.revision
        XCTAssertNil(state.send(.selectMode(0)))
        XCTAssertEqual(state.revision, revision)
        XCTAssertNil(state.send(.advance(revision: revision)))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 0, "Idle playback must not cycle to another Mode")
    }

    func testShortPowerCyclesExactlyOnceWhenOnIncludingWraparound() throws {
        var state = StudioKeyboardPreviewState(mode: 3)
        let timer = try XCTUnwrap(state.send(.shortPower))
        XCTAssertEqual(state.mode, 0)
        XCTAssertEqual(state.scene, .daily)
        state.send(.advance(revision: timer.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 0)
    }

    func testLongPowerOffAndShortPowerBootPreserveMode() throws {
        var state = StudioKeyboardPreviewState(mode: 2)
        let off = try XCTUnwrap(state.send(.longPower))
        XCTAssertEqual(state.scene, .shuttingDown)
        state.send(.advance(revision: off.revision))
        XCTAssertEqual(state.scene, .off)
        XCTAssertFalse(state.powered)
        let boot = try XCTUnwrap(state.send(.shortPower))
        XCTAssertEqual(boot.milliseconds, 300)
        XCTAssertEqual(state.mode, 2)
        XCTAssertEqual(state.scene, .boot)
        let connect = try XCTUnwrap(state.send(.advance(revision: boot.revision)))
        XCTAssertEqual(state.scene, .reconnecting)
        let daily = try XCTUnwrap(state.send(.advance(revision: connect.revision)))
        XCTAssertEqual(state.scene, .daily)
        state.send(.advance(revision: daily.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 2)
    }

    func testThemeShowsDailyThenReturnsSameMode() throws {
        var state = StudioKeyboardPreviewState(mode: 1)
        let timer = try XCTUnwrap(state.send(.theme(.light)))
        XCTAssertEqual(state.theme, .light)
        XCTAssertEqual(state.scene, .daily)
        XCTAssertEqual(timer.milliseconds, 2200)
        state.send(.advance(revision: timer.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 1)
    }

    func testThemeAndModeSelectionWhileOffDoNotWakeScreen() throws {
        var state = StudioKeyboardPreviewState()
        let timer = try XCTUnwrap(state.send(.longPower))
        state.send(.advance(revision: timer.revision))
        XCTAssertNil(state.send(.theme(.light)))
        XCTAssertNil(state.send(.selectMode(2)))
        XCTAssertEqual(state.mode, 2)
        XCTAssertEqual(state.scene, .off)
        XCTAssertFalse(state.powered)
    }

    func testLateModeOrThemeTimerCannotWakePoweredOffScreen() throws {
        var state = StudioKeyboardPreviewState()
        let old = try XCTUnwrap(state.send(.selectMode(1)))
        let off = try XCTUnwrap(state.send(.longPower))
        XCTAssertNil(state.send(.advance(revision: old.revision)))
        XCTAssertEqual(state.scene, .shuttingDown)
        state.send(.advance(revision: off.revision))
        state.send(.advance(revision: old.revision))
        XCTAssertEqual(state.scene, .off)
    }

    func testSystemSelectionNoOffersWindowsAndYesReturnsToCurrentMode() throws {
        var state = StudioKeyboardPreviewState(mode: 2)
        state.send(.selectSystem)
        XCTAssertEqual(state.scene, .system(.mac))
        state.send(.answerSystem(false))
        XCTAssertEqual(state.scene, .system(.windows))
        let daily = try XCTUnwrap(state.send(.answerSystem(true)))
        XCTAssertEqual(state.computer, .windows)
        XCTAssertEqual(state.scene, .daily)
        state.send(.advance(revision: daily.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 2)
    }

    func testConnectionAnimationKeepsSelectedModeAndReturnsToArtwork() throws {
        var state = StudioKeyboardPreviewState(mode: 1)
        let connecting = try XCTUnwrap(state.send(.connect))
        XCTAssertFalse(state.connected)
        XCTAssertEqual(state.scene, .reconnecting)
        let daily = try XCTUnwrap(state.send(.advance(revision: connecting.revision)))
        XCTAssertTrue(state.connected)
        XCTAssertEqual(state.scene, .daily)
        state.send(.advance(revision: daily.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 1)
    }

    func testLatestModeWinsOverEarlierScheduledTransition() throws {
        var state = StudioKeyboardPreviewState()
        let old = try XCTUnwrap(state.send(.selectMode(1)))
        let latest = try XCTUnwrap(state.send(.selectMode(3)))
        state.send(.advance(revision: old.revision))
        XCTAssertEqual(state.scene, .daily)
        XCTAssertEqual(state.mode, 3)
        state.send(.advance(revision: latest.revision))
        XCTAssertEqual(state.scene, .artwork)
        XCTAssertEqual(state.mode, 3)
    }
}
