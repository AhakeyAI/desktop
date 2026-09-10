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
                .init(sequence: 1, pageID: screenPage, confirmed: false, portCalled: false,
                      category: .pending, phase: .began),
                .init(sequence: 1, pageID: screenPage, confirmed: false, portCalled: true,
                      category: .requiresOverwriteConfirmation, phase: .returned),
                .init(sequence: 2, pageID: screenPage, confirmed: true, portCalled: false,
                      category: .pending, phase: .began),
                .init(sequence: 2, pageID: screenPage, confirmed: true, portCalled: true,
                      category: .accepted, phase: .returned),
            ]
        )
        // trace 必须自洽：`.began` 不能同时声称 port 已调用。
        for event in coordinator.trace where event.phase == .began {
            XCTAssertFalse(event.portCalled, "`.began` 时 port 尚未被调用")
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
        XCTAssertEqual(second.outcome.traceCategory, .noOp)
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

        _ = await runSubmit(coordinator, click, port: port)
        let second = await runSubmit(coordinator, click, port: port)
        guard case .failed(let reason) = second.outcome else {
            return XCTFail("第二次 throw 必须投影为 failed，实得 \(second)")
        }
        XCTAssertEqual(reason, "commit failed for test")
        XCTAssertEqual(second.outcome.traceCategory, .failed)
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
        XCTAssertEqual(coordinator.trace.last?.portCalled, false)
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
        XCTAssertEqual(coordinator.trace.last?.portCalled, false)
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
        XCTAssertEqual(last?.portCalled, true, "port 确已调用，但结果被作废")
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

    // MARK: - 5. trace 合法组合矩阵

    /// 严格状态矩阵：只有这些 (phase, portCalled, category) 组合是合法的。
    private static let legalTraceCombinations: Set<String> = [
        "began|false|pending",
        "returned|true|accepted",
        "returned|true|noOp",
        "returned|true|requiresOverwriteConfirmation",
        "returned|true|missingTrustedPageCache",
        "returned|true|unsupportedProfile",
        "returned|true|unsupportedPage",
        "failed|true|failed",
        "superseded|false|superseded",
        "superseded|true|superseded",
        "rejected|false|inFlightRejected",
    ]

    private func assertLegalTrace(
        _ coordinator: AhaKeyStudioPageCommitCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for event in coordinator.trace {
            let key = "\(event.phase.rawValue)|\(event.portCalled)|\(event.category.rawValue)"
            XCTAssertTrue(
                Self.legalTraceCombinations.contains(key),
                "非法 trace 组合：\(key)",
                file: file,
                line: line
            )
        }
    }

    func testTraceMatrixRejectsEveryCombinationProducedByKnownPaths() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        // 1) 前置不一致 → superseded|false
        _ = await runSubmit(coordinator, input(activeSet: 1), port: RecordingCommitPort(results: []))
        // 2) requires 后 accepted → began / returned
        let port = RecordingCommitPort(results: [
            .success(.requiresOverwriteConfirmation),
            .success(.accepted(AhaKeyRuntimeOperationID())),
        ])
        _ = await runSubmit(coordinator, click, port: port)
        _ = await runSubmit(coordinator, click, port: port)
        // 3) no-op 与失败
        _ = await runSubmit(coordinator, click, port: RecordingCommitPort(results: [.success(.noOp)]))
        _ = await runSubmit(coordinator, click, port: RecordingCommitPort(results: [.failure(CommitFailure())]))

        assertLegalTrace(coordinator)
        XCTAssertTrue(
            coordinator.trace.contains { $0.phase == .superseded && !$0.portCalled },
            "应出现前置不一致的 superseded"
        )
        XCTAssertTrue(
            coordinator.trace.contains { $0.phase == .returned && $0.category == .accepted }
        )
        XCTAssertTrue(
            coordinator.trace.contains { $0.phase == .failed }
        )
    }

    func testTraceMatrixRejectsIllegalCombinationsByConstruction() {
        // 逐个枚举矩阵外的组合，确认判定函数确实会拒绝（防止矩阵断言写成永真）。
        let illegal = [
            "began|true|pending",
            "began|false|portNotCalled",
            "began|true|portNotCalled",
            "returned|false|accepted",
            "superseded|false|accepted",
            "rejected|true|inFlightRejected",
            "failed|false|failed",
        ]
        for key in illegal {
            XCTAssertFalse(
                Self.legalTraceCombinations.contains(key),
                "非法组合不得进入合法矩阵：\(key)"
            )
        }
    }

    func testStartIsSynchronousSoBeganAndSubmittingAreVisibleBeforePortReturns() async {
        let coordinator = AhaKeyStudioPageCommitCoordinator()
        let port = GatedCommitPort()
        let click = input(activeSet: 0)
        coordinator.observeIdentity(click.confirmationIdentity)

        let start = coordinator.start(click, port: port)

        // 同步返回时：began 已记录、isSubmitting 已生效、port 尚未返回。
        XCTAssertTrue(coordinator.isSubmitting, "start 同步返回即应处于提交中")
        XCTAssertEqual(coordinator.trace.last?.phase, .began)
        XCTAssertEqual(coordinator.trace.last?.portCalled, false)
        XCTAssertEqual(coordinator.trace.last?.category, .pending)

        // 同 tick 的第二次点击：ignored，且不得新增 port 调用。
        guard case .rejected(let rejected) = coordinator.start(click, port: port) else {
            return XCTFail("同 tick 第二次点击必须被拒绝")
        }
        XCTAssertEqual(rejected.outcome, .ignoredInFlight)
        XCTAssertEqual(coordinator.trace.last?.phase, .rejected)

        while !port.hasReachedPort { await Task.yield() }
        XCTAssertEqual(port.snapshots.count, 1, "port 只允许被调用一次")

        guard case .started(let task) = start else { return XCTFail("第一次必须 started") }
        port.resume(with: .success(.noOp))
        let projection = await task.value
        XCTAssertEqual(projection.outcome, .noOp)
        XCTAssertFalse(coordinator.isSubmitting)
        assertLegalTrace(coordinator)
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
        XCTAssertEqual(coordinator.trace.last?.portCalled, true)
        assertLegalTrace(coordinator)
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
}

/// C5GR1：生产路径是同步 `start`（began/isSubmitting 立即可见）。测试统一用它并等待结果。
@MainActor
private func runSubmit(
    _ coordinator: AhaKeyStudioPageCommitCoordinator,
    _ input: AhaKeyStudioPageSubmissionInput,
    port: any AhaKeyStudioPageCommitPort
) async -> AhaKeyStudioPageCommitProjection {
    switch coordinator.start(input, port: port) {
    case .rejected(let projection): return projection
    case .started(let task): return await task.value
    }
}
