import XCTest
@testable import AhaKeyConfigShared

/// C5E：覆盖确认 ledger。捕获序列必须在「历史同页 completed 不得清 pending」上稳定。
final class AhaKeyStudioPageOverwriteConfirmationLedgerTests: XCTestCase {
    func testCapturedC5BWR2SequenceKeepsPendingAcrossHistoricalCompletedOperations() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let unconfirmed = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(unconfirmed),
            .requiresOverwriteConfirmation
        )

        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(4),
            transportGeneration: .init(9),
            snapshot: unconfirmed
        )
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity).commitKind,
            .writeAndActivate
        )

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        XCTAssertTrue(ledger.showsOverwritePrompt(for: identity))
        XCTAssertTrue(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity).commitKind,
            .overwritePage
        )

        ledger.noteOperationsChanged(try capturedHistoricalOperations(device: device))
        XCTAssertTrue(
            ledger.shouldSubmitConfirmed(for: identity),
            "同页 completed B/A 不得按 pageID 清掉新 pending"
        )

        let confirmed = capturedActiveSetOnlySnapshot(overwriteConfirmed: true)
        XCTAssertEqual(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: device,
                sessionGeneration: .init(4),
                transportGeneration: .init(9),
                snapshot: confirmed
            ),
            identity
        )
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
        ledger.applyCommitResult(.accepted(acceptedID), identity: identity)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertNil(ledger.pending)
    }

    func testHistoricalTerminalsOnOtherPagesOrDevicesDoNotConsumePending() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        let other = try AhaKeyRuntimeDeviceID("OTHER")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)

        let terminals = try [
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
        ledger.noteOperationsChanged(terminals)
        XCTAssertTrue(ledger.shouldSubmitConfirmed(for: identity))

        let otherIdentity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: other,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        ledger.applyCommitResult(.accepted(AhaKeyRuntimeOperationID()), identity: otherIdentity)
        XCTAssertTrue(
            ledger.shouldSubmitConfirmed(for: identity),
            "只有当前 exact confirmation identity 的结果可消费 pending"
        )

        ledger.applyCommitResult(.accepted(AhaKeyRuntimeOperationID()), identity: identity)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
    }

    func testStaleIdentityIsRejectedAndMustReconfirm() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
        let base = capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(4),
            transportGeneration: .init(9),
            snapshot: base
        )
        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)

        var dirtyField = base
        dirtyField.fields[0].value = .integer(1)
        let fieldIdentity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(4),
            transportGeneration: .init(9),
            snapshot: dirtyField
        )
        ledger.observeCurrentIdentity(fieldIdentity)
        XCTAssertNil(ledger.pending)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(dirtyField),
            .requiresOverwriteConfirmation
        )

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        var switchedSet = base
        switchedSet.selectedTaskSet = 1
        ledger.observeCurrentIdentity(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: device,
                sessionGeneration: .init(4),
                transportGeneration: .init(9),
                snapshot: switchedSet
            )
        )
        XCTAssertNil(ledger.pending)

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        ledger.observeCurrentIdentity(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: try AhaKeyRuntimeDeviceID("OTHER"),
                sessionGeneration: .init(4),
                transportGeneration: .init(9),
                snapshot: base
            )
        )
        XCTAssertNil(ledger.pending)

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        ledger.observeCurrentIdentity(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: device,
                sessionGeneration: .init(5),
                transportGeneration: .init(9),
                snapshot: base
            )
        )
        XCTAssertNil(ledger.pending)

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        ledger.observeCurrentIdentity(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: device,
                sessionGeneration: .init(4),
                transportGeneration: .init(10),
                snapshot: base
            )
        )
        XCTAssertNil(ledger.pending)

        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        var otherProfile = base
        otherProfile.profile = .legacyStandard
        ledger.observeCurrentIdentity(
            AhaKeyStudioPageOverwriteConfirmationLedger.identity(
                deviceID: device,
                sessionGeneration: .init(4),
                transportGeneration: .init(9),
                snapshot: otherProfile
            )
        )
        XCTAssertNil(ledger.pending)
        XCTAssertFalse(ledger.shouldSubmitConfirmed(for: identity))
    }

    func testFailClosedResultsDropPending() throws {
        let device = try AhaKeyRuntimeDeviceID("505C")
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: capturedActiveSetOnlySnapshot(overwriteConfirmed: false)
        )
        for result in [
            AhaKeyStudioPageCommitResult.noOp,
            .missingTrustedPageCache,
            .unsupportedProfile,
            .unsupportedPage,
        ] {
            var ledger = AhaKeyStudioPageOverwriteConfirmationLedger()
            ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
            ledger.applyCommitResult(result, identity: identity)
            XCTAssertNil(ledger.pending, "\(result) 必须 fail-closed 丢掉 pending")
        }

        var failed = AhaKeyStudioPageOverwriteConfirmationLedger()
        failed.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        failed.noteAttemptFailed()
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
        let identity = AhaKeyStudioPageOverwriteConfirmationLedger.identity(
            deviceID: device,
            sessionGeneration: .init(1),
            transportGeneration: .init(1),
            snapshot: snapshot
        )
        ledger.applyCommitResult(.requiresOverwriteConfirmation, identity: identity)
        let chrome = ledger.applyingPendingPrompt(to: writeAndActivateChrome(), for: identity)
        XCTAssertEqual(chrome.commitKind, .overwritePage)
        XCTAssertEqual(chrome.commitButtonTitle, "覆盖写入此页")
        XCTAssertTrue(chrome.canSubmit)
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
