import XCTest
@testable import AhaKeyConfig
@testable import AhaKeyConfigShared

@MainActor
final class StudioKimiPermissionsModelTests: XCTestCase {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let candidate: StudioKimiPermissionsModel.Candidate
        var state: KimiDesktopLeverState { .init(directory: root) }
        init() throws {
            candidate = .init(target: try .init(home: "/tmp/kimi-home", sessionID: "session-A"), title: "A",
                serverID: "01" + String(repeating: "A", count: 24))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
    private actor Counter {
        var notifications = 0
        func notify() -> Bool { notifications += 1; return true }
    }
    func testInspectionAloneCreatesNoGrantOrPermissionLease() async throws {
        let f = try Fixture(); defer { f.remove() }
        let candidate = f.candidate, counter = Counter()
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { .init(sessions: [candidate], limited: false) }, verify: { _ in true }, notify: { await counter.notify() }))
        await model.inspect()
        XCTAssertEqual(model.candidates, [candidate])
        XCTAssertTrue(try f.state.snapshot().grants.isEmpty); XCTAssertTrue(try f.state.snapshot().leases.isEmpty)
        let notifications = await counter.notifications; XCTAssertEqual(notifications, 0)
    }
    func testConfirmedAuthorizationPersistsOnlySelectedTargetAndDefersNativeWriteToAgent() async throws {
        let f = try Fixture(); defer { f.remove() }
        let candidate = f.candidate, counter = Counter()
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { .init(sessions: [candidate], limited: false) }, verify: { $0 == candidate }, notify: { await counter.notify() }))
        await model.inspect(); await model.authorize(candidate)
        XCTAssertEqual(try f.state.snapshot().grants.map(\.target), [candidate.target])
        XCTAssertEqual(try f.state.snapshot().grants.first?.preferredServerID, candidate.serverID)
        XCTAssertTrue(try f.state.snapshot().leases.isEmpty)
        let notifications = await counter.notifications; XCTAssertEqual(notifications, 1)
    }
    func testStaleCandidateCannotGrantOrNotify() async throws {
        let f = try Fixture(); defer { f.remove() }
        let candidate = f.candidate, counter = Counter()
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { .init(sessions: [candidate], limited: false) }, verify: { _ in false }, notify: { await counter.notify() }))
        await model.inspect(); await model.authorize(candidate)
        XCTAssertTrue(try f.state.snapshot().grants.isEmpty)
        let notifications = await counter.notifications; XCTAssertEqual(notifications, 0)
    }
    func testUnlistedCandidateCannotGrantAnything() async throws {
        let f = try Fixture(); defer { f.remove() }
        let counter = Counter()
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { .init(sessions: [], limited: false) }, verify: { _ in XCTFail("Unlisted"); return true }, notify: { await counter.notify() }))
        await model.authorize(f.candidate)
        XCTAssertTrue(try f.state.snapshot().grants.isEmpty)
        let notifications = await counter.notifications; XCTAssertEqual(notifications, 0)
    }
    func testRevocationRetainsPendingRecovery() async throws {
        let f = try Fixture(); defer { f.remove() }
        try f.state.authorize(f.candidate.target, title: "A")
        let lease = try f.state.prepare(f.candidate.target, baseline: .yolo, intended: .auto)
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { .init(sessions: [], limited: false) }, verify: { _ in false }, notify: { true }))
        model.refresh(); await model.revoke(try XCTUnwrap(model.grants.first))
        XCTAssertTrue(try f.state.snapshot().grants.isEmpty)
        XCTAssertEqual(try f.state.snapshot().leases, [lease])
    }
    func testViewDepartureCannotPublishLateInspection() async throws {
        actor Gate {
            var continuation: CheckedContinuation<Void, Never>?
            func wait() async { await withCheckedContinuation { continuation = $0 } }
            func finish() { continuation?.resume(); continuation = nil }
        }
        let f = try Fixture(); defer { f.remove() }
        let gate = Gate(), started = expectation(description: "Inspection starts"), candidate = f.candidate
        let model = StudioKimiPermissionsModel(state: f.state, access: .init(
            inspect: { started.fulfill(); await gate.wait(); return .init(sessions: [candidate], limited: false) },
            verify: { _ in false }, notify: { true }))
        let task = Task { await model.inspect() }
        await fulfillment(of: [started], timeout: 2)
        model.cancelInspection(); await gate.finish(); await task.value
        XCTAssertTrue(model.candidates.isEmpty); XCTAssertFalse(model.isBusy)
    }
}
