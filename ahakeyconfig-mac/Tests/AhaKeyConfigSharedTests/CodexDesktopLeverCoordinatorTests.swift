import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexDesktopLeverCoordinatorTests: XCTestCase {
    private let id = "01a11a8c-27dc-7670-9389-e912f24b2d65"
    private func withFixture(_ body: (CodexDesktopLeverState, Runtime) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(.init(directory: root), Runtime())
    }
    private func coordinator(_ state: CodexDesktopLeverState, _ runtime: Runtime) -> CodexDesktopLeverCoordinator {
        .init(state: state, dependencies: .init(authority: { await runtime.proof() }, controlEnabled: { true },
            discover: { try await runtime.discover($0) }, read: { try await runtime.read($0) }, write: { try await runtime.write($0, $1) }))
    }

    func testNoConsentAndUnverifiedPhysicalAutoNeverGrantFullAccess() async throws {
        try await withFixture { state, runtime in
            let worker = coordinator(state, runtime)
            _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            var counts = await runtime.counts()
            XCTAssertEqual(counts.reads, 0); XCTAssertEqual(counts.writes, 0)
            try state.setManagementEnabled(true)
            await runtime.setAuthority(.manual)
            _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            counts = await runtime.counts()
            XCTAssertEqual(counts.writes, 0, "A raw auto hint is not a fresh grant")
        }
    }

    func testBothDirectionsReadBackAndIdenticalHeartbeatDoesNotPollDesktop() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            let worker = coordinator(state, runtime)
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            XCTAssertEqual(result[id], .nextTurn)
            let counts = await runtime.counts()
            for _ in 0..<20 { _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0) }
            let repeated = await runtime.counts()
            XCTAssertEqual(repeated.reads, counts.reads); XCTAssertEqual(repeated.writes, counts.writes)
            await runtime.setAuthority(.manual)
            let manual = await worker.reconcile(threadIDs: [id], hint: .manual, epoch: 0)
            XCTAssertEqual(manual[id], .nextTurn)
            let current = await runtime.current()
            XCTAssertEqual(current, Runtime.baseline)
            try state.setManagementEnabled(false)
            _ = await worker.reconcile(threadIDs: [id], hint: .unmanaged, epoch: 0)
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testRevocationDuringSubmittedAutomaticWriteRestoresBeforeFinishing() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            await runtime.holdNextWrite()
            let worker = coordinator(state, runtime)
            let first = Task { await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0) }
            await runtime.waitForWrite()
            try state.setManagementEnabled(false)
            _ = await worker.reconcile(threadIDs: [id], hint: .unmanaged, epoch: 1)
            await runtime.releaseWrite()
            let result = await first.value
            XCTAssertEqual(result[id], .restored)
            let current = await runtime.current()
            XCTAssertEqual(current, Runtime.baseline)
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testRapidAutoToManualDoesNotPublishLateAutomaticResult() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            await runtime.holdNextWrite()
            let worker = coordinator(state, runtime)
            let first = Task { await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0) }
            await runtime.waitForWrite()
            await runtime.setAuthority(.manual)
            _ = await worker.reconcile(threadIDs: [id], hint: .manual, epoch: 0)
            await runtime.releaseWrite()
            let result = await first.value
            XCTAssertEqual(result[id], .nextTurn)
            let current = await runtime.current()
            XCTAssertEqual(current, Runtime.baseline)
            XCTAssertTrue(try state.snapshot().leases[0].acknowledged)
        }
    }

    func testLostReplyIsResolvedByNativeReadbackAndJournalSurvivesRestart() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            await runtime.loseReplies()
            var worker = coordinator(state, runtime)
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            XCTAssertEqual(result[id], .nextTurn)
            XCTAssertTrue(try state.snapshot().leases[0].acknowledged)
            await runtime.restartOwner()
            worker = coordinator(state, runtime)
            let restored = await worker.reconcile(threadIDs: [], hint: .unmanaged, epoch: 1)
            XCTAssertEqual(restored[id], .restored)
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
            let current = await runtime.current()
            XCTAssertEqual(current, Runtime.baseline)
        }
    }

    func testIndependentNativeUserChangeIsPreservedEvenDuringRecoveryRetries() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            let worker = coordinator(state, runtime)
            _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            let userChoice = try CodexDesktopSessionBridge.Settings(encoded: Data("{\"approvalPolicy\":\"on-request\",\"permissions\":\":read-only\"}".utf8))
            await runtime.setCurrent(userChoice)
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0, retry: true)
            XCTAssertEqual(result[id], .externalChange)
            let counts = await runtime.counts()
            _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0, retry: true)
            let after = await runtime.counts()
            XCTAssertEqual(after.writes, counts.writes)
            let current = await runtime.current()
            XCTAssertEqual(current, userChoice)
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testPositiveTransportReplyWithoutNativeChangeNeverAcknowledgesGrant() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            await runtime.ignoreWrites()
            let worker = coordinator(state, runtime)
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            XCTAssertEqual(result[id], .notSynchronized)
            XCTAssertFalse(try state.snapshot().leases[0].acknowledged)
            try state.setManagementEnabled(false)
            _ = await worker.reconcile(threadIDs: [], hint: .unmanaged, epoch: 1)
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testUserCanReturnToTheOriginalOrdinaryModeAfterAnAcknowledgedGrant() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            let worker = coordinator(state, runtime)
            _ = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            await runtime.setCurrent(Runtime.baseline) // User chooses request approval in Codex.
            let before = await runtime.counts()
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0, retry: true)
            XCTAssertEqual(result[id], .externalChange)
            let after = await runtime.counts()
            XCTAssertEqual(after.writes, before.writes, "A confirmed old auto value must not conceal the user's manual choice")
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }

    func testUnstablePhysicalProofHasABoundedRetryLoopAndNoWrites() async throws {
        try await withFixture { state, runtime in
            try state.setManagementEnabled(true)
            await runtime.flapAuthority()
            let worker = coordinator(state, runtime)
            let result = await worker.reconcile(threadIDs: [id], hint: .verifiedAutomatic, epoch: 0)
            XCTAssertEqual(result[id], .notSynchronized)
            let counts = await runtime.counts()
            XCTAssertEqual(counts.writes, 0)
            XCTAssertLessThanOrEqual(counts.proofs, 8)
        }
    }

    private actor Runtime {
        static let baseline = try! CodexDesktopSessionBridge.Settings(encoded: Data("{\"approvalPolicy\":\"on-request\",\"permissions\":\":workspace\"}".utf8))
        private var settings = baseline
        private var owner = CodexDesktopSessionBridge.Owner(threadID: "01a11a8c-27dc-7670-9389-e912f24b2d65", clientID: "71efe1c2-e444-41ea-934d-9185e2c310aa")
        private var authority = CodexDesktopLeverCoordinator.Authority.verifiedAutomatic
        private var reads = 0, writes = 0, proofs = 0
        private var hold = false, lostReply = false, ignore = false, flap = false
        private var release: CheckedContinuation<Void, Never>?
        private var writeStarted = false
        private var startedWaiter: CheckedContinuation<Void, Never>?
        func setAuthority(_ value: CodexDesktopLeverCoordinator.Authority) { authority = value }
        func proof() -> CodexDesktopLeverCoordinator.Authority {
            proofs += 1
            return flap ? (proofs.isMultiple(of: 2) ? .manual : .verifiedAutomatic) : authority
        }
        func discover(_ id: String) throws -> CodexDesktopSessionBridge.Owner {
            guard id == owner.threadID else { throw CodexDesktopSessionBridge.BridgeError.invalidTarget }; return owner
        }
        func read(_ target: CodexDesktopSessionBridge.Owner) throws -> CodexDesktopSessionBridge.Settings {
            guard target == owner else { throw CodexDesktopSessionBridge.BridgeError.ownerChanged }
            reads += 1; return settings
        }
        func write(_ target: CodexDesktopSessionBridge.Owner, _ value: CodexDesktopSessionBridge.Settings) async throws {
            guard target == owner else { throw CodexDesktopSessionBridge.BridgeError.ownerChanged }
            writes += 1
            if !ignore { settings = value }
            writeStarted = true; startedWaiter?.resume(); startedWaiter = nil
            if hold { hold = false; await withCheckedContinuation { release = $0 } }
            if lostReply { throw CodexDesktopSessionBridge.BridgeError.timedOut }
        }
        func current() -> CodexDesktopSessionBridge.Settings { settings }
        func setCurrent(_ value: CodexDesktopSessionBridge.Settings) { settings = value }
        func holdNextWrite() { hold = true; writeStarted = false }
        func waitForWrite() async {
            if !writeStarted { await withCheckedContinuation { startedWaiter = $0 } }
        }
        func releaseWrite() { release?.resume(); release = nil }
        func loseReplies() { lostReply = true }
        func ignoreWrites() { ignore = true }
        func flapAuthority() { flap = true }
        func restartOwner() { owner = .init(threadID: owner.threadID, clientID: UUID().uuidString) }
        func counts() -> (reads: Int, writes: Int, proofs: Int) { (reads, writes, proofs) }
    }
}
