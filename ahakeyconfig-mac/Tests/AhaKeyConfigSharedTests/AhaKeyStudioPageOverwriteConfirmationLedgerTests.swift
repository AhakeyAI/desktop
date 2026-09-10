import XCTest
@testable import AhaKeyConfigShared

/// C5ER1：attempt token + monotonic revision。迟到结果不得复活已作废确认。
final class AhaKeyStudioPageOverwriteConfirmationLedgerTests: XCTestCase {
    func testCapturedC5BWR2SequenceKeepsPendingWithoutOperationsSeam() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let unconfirmed = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(unconfirmed),
            .requiresOverwriteConfirmation
        )

        let identity = makeIdentity(device: device, snapshot: unconfirmed)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity).commitKind,
            .writeAndActivate
        )

        installPending(on: &ledger, identity: identity)
        XCTAssertTrue(ledger.showsOverwritePrompt(for: identity))
        XCTAssertTrue(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity).commitKind,
            .overwritePage
        )

        _ = try capturedHistoricalOperations(device: device)
        XCTAssertTrue(
            ledger.shouldSubmitConfirmed(for: identity),
            "历史 completed 不进入 ledger；接口不存在 operations 方法"
        )

        let confirmed = capturedActiveSetOnlySnapshot(overwriteConfirmed: true)
        XCTAssertEqual(makeIdentity(device: device, snapshot: confirmed), identity)
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(confirmed) else {
            return XCTFail("第二次相同提交必须进入 write")
        }
        XCTAssertTrue(plan.overwriteSemantic)
        XCTAssertEqual(plan.fieldMask, [.screenActiveSet(modeSlot: 0)])
        XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
        XCTAssertEqual(plan.values[.screenActiveSet(modeSlot: 0)]?.integerValue, 0)
        XCTAssertEqual(plan.activateTaskSet, 0)
        XCTAssertTrue(plan.emitsSetActiveSetOpcode)
        XCTAssertFalse(plan.writeTaskSetA)
        XCTAssertFalse(plan.writeTaskSetB)
        XCTAssertTrue(plan.resources.isEmpty)
        XCTAssertNil(plan.statusLine)

        let acceptedID = AhaKeyRuntimeOperationID(
            UUID(uuidString: "A1111111-0000-4000-8000-000000000001")!
        )
        let confirmedAttempt = ledger.beginAttempt(for: identity)
        ledger.applyCommitResult(
            .accepted(acceptedID),
            attempt: confirmedAttempt,
            currentIdentity: identity
        )
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertNil(ledger.pending)
    }

    func testStaleRequiresAfterIdentityRoundTripDoesNotResurrectPending() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let snapshotA = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        let identityA = makeIdentity(device: device, snapshot: snapshotA)
        ledger.observeCurrentIdentity(identityA)
        let staleAttempt = ledger.beginAttempt(for: identityA)

        var snapshotB = snapshotA
        snapshotB.selectedTaskSet = 1
        let identityB = makeIdentity(device: device, snapshot: snapshotB)
        ledger.observeCurrentIdentity(identityB)
        ledger.observeCurrentIdentity(identityA)

        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: staleAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(ledger.pending)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identityA))

        let freshAttempt = ledger.beginAttempt(for: identityA)
        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: freshAttempt,
            currentIdentity: identityA
        )
        XCTAssertTrue(ledger.shouldSubmitConfirmed(for: identityA))

        let confirmedAttempt = ledger.beginAttempt(for: identityA)
        ledger.applyCommitResult(
            .accepted(AhaKeyRuntimeOperationID()),
            attempt: confirmedAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(ledger.pending)
    }

    func testDeviceGenerationAndProfileRoundTripsVoidInFlightAttempts() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        let snapshot = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        let identityA = makeIdentity(device: device, snapshot: snapshot)

        var deviceLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let deviceAttempt = deviceLedger.beginAttempt(for: identityA)
        let otherDevice = makeIdentity(
            device: try AhaKeyRuntimeDeviceID("OTHER"),
            snapshot: snapshot
        )
        deviceLedger.observeCurrentIdentity(otherDevice)
        deviceLedger.observeCurrentIdentity(identityA)
        deviceLedger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: deviceAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(deviceLedger.pending)

        var sessionLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let sessionAttempt = sessionLedger.beginAttempt(for: identityA)
        let otherSession = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(5),
            transportGeneration: .init(9),
            snapshot: snapshot
        )
        sessionLedger.observeCurrentIdentity(otherSession)
        sessionLedger.observeCurrentIdentity(identityA)
        sessionLedger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: sessionAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(sessionLedger.pending)

        var transportLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let transportAttempt = transportLedger.beginAttempt(for: identityA)
        let otherTransport = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(4),
            transportGeneration: .init(10),
            snapshot: snapshot
        )
        transportLedger.observeCurrentIdentity(otherTransport)
        transportLedger.observeCurrentIdentity(identityA)
        transportLedger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: transportAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(transportLedger.pending)

        var profileLedger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let profileAttempt = profileLedger.beginAttempt(for: identityA)
        var otherProfileSnapshot = snapshot
        otherProfileSnapshot.profile = .legacyStandard
        let otherProfile = makeIdentity(device: device, snapshot: otherProfileSnapshot)
        profileLedger.observeCurrentIdentity(otherProfile)
        profileLedger.observeCurrentIdentity(identityA)
        profileLedger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: profileAttempt,
            currentIdentity: identityA
        )
        XCTAssertNil(profileLedger.pending)
    }

    func testReplayAndOutOfOrderResultsCannotMintOrConsumePending() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let identity = makeIdentity(
            device: device,
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        let first = ledger.beginAttempt(for: identity)
        let second = ledger.beginAttempt(for: identity)

        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: first,
            currentIdentity: identity
        )
        XCTAssertNil(ledger.pending, "被替换的旧 attempt 不得铸造 pending")

        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: second,
            currentIdentity: identity
        )
        XCTAssertEqual(ledger.pending, identity)

        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: second,
            currentIdentity: identity
        )
        XCTAssertEqual(ledger.pending, identity)

        let confirmed = ledger.beginAttempt(for: identity)
        ledger.applyCommitResult(
            .accepted(AhaKeyRuntimeOperationID()),
            attempt: first,
            currentIdentity: identity
        )
        XCTAssertEqual(ledger.pending, identity, "重放旧 accepted 不得消费另一 pending")

        ledger.applyCommitResult(
            .noOp,
            attempt: first,
            currentIdentity: identity
        )
        XCTAssertEqual(ledger.pending, identity)

        ledger.applyCommitResult(
            .accepted(AhaKeyRuntimeOperationID()),
            attempt: confirmed,
            currentIdentity: identity
        )
        XCTAssertNil(ledger.pending)
    }

    func testStaleFailureDoesNotClearUnrelatedPending() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let identity = makeIdentity(
            device: device,
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        let stale = ledger.beginAttempt(for: identity)
        ledger.observeCurrentIdentity(
            makeIdentity(
                device: try AhaKeyRuntimeDeviceID("OTHER"),
                snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
            )
        )
        ledger.observeCurrentIdentity(identity)
        installPending(on: &ledger, identity: identity)
        ledger.noteAttemptFailed(attempt: stale, currentIdentity: identity)
        XCTAssertEqual(ledger.pending, identity)
    }

    func testHistoricalTerminalsDoNotConsumePendingAndOnlyExactAttemptMayConsume() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        let other = try AhaKeyRuntimeDeviceID("OTHER")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let identity = makeIdentity(
            device: device,
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        installPending(on: &ledger, identity: identity)

        _ = try [
            summary(
                id: AhaKeyRuntimeOperationID(UUID(uuidString: "844F52E4-D601-441F-942D-682A69DBF91F")!),
                device: device,
                state: .completed,
                pageID: .screen(modeSlot: 0)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(UUID(uuidString: "F2BAE385-0000-4000-8000-0000000000A1")!),
                device: device,
                state: .completed,
                pageID: .screen(modeSlot: 0)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(),
                device: device,
                state: .failedWithoutWrites,
                pageID: .screen(modeSlot: 0)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(),
                device: device,
                state: .failedWithPartialCommit,
                pageID: .screen(modeSlot: 0)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(),
                device: device,
                state: .completed,
                pageID: .key(modeSlot: 0, role: .voice)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(),
                device: other,
                state: .completed,
                pageID: .screen(modeSlot: 0)
            ),
        ]
        XCTAssertTrue(ledger.shouldSubmitConfirmed(for: identity))

        let consume = ledger.beginAttempt(for: identity)
        ledger.applyCommitResult(
            .accepted(AhaKeyRuntimeOperationID()),
            attempt: consume,
            currentIdentity: identity
        )
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
    }

    func testStaleIdentityIsRejectedAndMustReconfirm() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let base = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        let identity = makeIdentity(device: device, snapshot: base)
        installPending(on: &ledger, identity: identity)

        var dirtyField = base
        dirtyField.fields[0].value = .integer(1)
        let fieldIdentity = makeIdentity(device: device, snapshot: dirtyField)
        ledger.observeCurrentIdentity(fieldIdentity)
        XCTAssertNil(ledger.pending)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(dirtyField),
            .requiresOverwriteConfirmation
        )
    }

    func testFailClosedResultsDropPendingOnlyForMatchingAttempt() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        let identity = makeIdentity(
            device: device,
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        for result in [
            AhaKeyStudioPageCommitResult.noOp,
            .missingTrustedPageCache,
            .unsupportedProfile,
            .unsupportedPage,
        ] {
            var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
            installPending(on: &ledger, identity: identity)
            let attempt = ledger.beginAttempt(for: identity)
            ledger.applyCommitResult(result, attempt: attempt, currentIdentity: identity)
            XCTAssertNil(ledger.pending, "\(result) 必须 fail-closed 丢掉 pending")
        }

        var failed = AhaKeyStudioPageOverwriteConfirmationLedger()
        installPending(on: &failed, identity: identity)
        let failedAttempt = failed.beginAttempt(for: identity)
        failed.noteAttemptFailed(attempt: failedAttempt, currentIdentity: identity)
        XCTAssertNil(failed.pending)
    }

    func testPendingChromeStaysOverwritePageWhileAssemblerWouldWrite() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let snapshot = AhaKeyStudioPageSnapshot(
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            selectedTaskSet: 0,
            overwriteConfirmed: false,
            fields: [
                AhaKeyStudioFrozenField(
                    id: .screenActiveSet(modeSlot: 0),
                    value: .integer(0),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(1))
                ),
            ]
        )
        guard case .write = AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot) else {
            return XCTFail("verified active-set-only 未确认时应由 page-base 而不是 assembler 要求确认")
        }
        let identity = makeIdentity(device: device, session: 1, transport: 1, snapshot: snapshot)
        installPending(on: &ledger, identity: identity)
        let chrome = ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity)
        XCTAssertEqual(chrome.commitKind, .overwritePage)
        XCTAssertEqual(chrome.commitButtonTitle, "覆盖写入此页")
        XCTAssertTrue(chrome.canSubmit)
    }

    private func installPending(
        on ledger: inout AhaKeyStudioPageOverwriteConfirmationLedger,
        identity: AhaKeyStudioPageOverwriteConfirmationIdentity
    ) {
        ledger.observeCurrentIdentity(identity)
        let attempt = ledger.beginAttempt(for: identity)
        ledger.applyCommitResult(
            .requiresOverwriteConfirmation,
            attempt: attempt,
            currentIdentity: identity
        )
        XCTAssertEqual(ledger.pending, identity)
    }

    private func makeIdentity(
        device: AhaKeyRuntimeDeviceID,
        session: UInt64 = 4,
        transport: UInt64 = 9,
        snapshot: AhaKeyStudioPageSnapshot
    ) -> AhaKeyStudioPageOverwriteConfirmationIdentity {
        AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(session),
            transportGeneration: .init(transport),
            snapshot: snapshot
        )
    }

    private func capturedActiveSetOnlySnapshot(overwriteConfirmed: Bool) -> AhaKeyStudioPageSnapshot {
        let aStates: [AhaKeyDesiredConfiguration.TaskDisplayState] = [.idle, .working, .waiting, .done]
        let aFields = aStates.map { state in
            AhaKeyStudioFrozenField(
                id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: state),
                value: .asset(
                    path: "/tmp/c5wr1-set0-\(state.rawValue).gif",
                    framesPerSecond: 12,
                    declaredFrameCount: 3,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
                isDirty: false,
                baseline: .init(
                    trust: .writeConfirmed,
                    value: .asset(
                        path: "/tmp/c5wr1-set0-\(state.rawValue).gif",
                        framesPerSecond: 12,
                        declaredFrameCount: 3,
                        pixelWidth: 160,
                        pixelHeight: 80
                    )
                )
            )
        }
        return AhaKeyStudioPageSnapshot(
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            selectedTaskSet: 0,
            overwriteConfirmed: overwriteConfirmed,
            fields: aFields + [
                AhaKeyStudioFrozenField(
                    id: .screenActiveSet(modeSlot: 0),
                    value: .integer(0),
                    isDirty: true,
                    baseline: .unknown
                ),
            ]
        )
    }

    private func capturedHistoricalOperations(
        device: AhaKeyRuntimeDeviceID
    ) throws -> [AhaKeyRuntimeOperationSummary] {
        try [
            summary(
                id: AhaKeyRuntimeOperationID(UUID(uuidString: "F2BAE385-1111-4000-8000-0000000000A0")!),
                device: device,
                state: .completed,
                pageID: .screen(modeSlot: 0)
            ),
            summary(
                id: AhaKeyRuntimeOperationID(UUID(uuidString: "844F52E4-D601-441F-942D-682A69DBF91F")!),
                device: device,
                state: .completed,
                pageID: .screen(modeSlot: 0),
                terminalOrder: 10
            ),
        ]
    }

    private func writeAndActivateChrome() -> AhaKeyStudioPageChrome {
        AhaKeyStudioPageChrome(
            status: .dirty,
            commitKind: .writeAndActivate,
            isLocked: false,
            canSubmit: true,
            canRemoveQueued: false,
            canCancelRunning: false,
            canAbandon: false,
            canRetryResidual: false,
            queuePosition: nil,
            queuedBehindCount: 0,
            operationID: nil
        )
    }

    private func summary(
        id: AhaKeyRuntimeOperationID,
        device: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        pageID: AhaKeyStudioPageID,
        terminalOrder: UInt64 = 1
    ) throws -> AhaKeyRuntimeOperationSummary {
        try AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: device,
            state: state,
            pageID: pageID,
            durableOrdering: state.isTerminal
                ? .terminal(terminalOrder: terminalOrder)
                : .live(queueOrder: 1)
        )
    }
}
