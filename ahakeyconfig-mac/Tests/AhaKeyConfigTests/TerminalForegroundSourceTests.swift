import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class TerminalForegroundSourceTests: XCTestCase {
    @MainActor private final class Harness {
        var target: TerminalForegroundSource.Target? = .init(provider: .terminal,
            instance: WS3ProcessInstance(pid: 200, seconds: 11, microseconds: 0)!)
        var trusted = true
        var readCount = 0
        var authorizationCount = 0
        var stopped = 0
        var pending: CheckedContinuation<String, Error>?
        var changed: (() -> Void)?
        let terminal = WS3TerminalTaskIdentity(device: 123, processGroup: 300,
            leaderStartedSeconds: 12, leaderStartedMicroseconds: 0)!
        func source() -> TerminalForegroundSource {
            .init(access: .init(frontmost: { self.target }, accessibilityTrusted: { self.trusted },
                observe: { _, changed in self.changed = changed; return true },
                stopObserving: { self.stopped += 1; self.changed = nil },
                read: { _ in self.readCount += 1; return try await withCheckedThrowingContinuation { self.pending = $0 } },
                identify: { _ in self.terminal }, authorize: { _ in self.authorizationCount += 1; return true }))
        }
        func resolve(_ value: Result<String, Error> = .success("/dev/ttys999")) {
            let continuation = pending; pending = nil; continuation?.resume(with: value)
        }
    }
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    func testEnablingWithoutPermissionNeverPromptsOrReads() async {
        let harness = Harness(); harness.trusted = false
        let source = harness.source(); source.setEnabled(true)
        XCTAssertEqual(source.status, .accessibility)
        XCTAssertEqual(harness.readCount, 0); XCTAssertEqual(harness.authorizationCount, 0)
        await source.authorize()
        XCTAssertEqual(harness.authorizationCount, 1)
        source.setEnabled(false)
    }
    func testAuthorizationRemainsAvailableWhenReturningToStudioAfterDeniedRead() async {
        let harness = Harness(), source = harness.source()
        source.setEnabled(true)
        let started = await eventually { harness.pending != nil }; XCTAssertTrue(started)
        harness.resolve(.failure(TerminalSelectionQuery.Failure.authorizationRequired))
        let denied = await eventually { source.status == .automation }; XCTAssertTrue(denied)
        XCTAssertTrue(source.canRequestAuthorization)
        harness.target = nil
        source.refresh()
        XCTAssertEqual(source.status, .waiting)
        XCTAssertNil(source.focus)
        XCTAssertTrue(source.canRequestAuthorization, "The button must survive switching back to Studio to use it")
        let reads = harness.readCount
        await source.authorize()
        XCTAssertEqual(harness.authorizationCount, 1)
        XCTAssertEqual(harness.readCount, reads, "Returning to Studio does not read background terminal content")
        source.setEnabled(false)
        XCTAssertFalse(source.canRequestAuthorization)
    }

    func testLateResultAfterDisableCannotRestoreForeground() async {
        let harness = Harness(), source = harness.source()
        source.setEnabled(true)
        let started = await eventually { harness.pending != nil }; XCTAssertTrue(started)
        source.setEnabled(false); harness.resolve()
        await Task.yield()
        XCTAssertNil(source.focus); XCTAssertEqual(source.status, .disabled)
        XCTAssertGreaterThan(harness.stopped, 0); XCTAssertEqual(harness.authorizationCount, 0)
    }
    func testFocusChangeDuringQueryDiscardsOldResultAndRefreshesNewTarget() async {
        let harness = Harness(), source = harness.source()
        source.setEnabled(true)
        let started = await eventually { harness.pending != nil }; XCTAssertTrue(started)
        harness.target = .init(provider: .iTerm,
            instance: WS3ProcessInstance(pid: 201, seconds: 13, microseconds: 0)!)
        source.refresh(); harness.resolve()
        let second = await eventually { harness.readCount == 2 && harness.pending != nil }; XCTAssertTrue(second)
        XCTAssertNil(source.focus)
        harness.resolve()
        let delivered = await eventually { source.focus != nil }; XCTAssertTrue(delivered)
        XCTAssertEqual(source.focus?.application, harness.target?.instance)
        source.setEnabled(false)
    }
    func testAutomationDeniedClearsFocusWithoutRequestingPermission() async {
        let harness = Harness(), source = harness.source()
        source.setEnabled(true)
        let started = await eventually { harness.pending != nil }; XCTAssertTrue(started)
        harness.resolve(.failure(TerminalSelectionQuery.Failure.authorizationRequired))
        let denied = await eventually { source.status == .automation }; XCTAssertTrue(denied)
        XCTAssertNil(source.focus); XCTAssertEqual(harness.authorizationCount, 0)
        source.setEnabled(false)
    }
    func testSameApplicationTabChangeRevokesBeforeNewProofAndDropsStaleQuery() async {
        let harness = Harness(), source = harness.source()
        var values: [WS3ForegroundUpdate.Focus?] = []
        source.onChange = { values.append($0); _ = $1 }
        source.setEnabled(true)
        let first = await eventually { harness.pending != nil }; XCTAssertTrue(first)
        harness.resolve()
        let following = await eventually { source.focus != nil }; XCTAssertTrue(following)
        harness.changed?()
        XCTAssertNil(source.focus); XCTAssertNil(values.last!)
        let second = await eventually { harness.readCount == 2 && harness.pending != nil }; XCTAssertTrue(second)
        harness.changed?() // A further tab change invalidates the outstanding reply.
        harness.resolve()
        let third = await eventually { harness.readCount == 3 && harness.pending != nil }; XCTAssertTrue(third)
        XCTAssertNil(source.focus)
        source.setEnabled(false); harness.resolve()
    }
    func testUnsupportedApplicationImmediatelyRevokesAndIgnoresInFlightRead() async {
        let harness = Harness(), source = harness.source()
        source.setEnabled(true)
        let started = await eventually { harness.pending != nil }; XCTAssertTrue(started)
        harness.target = nil; source.refresh(); harness.resolve()
        await Task.yield()
        XCTAssertNil(source.focus); XCTAssertEqual(source.status, .waiting)
        source.setEnabled(false)
    }
}
