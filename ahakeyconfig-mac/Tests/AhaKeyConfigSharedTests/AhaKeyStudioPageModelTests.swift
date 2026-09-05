import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyStudioPageModelTests: XCTestCase {
    func testEachFieldOwnsExactlyOnePage() {
        var seen = Set<AhaKeyStudioFieldID>()
        for field in AhaKeyStudioFieldOwnership.allOwnedFields() {
            XCTAssertTrue(seen.insert(field).inserted, "字段重复归属 \(field)")
            _ = AhaKeyStudioFieldOwnership.page(for: field)
        }
        let screen = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done)
        XCTAssertEqual(AhaKeyStudioFieldOwnership.page(for: screen), .screen(modeSlot: 0))
        let key = AhaKeyStudioFieldID.keyAction(modeSlot: 1, role: .voice)
        XCTAssertEqual(AhaKeyStudioFieldOwnership.page(for: key), .key(modeSlot: 1, role: .voice))
        XCTAssertNotEqual(
            AhaKeyStudioFieldOwnership.page(for: key),
            AhaKeyStudioFieldOwnership.page(for: screen)
        )
    }

    func testVerifiedEqualDirtyIsStrictNoOp() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("same"),
            isDirty: true,
            baseline: .init(trust: .verified, value: .text("same"))
        )
        XCTAssertTrue(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testWriteConfirmedExactMatchIsStrictNoOp() {
        let value = AhaKeyStudioFieldValue.asset(
            path: "/tmp/a.gif", framesPerSecond: 12, declaredFrameCount: 4,
            pixelWidth: 160, pixelHeight: 80
        )
        let field = AhaKeyStudioFrozenField(
            id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
            value: value,
            isDirty: true,
            baseline: .init(trust: .writeConfirmed, value: value)
        )
        XCTAssertTrue(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testUnknownNeverStrictNoOpWhenDirty() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("x"),
            isDirty: true,
            baseline: .unknown
        )
        XCTAssertFalse(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testUnknownNeverStrictNoOpEvenWhenMarkedClean() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("x"),
            isDirty: false,
            baseline: .unknown
        )
        XCTAssertFalse(AhaKeyStudioPageDiffer.isStrictNoOp(field))
    }

    func testLocalCacheProvenanceCannotBecomeVerified() {
        let authority = AhaKeyStudioFieldAuthority(
            value: .text("cached"),
            trust: .verified,
            provenance: .absent
        )
        XCTAssertEqual(authority.resolvedBaseline(), .unknown)
        let writeOnly = AhaKeyStudioFieldAuthority(
            value: .text("wrote"),
            trust: .verified,
            provenance: .writeConfirmation
        )
        XCTAssertEqual(writeOnly.resolvedBaseline().trust, .writeConfirmed)
        XCTAssertNotEqual(writeOnly.resolvedBaseline().trust, .verified)
    }

    func testLeverAndPowerAreNotWritable() {
        XCTAssertFalse(AhaKeyStudioFieldOwnership.isWritable(.lever))
        XCTAssertFalse(AhaKeyStudioFieldOwnership.isWritable(.power))
        XCTAssertTrue(AhaKeyStudioFieldOwnership.fieldIDs(on: .lever).isEmpty)
        XCTAssertTrue(AhaKeyStudioFieldOwnership.fieldIDs(on: .power).isEmpty)
    }

    func testStandardRequiredFieldsUseSelectedLogicalSet() {
        let required = AhaKeyStudioFieldOwnership.requiredFields(
            on: .screen(modeSlot: 0),
            profile: .legacyStandard,
            selectedTaskSet: 1
        )
        XCTAssertEqual(required.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertFalse(required.contains { id in
            if case .screenTaskAsset(_, _, .idle) = id { return true }
            return false
        })
        XCTAssertTrue(required.allSatisfy {
            if case .screenTaskAsset(_, 1, _) = $0 { return true }
            return false
        })
        XCTAssertTrue(
            AhaKeyStudioFieldOwnership.requiredFields(
                on: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                selectedTaskSet: 1
            ).isEmpty
        )
    }

    func testChromeMapsNoOpAndScreenWriteAndOverwrite() throws {
        let noOp = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(pageID: .lights(modeSlot: 0), assembly: .noOp)
        )
        XCTAssertEqual(noOp.status, .synced)
        XCTAssertEqual(noOp.commitKind, .noModification)
        XCTAssertFalse(noOp.canSubmit)
        XCTAssertFalse(noOp.canCancelRunning)

        let screen = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(pageID: .screen(modeSlot: 0), assembly: .write(Self.statusPlan()))
        )
        XCTAssertEqual(screen.status, .dirty)
        XCTAssertEqual(screen.commitKind, .writeAndActivate)
        XCTAssertTrue(screen.canSubmit)
        XCTAssertEqual(screen.statusLabel, "有修改")
        XCTAssertEqual(screen.commitButtonTitle, "写入并激活")

        let key = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .key(modeSlot: 0, role: .voice),
                assembly: .write(Self.statusPlan())
            )
        )
        XCTAssertEqual(key.commitKind, .writeCurrentPage)

        let overwrite = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .screen(modeSlot: 0),
                assembly: .requiresOverwriteConfirmation
            )
        )
        XCTAssertEqual(overwrite.commitKind, .overwritePage)
        XCTAssertTrue(overwrite.canSubmit)
    }

    func testChromeLocksQueuedPageAndAllowsParallelPages() throws {
        let device = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let queuedID = AhaKeyRuntimeOperationID()
        let runningID = AhaKeyRuntimeOperationID()
        let queued = Self.summary(id: queuedID, device: device, state: .accepted)
        let running = Self.summary(id: runningID, device: device, state: .running)
        let queue = [running, queued]

        let queuedChrome = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .key(modeSlot: 0, role: .voice),
                assembly: .write(Self.statusPlan()),
                operation: queued,
                deviceQueue: queue
            )
        )
        XCTAssertEqual(queuedChrome.status, .queued)
        XCTAssertTrue(queuedChrome.isLocked)
        XCTAssertTrue(queuedChrome.canRemoveQueued)
        XCTAssertFalse(queuedChrome.canSubmit)
        XCTAssertFalse(queuedChrome.canCancelRunning)
        XCTAssertEqual(queuedChrome.queuePosition, 2)
        XCTAssertEqual(queuedChrome.queuedBehindCount, 0)

        let otherPage = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .lights(modeSlot: 0),
                assembly: .write(Self.statusPlan()),
                deviceQueue: queue
            )
        )
        XCTAssertFalse(otherPage.isLocked)
        XCTAssertTrue(otherPage.canSubmit)
        XCTAssertEqual(otherPage.queuedBehindCount, 2)
    }

    func testChromeRefusesRunningCancelAndGatesAbandonAt60Seconds() throws {
        let device = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let running = Self.summary(id: .init(), device: device, state: .running)
        let runningChrome = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .screen(modeSlot: 0),
                assembly: .write(Self.statusPlan()),
                operation: running,
                deviceQueue: [running]
            )
        )
        XCTAssertEqual(runningChrome.status, .writing)
        XCTAssertTrue(runningChrome.isLocked)
        XCTAssertFalse(runningChrome.canRemoveQueued)
        XCTAssertFalse(runningChrome.canCancelRunning)
        XCTAssertFalse(runningChrome.canAbandon)

        let paused = Self.summary(id: .init(), device: device, state: .paused)
        let tooEarly = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .screen(modeSlot: 0),
                assembly: .noOp,
                operation: paused,
                deviceQueue: [paused],
                isDeviceConnected: false,
                disconnectedDuration: 59
            )
        )
        XCTAssertEqual(tooEarly.status, .waitingReconnect)
        XCTAssertFalse(tooEarly.canAbandon)

        let ready = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .screen(modeSlot: 0),
                assembly: .noOp,
                operation: paused,
                deviceQueue: [paused],
                isDeviceConnected: false,
                disconnectedDuration: AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration
            )
        )
        XCTAssertTrue(ready.canAbandon)
        XCTAssertEqual(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration, 60)
    }

    func testResidualOverlayRetriesOnlyRemainingFields() {
        let status = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let fps = AhaKeyStudioFieldID.screenFramesPerSecond(modeSlot: 0)
        let snapshot = AhaKeyStudioPageSnapshot(
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            selectedTaskSet: 1,
            fields: [
                AhaKeyStudioFrozenField(
                    id: status,
                    value: .text("new"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .text("old"))
                ),
                AhaKeyStudioFrozenField(
                    id: fps,
                    value: .integer(18),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(12))
                ),
                AhaKeyStudioFrozenField(
                    id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
                    value: .asset(
                        path: "/tmp/a.gif", framesPerSecond: 12, declaredFrameCount: 2,
                        pixelWidth: 160, pixelHeight: 80
                    ),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .asset(
                        path: "/tmp/old-a.gif", framesPerSecond: 12, declaredFrameCount: 2,
                        pixelWidth: 160, pixelHeight: 80
                    ))
                ),
                AhaKeyStudioFrozenField(
                    id: .screenTaskAsset(modeSlot: 0, setIndex: 1, state: .done),
                    value: .asset(
                        path: "/tmp/b.gif", framesPerSecond: 12, declaredFrameCount: 2,
                        pixelWidth: 160, pixelHeight: 80
                    ),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .asset(
                        path: "/tmp/old-b.gif", framesPerSecond: 12, declaredFrameCount: 2,
                        pixelWidth: 160, pixelHeight: 80
                    ))
                ),
            ]
        )
        let residual = AhaKeyStudioPageChromeProjector.overlayResidualOnly(
            snapshot,
            residualFieldIDs: [.screenTaskAsset(modeSlot: 0, setIndex: 1, state: .done)]
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(residual) else {
            return XCTFail("residual 只应写出未确认的套图 B")
        }
        XCTAssertFalse(plan.writeTaskSetA)
        XCTAssertTrue(plan.writeTaskSetB)
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertTrue(plan.emitsSetActiveSetOpcode)
        XCTAssertEqual(plan.fieldMask, [.screenTaskAsset(modeSlot: 0, setIndex: 1, state: .done)])
        XCTAssertFalse(plan.fieldMask.contains(status))
        XCTAssertFalse(plan.fieldMask.contains(fps))
    }

    func testStandardScreenWriteDoesNotEmitSetActiveSetOpcode() {
        let fields = AhaKeyDesiredConfiguration.TaskDisplayState.allCases
            .filter { $0 != .idle }
            .map { state in
                AhaKeyStudioFrozenField(
                    id: .screenTaskAsset(modeSlot: 0, setIndex: 1, state: state),
                    value: .asset(
                        path: "/tmp/std-\(state.rawValue).gif",
                        framesPerSecond: 12,
                        declaredFrameCount: 2,
                        pixelWidth: 160,
                        pixelHeight: 80
                    ),
                    isDirty: true,
                    baseline: .unknown
                )
            }
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                selectedTaskSet: 1,
                overwriteConfirmed: true,
                fields: fields
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("Standard 覆盖写入应得到 write plan")
        }
        XCTAssertFalse(plan.emitsSetActiveSetOpcode)
        let chrome = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(pageID: .screen(modeSlot: 0), assembly: assembly)
        )
        XCTAssertEqual(chrome.commitKind, .writeAndActivate)
    }

    func testConflictAndPartialStatuses() throws {
        let device = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let conflict = Self.summary(
            id: .init(),
            device: device,
            state: .failedWithoutWrites,
            messageCode: .configurationPreflightConflict
        )
        let conflictChrome = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .lights(modeSlot: 0),
                assembly: .write(Self.statusPlan()),
                operation: conflict
            )
        )
        XCTAssertEqual(conflictChrome.status, .conflict)
        XCTAssertFalse(conflictChrome.isLocked)

        let partial = Self.summary(
            id: .init(),
            device: device,
            state: .resumablePartial,
            residual: AhaKeyRuntimePageResidual(fieldIDs: [.screenStatusLine(modeSlot: 0)])
        )
        let partialChrome = AhaKeyStudioPageChromeProjector.project(
            AhaKeyStudioPageChromeInput(
                pageID: .screen(modeSlot: 0),
                assembly: .write(Self.statusPlan()),
                operation: partial
            )
        )
        XCTAssertEqual(partialChrome.status, .partial)
        XCTAssertTrue(partialChrome.canRetryResidual)
        XCTAssertFalse(partialChrome.isLocked)
    }

    private static func statusPlan() -> AhaKeyStudioScopedWritePlan {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        return AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text("new")],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: "new"
        )
    }

    private static func summary(
        id: AhaKeyRuntimeOperationID,
        device: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        messageCode: AhaKeyRuntimeEventCode? = nil,
        residual: AhaKeyRuntimePageResidual? = nil
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: device,
            state: state,
            messageCode: messageCode,
            residual: residual
        )
    }
}
