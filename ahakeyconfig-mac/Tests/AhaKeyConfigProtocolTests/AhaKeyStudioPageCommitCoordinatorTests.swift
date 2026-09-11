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
        retryResidual: Bool = false,
        page: AhaKeyStudioPageID? = nil
    ) -> AhaKeyStudioPageSubmissionInput {
        AhaKeyStudioPageSubmissionInput(
            deviceID: deviceID ?? self.deviceID,
            sessionGeneration: .init(sessionGeneration),
            transportGeneration: .init(transportGeneration),
            snapshot: AhaKeyStudioPageSnapshot(
                pageID: page ?? screenPage,
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

        let first = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(first.outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots.count, 1)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.clickCount, 1)
        XCTAssertEqual(coordinator.portCallCount, 1)

        // 历史 completed operation（R4 的 844F52E4…）只更新 Store 状态；
        // 它不得消费 pending，也不得改动冻结输入。
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)

        let second = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(second.outcome, .accepted(acceptedID))
        XCTAssertEqual(port.snapshots.count, 2)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true)
        XCTAssertEqual(coordinator.pendingPrompt, nil)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.clickCount, 2)
        XCTAssertEqual(coordinator.portCallCount, 2)

        XCTAssertEqual(
            coordinator.trace,
            [
                .began(sequence: 1, pageID: screenPage, confirmed: false),
                .portInvoked(sequence: 1, pageID: screenPage, confirmed: false),
                .returned(sequence: 1, pageID: screenPage, confirmed: false,
                          category: .requiresOverwriteConfirmation),
                .began(sequence: 2, pageID: screenPage, confirmed: true),
                .portInvoked(sequence: 2, pageID: screenPage, confirmed: true),
                .returned(sequence: 2, pageID: screenPage, confirmed: true, category: .accepted),
            ]
        )
        // `began` 只证明 Button 同步进入；`portInvoked` 才证明内部 Task 真的调用了 port。
        for event in coordinator.trace where event.phase == .began {
            XCTAssertFalse(event.portInvoked, "`.began` 时 port 尚未被调用")
            XCTAssertEqual(event.category, .pending)
        }
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

        let submitted1 = await runSubmit(coordinator, click, port: port)

        XCTAssertEqual(submitted1.outcome, .requiresOverwriteConfirmation)
        let second = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(second.outcome, .noOp)
        XCTAssertEqual(AhaKeyStudioPageCommitCoordinator.traceCategory(for: second.outcome), .noOp)
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

        let submitted2 = await runSubmit(coordinator, click, port: port)

        XCTAssertEqual(submitted2.outcome, .requiresOverwriteConfirmation)
        let submitted3 = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(submitted3.outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true, "第二次仍需是 confirmed 提交")
        XCTAssertEqual(coordinator.pendingPrompt, click.confirmationIdentity)
        // 两次 requires 的 trace 必须各自成组（began→portInvoked→returned），不能被静默合并。
        XCTAssertEqual(
            coordinator.trace.map(\.phase),
            [.began, .portInvoked, .returned, .began, .portInvoked, .returned]
        )
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

        _ = await runSubmit(coordinator, click, port: port)
        let second = await runSubmit(coordinator, click, port: port)
        guard case .failed(let reason) = second.outcome else {
            return XCTFail("第二次 throw 必须投影为 failed，实得 \(second)")
        }
        XCTAssertEqual(reason, "commit failed for test")
        XCTAssertEqual(AhaKeyStudioPageCommitCoordinator.traceCategory(for: second.outcome), .failed)
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
            await runSubmit(coordinator, click, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        let second = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(second.outcome, .ignoredInFlight)
        XCTAssertEqual(port.snapshots.count, 1, "in-flight 期间不得产生第二次 port 调用")
        XCTAssertEqual(coordinator.trace.last?.category, .inFlightRejected)
        XCTAssertEqual(coordinator.trace.last?.phase, .rejected)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, false)
        XCTAssertFalse(second.outcome.isProjectable, "被拒绝的点击不得投影")

        port.resume(with: .success(.noOp))
        _ = await first.value
    }

    func testSubmitBeforePortRejectsWhenFrozenIdentityDiffersFromLive() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [.success(.accepted(AhaKeyRuntimeOperationID()))])
        let live = input(activeSet: 0)
        let stale = input(activeSet: 1)

        // live 观测是 A；却拿 B 的冻结输入提交 → 必须 superseded 且不调用 port。
        coordinator.observeIdentity(live.confirmationIdentity)
        let outcome = await runSubmit(coordinator, stale, port: port)

        XCTAssertEqual(outcome.outcome, .superseded)
        XCTAssertFalse(outcome.outcome.isProjectable)
        XCTAssertTrue(port.snapshots.isEmpty, "不一致时不得调用 port")
        XCTAssertEqual(coordinator.portCallCount, 0)
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertEqual(coordinator.trace.last?.category, .superseded)
        XCTAssertEqual(coordinator.trace.last?.phase, .superseded)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, false)
        // live identity 未被 frozen input 覆盖。
        XCTAssertEqual(coordinator.currentIdentity, live.confirmationIdentity)
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
        let submitted4 = await runSubmit(coordinator, a, port: port)
        XCTAssertEqual(submitted4.outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(coordinator.pendingPrompt, a.confirmationIdentity)

        // 第二击前 selected set 变化：pending 必须作废。
        coordinator.observeIdentity(b.confirmationIdentity)
        XCTAssertEqual(coordinator.pendingPrompt, nil)

        // 新的“第一次”必须仍是 confirmed=false。
        let submitted5 = await runSubmit(coordinator, b, port: port)
        XCTAssertEqual(submitted5.outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, false)

        // A→B→A 不得复活旧 attempt。
        coordinator.observeIdentity(a.confirmationIdentity)
        XCTAssertNotEqual(coordinator.pendingPrompt, a.confirmationIdentity)
        _ = await runSubmit(coordinator, a, port: port)
        XCTAssertEqual(port.snapshots.last?.overwriteConfirmed, false)
    }

    func testDeviceGenerationAndProfileMutationAllVoidPending() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let requires: Result<AhaKeyStudioPageCommitResult, Error> = .success(.requiresOverwriteConfirmation)
        let port = RecordingCommitPort(results: [requires, requires, requires, requires])
        let base = input(activeSet: 0)

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await runSubmit(coordinator, base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)

        let otherDevice = try! AhaKeyRuntimeDeviceID("DEVICE-2")
        coordinator.observeIdentity(input(activeSet: 0, deviceID: otherDevice).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "device 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await runSubmit(coordinator, base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(input(activeSet: 0, sessionGeneration: 1).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "session generation 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await runSubmit(coordinator, base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(input(activeSet: 0, transportGeneration: 1).confirmationIdentity)
        XCTAssertNil(coordinator.pendingPrompt, "transport generation 变化必须作废 pending")

        coordinator.observeIdentity(base.confirmationIdentity)
        _ = await runSubmit(coordinator, base, port: port)
        XCTAssertEqual(coordinator.pendingPrompt, base.confirmationIdentity)
        coordinator.observeIdentity(
            input(activeSet: 0, profile: .currentSessionCapable).confirmationIdentity
        )
        XCTAssertNil(coordinator.pendingPrompt, "profile 变化必须作废 pending")
    }

    // MARK: - 4. stale / replay 因果（C5ER1 不得回退）

    func testStaleResultDuringAwaitIsSupersededAndNeverProjected() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let a = input(activeSet: 0)
        coordinator.observeIdentity(a.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, a, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // await 期间 context 真变了：在途 attempt 必须永久作废。
        let otherDevice = try! AhaKeyRuntimeDeviceID("DEVICE-2")
        coordinator.observeIdentity(input(activeSet: 0, deviceID: otherDevice).confirmationIdentity)

        port.resume(with: .success(.requiresOverwriteConfirmation))
        let outcome = await task.value
        XCTAssertEqual(outcome.outcome, .superseded, "失效结果不得投影为旧 requires")
        XCTAssertFalse(outcome.outcome.isProjectable)
        XCTAssertNil(coordinator.lastOutcome, "失效结果不得写入 lastOutcome")
        XCTAssertNil(coordinator.pendingPrompt, "迟到的 requires 不得铸造 pending")
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.supersededCount, 1)

        let last = coordinator.trace.last
        XCTAssertEqual(last?.phase, .superseded)
        XCTAssertEqual(last?.category, .superseded)
        XCTAssertEqual(last?.portInvoked, true, "port 确已调用，但结果被作废")
    }

    func testStaleAcceptedDuringAwaitIsSupersededAndDoesNotBecomeCurrentResult() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let a = input(activeSet: 0)
        coordinator.observeIdentity(a.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, a, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // await 期间用户把套图从 A 切到 B。
        coordinator.observeIdentity(input(activeSet: 1).confirmationIdentity)

        port.resume(with: .success(.accepted(AhaKeyRuntimeOperationID())))
        let outcome = await task.value
        XCTAssertEqual(outcome.outcome, .superseded, "迟到的 accepted 不得成为当前页结果")
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.trace.last?.category, .superseded)
        XCTAssertEqual(coordinator.trace.last?.phase, .superseded)
    }

    func testStaleFailureDuringAwaitIsSupersededAndDoesNotRaiseError() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let a = input(activeSet: 0)
        coordinator.observeIdentity(a.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, a, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }
        coordinator.observeIdentity(input(activeSet: 1).confirmationIdentity)

        port.resume(with: .failure(CommitFailure()))
        let outcome = await task.value
        XCTAssertEqual(outcome.outcome, .superseded, "失效的失败不得弹错给当前页")
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertEqual(coordinator.trace.last?.category, .superseded)
        XCTAssertEqual(coordinator.trace.last?.phase, .superseded)
    }

    func testProjectableOutcomeStillUpdatesLastOutcome() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [.success(.noOp)])
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let outcome = await runSubmit(coordinator, click, port: port)
        XCTAssertEqual(outcome.outcome, .noOp)
        XCTAssertTrue(outcome.outcome.isProjectable)
        XCTAssertEqual(coordinator.lastOutcome, .noOp, "有效结果必须照常投影")
    }

    func testAcceptedResultDoesNotClearNewerEditIntentRegisteredDuringAwait() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, click, port: port)
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
        guard case .accepted = outcome.outcome else {
            return XCTFail("第二次提交应 accepted，实得 \(outcome.outcome)")
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

        _ = await runSubmit(coordinator, click, port: port)
        XCTAssertTrue(
            coordinator.matchingExplicitIntentFieldIDs(intentContext(activeSet: 0)).contains(activeSetField),
            "requires 分支不得消费 edit intent"
        )

        _ = await runSubmit(coordinator, click, port: port)
        XCTAssertFalse(
            coordinator.matchingExplicitIntentFieldIDs(intentContext(activeSet: 0)).contains(activeSetField),
            "accepted 必须消费对应 edit intent"
        )
    }

    // MARK: - 5. trace 类型完全枚举（结构性，不抽样）

    /// 穷举 `AhaKeyStudioPageCommitTraceEvent` 的**全部** case，逐一断言派生字段。
    /// 由于事件是 associated-case 类型，phase / portInvoked / category 无法被独立构造，
    /// 因此这份枚举就是完整的合法矩阵，而不是对字符串样本的抽查。
    func testTraceEventDerivedFieldsAreExhaustivelyConsistent() {
        let table: [(event: AhaKeyStudioPageCommitTraceEvent,
                     phase: AhaKeyStudioPageCommitTracePhase,
                     portInvoked: Bool,
                     category: AhaKeyStudioPageCommitTraceCategory,
                     confirmed: Bool)] = [
            (.began(sequence: 7, pageID: screenPage, confirmed: false),
             .began, false, .pending, false),
            (.portInvoked(sequence: 7, pageID: screenPage, confirmed: false),
             .portInvoked, true, .pending, false),
            (.returned(sequence: 7, pageID: screenPage, confirmed: true, category: .accepted),
             .returned, true, .accepted, true),
            (.returned(sequence: 7, pageID: screenPage, confirmed: false, category: .noOp),
             .returned, true, .noOp, false),
            (.returned(sequence: 7, pageID: screenPage, confirmed: false,
                       category: .requiresOverwriteConfirmation),
             .returned, true, .requiresOverwriteConfirmation, false),
            (.returned(sequence: 7, pageID: screenPage, confirmed: false,
                       category: .missingTrustedPageCache),
             .returned, true, .missingTrustedPageCache, false),
            (.returned(sequence: 7, pageID: screenPage, confirmed: false,
                       category: .unsupportedProfile),
             .returned, true, .unsupportedProfile, false),
            (.returned(sequence: 7, pageID: screenPage, confirmed: false,
                       category: .unsupportedPage),
             .returned, true, .unsupportedPage, false),
            (.failed(sequence: 7, pageID: screenPage, confirmed: true),
             .failed, true, .failed, true),
            (.superseded(sequence: 7, pageID: screenPage, confirmed: false, portInvoked: false),
             .superseded, false, .superseded, false),
            (.superseded(sequence: 7, pageID: screenPage, confirmed: true, portInvoked: true),
             .superseded, true, .superseded, true),
            (.rejected(sequence: 7, pageID: screenPage),
             .rejected, false, .inFlightRejected, false),
            (.cancelled(sequence: 7, pageID: screenPage, confirmed: false, portInvoked: false),
             .cancelled, false, .cancelled, false),
            (.cancelled(sequence: 7, pageID: screenPage, confirmed: true, portInvoked: true),
             .cancelled, true, .cancelled, true),
        ]

        // 覆盖全部 case：事件类型目前恰有 7 个 case，上面的表必须把每个 case 都包含。
        let phases = Set(table.map { $0.event.phase })
        XCTAssertEqual(
            phases,
            [.began, .portInvoked, .returned, .failed, .superseded, .rejected, .cancelled],
            "枚举必须覆盖全部 phase（即全部 case）"
        )
        XCTAssertEqual(table.count, 14, "每个 case 的确认/未确认与 port 前后分支都要覆盖")

        for row in table {
            XCTAssertEqual(row.event.phase, row.phase, "\(row.event)")
            XCTAssertEqual(row.event.portInvoked, row.portInvoked, "\(row.event)")
            XCTAssertEqual(row.event.category, row.category, "\(row.event)")
            XCTAssertEqual(row.event.confirmed, row.confirmed, "\(row.event)")
            XCTAssertEqual(row.event.sequence, 7)
            XCTAssertEqual(row.event.pageID, screenPage)
            XCTAssertTrue(row.event.evidenceLine.contains("phase=\(row.phase.rawValue)"))
        }
    }

    /// 运行期产生的 trace 必须全部落在上面穷举出的类型集合内（不存在第 8 种 case）。
    func testRuntimeTraceEventsStayWithinEnumeratedPhases() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        // 前置不一致
        _ = await runSubmit(coordinator, input(activeSet: 1), port: RecordingCommitPort(results: []))
        // requires 后 accepted
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.accepted(AhaKeyRuntimeOperationID())),
        ])
        _ = await runSubmit(coordinator, click, port: port)
        _ = await runSubmit(coordinator, click, port: port)
        // no-op / 失败
        _ = await runSubmit(coordinator, click, port: RecordingCommitPort(results: [.success(.noOp)]))
        _ = await runSubmit(coordinator, click, port: RecordingCommitPort(results: [.failure(CommitFailure())]))
        // 取消
        let gated = GatedCommitPort()
        let cancelTask = Task { @MainActor in
            await runSubmit(coordinator, click, port: gated)
        }
        while !gated.hasReachedPort { await Task.yield() }
        coordinator.cancelInFlight()
        gated.resume(with: .success(.accepted(AhaKeyRuntimeOperationID())))
        _ = await cancelTask.value

        let allowed = Set([AhaKeyStudioPageCommitTracePhase.began, .portInvoked, .returned,
                           .failed, .superseded, .rejected, .cancelled])
        XCTAssertFalse(coordinator.trace.isEmpty)
        for event in coordinator.trace {
            XCTAssertTrue(allowed.contains(event.phase), "未知 phase：\(event.evidenceLine)")
            // port 未调用时不得出现结果类别。
            if !event.portInvoked {
                XCTAssertTrue(
                    event.category == .pending
                        || event.category == .superseded
                        || event.category == .inFlightRejected
                        || event.category == .cancelled,
                    "port 未调用却给出结果类别：\(event.evidenceLine)"
                )
            }
        }
        XCTAssertTrue(coordinator.trace.contains { $0.phase == .portInvoked })
        XCTAssertTrue(coordinator.trace.contains { $0.phase == .cancelled })
        XCTAssertTrue(coordinator.trace.contains { $0.phase == .superseded && !$0.portInvoked })
    }

    // MARK: - 5b. portInvoked 区分「内部 Task 未调度」与「port 已进入但挂起」

    func testBeganWithoutPortInvokedMeansInternalTaskNotScheduled() {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        _ = runSubmitDetached(coordinator, click, port: port)

        // 同步返回后：began 在，portInvoked 还不在——这正是「Button 已进入但内部 Task 尚未调度」。
        let events = coordinator.trace.map(\.phase)
        XCTAssertEqual(events, [.began])
        XCTAssertTrue(coordinator.isSubmitting)
    }

    func testPortInvokedWithoutReturnedMeansPortHung() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, click, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // port 已实际进入但尚未返回：began + portInvoked，无 returned。
        let phases = coordinator.trace.map(\.phase)
        XCTAssertEqual(phases, [.began, .portInvoked])
        XCTAssertTrue(coordinator.isSubmitting)

        port.resume(with: .success(.noOp))
        _ = await task.value
        XCTAssertEqual(coordinator.trace.map(\.phase), [.began, .portInvoked, .returned])
    }

    // MARK: - 5c. 取消策略

    func testCancelInFlightClearsSubmittingAndLateResultIsNotConsumed() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, click, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }
        XCTAssertTrue(coordinator.isSubmitting)

        coordinator.cancelInFlight()
        XCTAssertFalse(coordinator.isSubmitting, "取消后必须立即解除 submitting")
        XCTAssertEqual(coordinator.trace.last?.phase, .cancelled)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, true)

        // 迟到的 port 结果不得被消费或投影。
        port.resume(with: .success(.accepted(AhaKeyRuntimeOperationID())))
        let projection = await task.value
        XCTAssertEqual(projection.outcome, .superseded)
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(
            coordinator.trace.map(\.phase).suffix(2),
            [.cancelled, .superseded]
        )
        // 取消后可以立刻开始新的 attempt（in-flight 已释放）。
        let next = coordinator.start(click, port: RecordingCommitPort(results: [.success(.noOp)]))
        XCTAssertEqual(next, .started)
    }

    func testCancelBeforePortInvokedAlsoReleasesSubmitting() {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        _ = runSubmitDetached(coordinator, click, port: port)
        XCTAssertTrue(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.trace.map(\.phase), [.began])

        coordinator.cancelInFlight()
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.trace.last?.phase, .cancelled)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, false)
    }

    func testCheckedIncrementDoesNotWrap() {
        XCTAssertEqual(AhaKeyStudioPageCommitCoordinator.checkedIncrement(0), 1)
        XCTAssertEqual(AhaKeyStudioPageCommitCoordinator.checkedIncrement(41), 42)
    }


    func testStartIsSynchronousSoBeganAndSubmittingAreVisibleBeforePortReturns() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let before = coordinator.projectionRevision
        let start = coordinator.start(click, port: port)

        // 同步返回时：began 已记录、isSubmitting 已生效、port 尚未调用。
        XCTAssertEqual(start, .started)
        XCTAssertTrue(coordinator.isSubmitting, "start 同步返回即应处于提交中")
        XCTAssertEqual(coordinator.trace.last?.phase, .began)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, false)
        XCTAssertEqual(coordinator.trace.last?.category, .pending)

        // 同 tick 的第二次点击：ignored，且不得新增 port 调用。
        guard case .rejected(let rejected) = coordinator.start(click, port: port) else {
            return XCTFail("同 tick 第二次点击必须被拒绝")
        }
        XCTAssertEqual(rejected.outcome, .ignoredInFlight)
        XCTAssertEqual(coordinator.trace.last?.phase, .rejected)

        // 被拒绝的点击本身也是一次终结投影事件，需要跨过它再等真正的终态。
        let revisionAfterReject = coordinator.projectionRevision
        XCTAssertGreaterThan(revisionAfterReject, before)
        XCTAssertEqual(coordinator.lastProjection?.outcome, .ignoredInFlight)

        while !port.hasReachedPort { await Task.yield() }
        XCTAssertEqual(port.snapshots.count, 1, "port 只允许被调用一次")

        port.resume(with: .success(.noOp))
        while coordinator.projectionRevision == revisionAfterReject { await Task.yield() }
        XCTAssertEqual(coordinator.lastProjection?.outcome, .noOp)
        XCTAssertFalse(coordinator.isSubmitting)
    }

    func testStaleRoundTripBToADuringAwaitStillSupersedes() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let a = input(activeSet: 0)
        let b = input(activeSet: 1)
        coordinator.observeIdentity(a.confirmationIdentity)

        let task = Task { @MainActor in
            await runSubmit(coordinator, a, port: port)
        }
        while !port.hasReachedPort { await Task.yield() }

        // A→B→A：即使回到同一 identity，observation revision 已推进，旧结果仍必须失效。
        coordinator.observeIdentity(b.confirmationIdentity)
        coordinator.observeIdentity(a.confirmationIdentity)

        port.resume(with: .success(.accepted(AhaKeyRuntimeOperationID())))
        let projection = await task.value
        XCTAssertEqual(projection.outcome, .superseded, "A→B→A 往返后旧 accepted 仍须失效")
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertEqual(coordinator.trace.last?.phase, .superseded)
        XCTAssertEqual(coordinator.trace.last?.portInvoked, true)
    }

    func testAcceptedProjectionCarriesFrozenPageIDNotLivePage() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = RecordingCommitPort(results: [.success(.accepted(AhaKeyRuntimeOperationID()))])
        let frozenPage = AhaKeyStudioPageID.screen(modeSlot: 1)

        // live 观测先落在默认页，再切到目标页。
        coordinator.observeIdentity(input(activeSet: 0).confirmationIdentity)
        let click = input(activeSet: 0, page: frozenPage)
        coordinator.observeIdentity(click.confirmationIdentity)

        let projection = await runSubmit(coordinator, click, port: port)
        guard case .accepted = projection.outcome else {
            return XCTFail("应 accepted，实得 \(projection.outcome)")
        }
        XCTAssertEqual(projection.pageID, frozenPage, "投影必须携带冻结 pageID")
    }

    // MARK: - 6. 静态接口门

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
            source.contains("pageCommitCoordinator.start("),
            "Button action 必须同步进入 coordinator 的单一 start 接口"
        )
        XCTAssertFalse(
            source.contains("pageCommitCoordinator.submit("),
            "不得存在先建 Task 再进入 coordinator 的 async submit 路径"
        )
        XCTAssertTrue(
            source.contains("AhaKeyStudioRuntimeStoreCommitPort(store:"),
            "生产提交必须经 CommitPort adapter"
        )
        XCTAssertFalse(
            source.contains("runtimeStore.commitFrozenPage("),
            "View 不得绕过 coordinator 直接调用 Store 写入口"
        )
        XCTAssertTrue(
            source.contains("AhaKeyStudioPageChromeProjector.pageTitle(projection.pageID)"),
            "结果投影必须使用冻结 pageID，而不是 live currentPageID"
        )
    }

    /// C5GR2：Button click path 不得写 live observation、不得写「正在提交」、不得自建 Task。
    func testClickPathDoesNotPublishLiveIdentityNorWriteStatusNorCreateTask() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewURL = packageRoot.appendingPathComponent("Sources/Views/AhaKeyStudioView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)

        let body = try XCTUnwrap(
            Self.functionBody(named: "private func writeCurrentPage(retryResidual: Bool)", in: source),
            "必须能定位 writeCurrentPage"
        )

        XCTAssertFalse(
            body.contains("observeIdentity"),
            "click path 禁止发布 live identity，否则 pre-port gate 恒真"
        )
        XCTAssertFalse(
            body.contains("正在提交"),
            "不得在 start 前把「正在提交」写进共享 status"
        )
        XCTAssertFalse(
            body.contains("Task {") || body.contains("Task<"),
            "异步生命周期必须归 coordinator，View 不得自建 Task"
        )
        XCTAssertTrue(
            body.contains("pageCommitCoordinator.start("),
            "click path 必须调用同步 start"
        )
    }

    /// 从源码里截取指定函数签名的函数体（到下一个同缩进 func 为止）。
    private static func functionBody(named signature: String, in source: String) -> String? {
        guard let start = source.range(of: signature) else { return nil }
        let rest = source[start.lowerBound...]
        guard let end = rest.range(of: "\n    private func ", options: [], range: rest.index(after: rest.startIndex)..<rest.endIndex) else {
            return String(rest)
        }
        return String(rest[rest.startIndex..<end.lowerBound])
    }
}

/// C5GR2：生产路径是同步 `start`；终结投影经 `projectionRevision` 事件发布。
/// 测试经同一接口进入并等待该事件。
@MainActor
private func runSubmit(
    _ coordinator: AhaKeyStudioPageCommitCoordinator,
    _ input: AhaKeyStudioPageSubmissionInput,
    port: any AhaKeyStudioPageCommitPort
) async -> AhaKeyStudioPageCommitProjection {
    let before = coordinator.projectionRevision
    _ = coordinator.start(input, port: port)
    while coordinator.projectionRevision == before {
        await Task.yield()
    }
    return coordinator.lastProjection!
}

/// 只同步进入 attempt、不等投影事件（用于观察 began / portInvoked 的时序窗口）。
@MainActor
@discardableResult
private func runSubmitDetached(
    _ coordinator: AhaKeyStudioPageCommitCoordinator,
    _ input: AhaKeyStudioPageSubmissionInput,
    port: any AhaKeyStudioPageCommitPort
) -> AhaKeyStudioPageCommitStartResult {
    coordinator.start(input, port: port)
}
