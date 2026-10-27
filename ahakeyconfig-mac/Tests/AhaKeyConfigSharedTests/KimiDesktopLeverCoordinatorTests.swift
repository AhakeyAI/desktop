import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopLeverCoordinatorTests: XCTestCase {
    private actor Native {
        var authority = KimiDesktopLeverCoordinator.Authority.automatic
        var modes: [KimiDesktopLeverState.Target: KimiDesktopPermissionBridge.Mode] = [:]
        var writes: [KimiDesktopPermissionBridge.Mode] = []
        var reads = 0
        var loseWriteReply = false, rejectWrite = false, revokeDuringWrite = false, changeToManualDuringRead = false
        let state: KimiDesktopLeverState
        init(_ state: KimiDesktopLeverState) { self.state = state }
        func seed(_ target: KimiDesktopLeverState.Target, _ mode: KimiDesktopPermissionBridge.Mode) { modes[target] = mode }
        func physical(_ value: KimiDesktopLeverCoordinator.Authority) { authority = value }
        func failure(lost: Bool = false, reject: Bool = false, revoke: Bool = false, changeOnRead: Bool = false) {
            loseWriteReply = lost; rejectWrite = reject; revokeDuringWrite = revoke; changeToManualDuringRead = changeOnRead
        }
        func read(_ target: KimiDesktopLeverState.Target) throws -> KimiDesktopPermissionBridge.Mode {
            reads += 1
            if changeToManualDuringRead { authority = .manual; changeToManualDuringRead = false }
            return try XCTUnwrap(modes[target])
        }
        func write(_ lease: KimiDesktopLeverState.Lease, _ expected: KimiDesktopPermissionBridge.Mode,
                   _ desired: KimiDesktopPermissionBridge.Mode, _ managing: Bool) throws -> KimiDesktopPermissionBridge.Receipt {
            XCTAssertTrue(try state.snapshot().leases.contains { $0.operationID == lease.operationID }, "Journal precedes IO")
            guard modes[lease.target] == expected else { throw KimiDesktopPermissionBridge.Failure.conflict(try XCTUnwrap(modes[lease.target])) }
            writes.append(desired)
            if !rejectWrite { modes[lease.target] = desired }
            if revokeDuringWrite { try state.revoke(lease.target); revokeDuringWrite = false }
            if loseWriteReply { loseWriteReply = false; throw KimiDesktopPermissionBridge.Failure.unavailable }
            return .init(mode: try XCTUnwrap(modes[lease.target]), attemptedWrite: true)
        }
    }
    private func worker(_ state: KimiDesktopLeverState, _ native: Native) -> KimiDesktopLeverCoordinator {
        .init(state: state, dependencies: .init(authority: { await native.authority }, controlEnabled: { true },
            read: { try await native.read($0) }, write: { try await native.write($0, $1, $2, $3) }))
    }
    private func setup() throws -> (URL, KimiDesktopLeverState, KimiDesktopLeverState.Target) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = KimiDesktopLeverState(directory: root)
        let target = try KimiDesktopLeverState.Target(home: "/tmp/kimi-home", sessionID: "session-A")
        return (root, state, target)
    }
    func testAutoManualAndDisconnectRestoreOriginalYolo() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .yolo)
        let engine = worker(state, native)
        _ = await engine.reconcile(hint: .automatic, epoch: 1)
        await native.physical(.manual); _ = await engine.reconcile(hint: .manual, epoch: 1)
        _ = await engine.reconcile(hint: .unmanaged, epoch: 2)
        let writes = await native.writes; XCTAssertEqual(writes, [.auto, .manual, .yolo])
        XCTAssertFalse(try state.hasPendingRecovery())
    }
    func testNoGrantNeverReadsOrWritesConversation() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let native = Native(state); await native.seed(target, .manual)
        _ = await worker(state, native).reconcile(hint: .automatic, epoch: 1)
        let reads = await native.reads, writes = await native.writes
        XCTAssertEqual(reads, 0); XCTAssertTrue(writes.isEmpty)
    }
    func testIdenticalSignalDoesNotPollSessions() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .manual)
        let engine = worker(state, native); _ = await engine.reconcile(hint: .automatic, epoch: 1)
        let reads = await native.reads
        for _ in 0..<5 { _ = await engine.reconcile(hint: .automatic, epoch: 1) }
        let after = await native.reads; XCTAssertEqual(after, reads)
    }
    func testUserChangeSurvivesWorkerRestartAndReconnectionUntilLeverChanges() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .manual)
        let engine = worker(state, native); _ = await engine.reconcile(hint: .automatic, epoch: 1)
        await native.seed(target, .yolo)
        _ = await engine.reconcile(hint: .automatic, epoch: 1, retry: true)
        XCTAssertTrue(try state.snapshot().leases.isEmpty)
        let reopened = worker(state, native)
        _ = await reopened.reconcile(hint: .automatic, epoch: 2)
        let writes = await native.writes; XCTAssertEqual(writes, [.auto])
        await native.physical(.manual); _ = await reopened.reconcile(hint: .manual, epoch: 2)
        let changed = await native.writes; XCTAssertEqual(changed, [.auto, .manual])
    }
    func testRevocationDuringWriteRecoversOriginalPermission() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .yolo); await native.failure(revoke: true)
        _ = await worker(state, native).reconcile(hint: .automatic, epoch: 1)
        let writes = await native.writes; XCTAssertEqual(writes, [.auto, .yolo])
        XCTAssertFalse(try state.hasPendingRecovery())
    }
    func testLostReplyKeepsJournalAndRestartRestoresBaseline() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .yolo); await native.failure(lost: true)
        _ = await worker(state, native).reconcile(hint: .automatic, epoch: 1)
        XCTAssertTrue(try state.hasPendingRecovery())
        _ = await worker(state, native).reconcile(hint: .unmanaged, epoch: 2)
        let writes = await native.writes; XCTAssertEqual(writes, [.auto, .yolo])
        XCTAssertFalse(try state.hasPendingRecovery())
    }
    func testAuthorityChangedDuringReadDoesNotGrantAuto() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .yolo); await native.failure(changeOnRead: true)
        _ = await worker(state, native).reconcile(hint: .automatic, epoch: 1)
        let writes = await native.writes; XCTAssertEqual(writes, [.manual])
    }
    func testFalseReadbackCannotAcknowledgeJournal() async throws {
        let (root, state, target) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        try state.authorize(target, title: "A")
        let native = Native(state); await native.seed(target, .manual); await native.failure(reject: true)
        let outcomes = await worker(state, native).reconcile(hint: .automatic, epoch: 1)
        XCTAssertEqual(outcomes[target], .notSynchronized)
        XCTAssertFalse(try XCTUnwrap(state.snapshot().leases.first).acknowledged)
    }
    func testEveryAuthorizedSessionKeepsItsOwnOriginalMode() async throws {
        let (root, state, first) = try setup(); defer { try? FileManager.default.removeItem(at: root) }
        let second = try KimiDesktopLeverState.Target(home: first.home, sessionID: "session-B")
        for target in [first, second] { try state.authorize(target, title: "Session") }
        let native = Native(state); await native.seed(first, .manual); await native.seed(second, .yolo)
        let engine = worker(state, native)
        _ = await engine.reconcile(hint: .automatic, epoch: 1)
        _ = await engine.reconcile(hint: .unmanaged, epoch: 2)
        let modes = await native.modes; XCTAssertEqual(modes[first], .manual); XCTAssertEqual(modes[second], .yolo)
        XCTAssertFalse(try state.hasPendingRecovery())
    }
}
