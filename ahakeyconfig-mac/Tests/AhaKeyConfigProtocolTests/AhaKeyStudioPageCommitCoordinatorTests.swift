import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

/// C5G 必测反馈循环：coordinator + recording CommitPort 重放 R4。
@MainActor
final class AhaKeyStudioPageCommitCoordinatorTests: XCTestCase {

    // MARK: - 夹具

    private let deviceID = try! AhaKeyRuntimeDeviceID("DEVICE-1")
    private let screenPage = AhaKeyStudioPageID.screen(modeSlot: 0)
    private let activeSetField = AhaKeyStudioFieldID.screenActiveSet(modeSlot: 0)
    private let profile = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false)

    private struct CommitFailure: LocalizedError {
        var errorDescription: String? { "commit failed for test" }
    }

    @MainActor
    private final class RecordingCommitPort: AhaKeyStudioPageCommitPort {
        private var results: [Result<AhaKeyStudioPageCommitResult, Error>]
        private(set) var snapshots: [AhaKeyStudioPageSnapshot] = []
        private(set) var retryResiduals: [Bool] = []

        init(results: [Result<AhaKeyStudioPageCommitResult, Error>]) {
            self.results = results
        }

        func commitFrozenPage(
            _ snapshot: AhaKeyStudioPageSnapshot,
            retryResidual: Bool
        ) async throws -> AhaKeyStudioPageCommitResult {
            snapshots.append(snapshot)
            retryResiduals.append(retryResidual)
            guard !results.isEmpty else { throw CommitFailure() }
            return try results.removeFirst().get()
        }
    }

    /// 可在 await 中途被测试放行/注入的 port，用于证明 stale 因果。
    @MainActor
    private final class GatedCommitPort: AhaKeyStudioPageCommitPort {
        private(set) var snapshots: [AhaKeyStudioPageSnapshot] = []
        private var continuation: CheckedContinuation<AhaKeyStudioPageCommitResult, Error>?

        var hasReachedPort: Bool { continuation != nil }

        func commitFrozenPage(
            _ snapshot: AhaKeyStudioPageSnapshot,
            retryResidual: Bool
        ) async throws -> AhaKeyStudioPageCommitResult {
            snapshots.append(snapshot)
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func resume(with result: Result<AhaKeyStudioPageCommitResult, Error>) {
            let pending = continuation
            continuation = nil
            pending?.resume(with: result)
        }
    }

    private func field(activeSet: Int) -> AhaKeyStudioFrozenField {
        AhaKeyStudioFrozenField(
            id: activeSetField,
            value: .integer(activeSet),
            isDirty: true,
            baseline: .init(trust: .verified, value: .integer(0))
        )
    }

    private func input(
        activeSet: Int,
        deviceID: AhaKeyRuntimeDeviceID? = nil,
        sessionGeneration: UInt64 = 0,
        transportGeneration: UInt64 = 0,
        profile: AhaKeyOLEDCompatibilityProfile? = nil,
        explicitIntentFieldIDs: Set<AhaKeyStudioFieldID>? = nil,
        retryResidual: Bool = false
    ) -> AhaKeyStudioPageSubmissionInput {
        AhaKeyStudioPageSubmissionInput(
            deviceID: deviceID ?? self.deviceID,
            sessionGeneration: .init(sessionGeneration),
            transportGeneration: .init(transportGeneration),
            snapshot: AhaKeyStudioPageSnapshot(
                pageID: screenPage,
                profile: profile ?? self.profile,
                selectedTaskSet: activeSet,
                overwriteConfirmed: false,
                fields: [field(activeSet: activeSet)]
            ),
            explicitIntentFieldIDs: explicitIntentFieldIDs ?? [activeSetField],
            retryResidual: retryResidual
        )
    }

    private func intentContext(
        activeSet: Int,
        deviceID: AhaKeyRuntimeDeviceID? = nil,
        sessionGeneration: UInt64 = 0,
        transportGeneration: UInt64 = 0,
        profile: AhaKeyOLEDCompatibilityProfile? = nil
    ) -> AhaKeyStudioPageEditIntentContext {
        AhaKeyStudioPageEditIntentContext(
            deviceID: deviceID ?? self.deviceID,
            sessionGeneration: .init(sessionGeneration),
            transportGeneration: .init(transportGeneration),
            pageID: screenPage,
            profile: profile ?? self.profile,
            currentValues: [activeSetField: .integer(activeSet)]
        )
    }

    // MARK: - 1. R4 回放

    func testR4ReplayTwoClicksCallPortTwiceWithOneFreezeEachAndExactTrace() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let acceptedID = AhaKeyRuntimeOperationID()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.accepted(acceptedID)),
        ])
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let first = await coordinator.submit(click, port: port)
        XCTAssertEqual(first, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots.count, 1)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.clickCount, 1)
        XCTAssertEqual(coordinator.portCallCount, 1)

        // 历史 completed operation（R4 的 844F52E4…）只更新 Store 状态；
        // 它不得消费 pending，也不得改动冻结输入。
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)

        let second = await coordinator.submit(click, port: port)
        XCTAssertEqual(second, .accepted(acceptedID))
        XCTAssertEqual(port.snapshots.count, 2)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true)
        XCTAssertEqual(coordinator.pendingPrompt, nil)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.clickCount, 2)
        XCTAssertEqual(coordinator.portCallCount, 2)

        XCTAssertEqual(
            coordinator.trace,
            [
                .init(sequence: 1, pageID: screenPage, confirmed: false, portCalled: true,
                      category: .portNotCalled, phase: .began),
                .init(sequence: 1, pageID: screenPage, confirmed: false, portCalled: true,
                      category: .requiresOverwriteConfirmation, phase: .returned),
                .init(sequence: 2, pageID: screenPage, confirmed: true, portCalled: true,
                      category: .portNotCalled, phase: .began),
                .init(sequence: 2, pageID: screenPage, confirmed: true, portCalled: true,
                      category: .accepted, phase: .returned),
            ]
        )
    }

    // MARK: - 2. 第二次返回分支必须可区分

    func testSecondClickNoOpOutcomeAndTraceAreDistinctFromRequires() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.noOp),
        ])
        let click = input(activeSet: 1)
        coordinator.observeIdentity(click.confirmationIdentity)

        let submitted1 = await coordinator.submit(click, port: port)

        XCTAssertEqual(submitted1, .requiresOverwriteConfirmation)
        let second = await coordinator.submit(click, port: port)
        XCTAssertEqual(second, .noOp)
        XCTAssertEqual(second.traceCategory, .noOp)
        XCTAssertEqual(coordinator.pendingPrompt, nil, "no-op 必须消费 pending")
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true)
        XCTAssertEqual(coordinator.trace.last?.category, .noOp)
    }

    func testSecondClickRequiresAgainKeepsPendingAndIsDistinctFromFirst() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.requiresOverwriteConfirmation),
        ])
        let click = input(activeSet: 1)
        coordinator.observeIdentity(click.confirmationIdentity)

        let submitted2 = await coordinator.submit(click, port: port)

        XCTAssertEqual(submitted2, .requiresOverwriteConfirmation)
        let submitted3 = await coordinator.submit(click, port: port)
        XCTAssertEqual(submitted3, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true, "第二次仍需是 confirmed 提交")
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)
        // 两次 requires 的 trace 必须各自成对，不能被静默合并。
        XCTAssertEqual(coordinator.trace.map(\.phase), [.began, .returned, .began, .returned])
        XCTAssertEqual(coordinator.attemptSequence, 2)
    }

    func testSecondClickErrorOutcomeAndTraceAreNamed() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .failure(CommitFailure()),
        ])
        let click = input(activeSet: 1)
        coordinator.observeIdentity(click.confirmationIdentity)

        _ = await coordinator.submit(click, port: port)
        let second = await coordinator.submit(click, port: port)
        guard case .failed(let reason) = second else {
            return XCTFail("第二次 throw 必须投影为 failed，实得 \(second)")
        }
        XCTAssertEqual(reason, "commit failed for test")
        XCTAssertEqual(second.traceCategory, .failed)
        XCTAssertEqual(coordinator.trace.last?.phase, .failed)
        XCTAssertEqual(coordinator.trace.last?.category, .failed)
        XCTAssertEqual(coordinator.pendingPrompt, nil)
        XCTAssertFalse(coordinator.isSubmitting)
    }

    func testPortNotCalledGuardRejectsConcurrentSubmitWithoutSecondPortCall() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 1)
        coordinator.observeIdentity(click.confirmationIdentity)

        let first = Task { @MainActor in
            await coordinator.submit(click, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        let second = await coordinator.submit(click, port: port)
        XCTAssertEqual(second, .ignoredInFlight)
        XCTAssertEqual(port.snapshots.count, 1, "in-flight 期间不得产生第二次 port 调用")
        XCTAssertEqual(coordinator.trace.last?.category, .portNotCalled)
        XCTAssertEqual(coordinator.trace.last?.portCalled, false)

        port.resume(with: .success(.noOp))
        _ = await first.value
    }

    // MARK: - 3. 上下文 mutation

    func testContextMutationBeforeSecondClickVoidsPendingAndDoesNotResurrect() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.requiresOverwriteConfirmation),
        ])
        let a = input(activeSet: 0)
        let b = input(activeSet: 1)

        coordinator.observeIdentity(a.confirmationIdentity)
        let submitted4 = await coordinator.submit(a, port: port)
        XCTAssertEqual(submitted4, .requiresOverwriteConfirmation)
        XCTAssertEqual(coordinator.pendingPrompt, a.confirmationIdentity)

        // 第二击前 selected set 变化：pending 必须作废。
        coordinator.observeIdentity(b.confirmationIdentity)
        XCTAssertEqual(coordinator.pendingPrompt, nil)

        // 新的“第一次”必须仍是 confirmed=false。
        let submitted5 = await coordinator.submit(b, port: port)
        XCTAssertEqual(submitted5, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, false)

        // A→B→A 不得复活旧 attempt。
        coordinator.observeIdentity(a.confirmationIdentity)
        XCTAssertNotEqual(coordinator.pendingPrompt, a.confirmationIdentity)
        _ = await coordinator.submit(a, port: port)
        XCTAssertEqual(port.snapshots.last?.overwriteConfirmed, false)
    }

    func testDeviceGenerationAndProfileMutationAllVoidPending() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let requires: Result<AhaKeyStudioPageCommitResult, Error> = .success(.requiresOverwriteConfirmation)
        let port = RecordingCommitPort(results: [requires, requires, requires, requires])
        let base = input(activeSet: 0)

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await coordinator.submit(base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)

        let otherDevice = try! AhaKeyRuntimeDeviceID("DEVICE-2")
        coordinator.observeIdentity(input(activeSet: 0, deviceID: otherDevice).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "device 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await coordinator.submit(base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(input(activeSet: 0, sessionGeneration: 1).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "session generation 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await coordinator.submit(base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(input(activeSet: 0, transportGeneration: 1).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "transport generation 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await coordinator.submit(base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(
            input(activeSet: 0, profile: .currentSessionCapable).confirmationIdentity
        )
        XCTAssertNil(coordinator.pendingPrompt, "profile 变化必须作废 pending")
    }

    // MARK: - 4. stale / replay 因果（C5ER1 不得回退）

    func testStaleResultDuringAwaitIsNotConsumed() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let a = input(activeSet: 0)
        coordinator.observeIdentity(a.confirmationIdentity)

        let task = Task { @MainActor in
            await coordinator.submit(a, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // await 期间 context 真变了：在途 attempt 必须永久作废。
        let otherDevice = try! AhaKeyRuntimeDeviceID("DEVICE-2")
        coordinator.observeIdentity(input(activeSet: 0, deviceID: otherDevice).confirmationIdentity)

        port.resume(with: .success(.requiresOverwriteConfirmation))
        let outcome = await task.value
        XCTAssertEqual(outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(coordinator.pendingPrompt, nil, "迟到的 requires 不得铸造 pending")
        XCTAssertFalse(coordinator.isSubmitting)
    }

    func testAcceptedResultDoesNotClearNewerEditIntentRegisteredDuringAwait() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let task = Task { @MainActor in
            await coordinator.submit(click, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // await 期间用户又改了套图：旧的 accepted 结果不得清掉这个新意图。
        coordinator.notePickerSelection(
            activeSet: 1,
            modeSlot: 0,
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            profile: profile
        )

        port.resume(with: .success(.accepted(AhaKeyRuntimeOperationID())))
        let outcome = await task.value
        guard case .accepted = outcome else {
            return XCTFail("第二次提交应 accepted，实得 \(outcome)")
        }
        XCTAssertTrue(
            coordinator.matchingExplicitIntentFieldIDs(intentContext(activeSet: 1)).contains(activeSetField),
            "await 期间登记的新 edit intent 不得被旧 result 消费"
        )
    }

    func testExplicitIntentIsConsumedByAcceptedButNotByRequires() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.accepted(AhaKeyRuntimeOperationID())),
        ])
        coordinator.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            profile: profile
        )
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        _ = await coordinator.submit(click, port: port)
        XCTAssertTrue(
            coordinator.matchingExplicitIntentFieldIDs(intentContext(activeSet: 0)).contains(activeSetField),
            "requires 分支不得消费 edit intent"
        )

        _ = await coordinator.submit(click, port: port)
        XCTAssertFalse(
            coordinator.matchingExplicitIntentFieldIDs(intentContext(activeSet: 0)).contains(activeSetField),
            "accepted 必须消费对应 edit intent"
        )
    }

    // MARK: - 5. 静态接口门

    func testViewOnlySubmitsThroughCoordinatorAndHoldsNoLedger() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewURL = packageRoot.appendingPathComponent("Sources/Views/AhaKeyStudioView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("overwriteConfirmationLedger"),
            "View 不得再直接持有 confirmation ledger"
        )
        XCTAssertFalse(
            source.contains("pageEditIntentLedger"),
            "View 不得再直接持有 edit-intent ledger"
        )
        XCTAssertTrue(
            source.contains("pageCommitCoordinator.submit("),
            "Button action 必须只经 coordinator 单一 submit 接口"
        )
        XCTAssertTrue(
            source.contains("AhaKeyStudioRuntimeStoreCommitPort(store:"),
            "生产提交必须经 CommitPort adapter"
        )
        XCTAssertFalse(
            source.contains("runtimeStore.commitFrozenPage("),
            "View 不得绕过 coordinator 直接调用 Store 写入口"
        )
    }
}
