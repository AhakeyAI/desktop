import XCTest
@testable import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class AhaKeyStudioPageInteractionTests: XCTestCase {
    func testPartMapsOntoC2PageIDs() {
        XCTAssertEqual(AhaKeyStudioPart.key1.pageID(modeSlot: .mode0), .key(modeSlot: 0, role: .voice))
        XCTAssertEqual(AhaKeyStudioPart.key2.pageID(modeSlot: .mode1), .key(modeSlot: 1, role: .approve))
        XCTAssertEqual(AhaKeyStudioPart.key3.pageID(modeSlot: .mode2), .key(modeSlot: 2, role: .reject))
        XCTAssertEqual(AhaKeyStudioPart.key4.pageID(modeSlot: .mode3), .key(modeSlot: 3, role: .submit))
        XCTAssertEqual(AhaKeyStudioPart.lightBar.pageID(modeSlot: .mode0), .lights(modeSlot: 0))
        XCTAssertEqual(AhaKeyStudioPart.oledDisplay.pageID(modeSlot: .mode1), .screen(modeSlot: 1))
        XCTAssertEqual(AhaKeyStudioPart.toggleSwitch.pageID(modeSlot: .mode0), .lever)
        XCTAssertFalse(AhaKeyStudioFieldOwnership.isWritable(.lever))
    }

    func testFreshStoreRebuildsQueuedRunningPausedAndResumableFromSnapshot() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let queued = summary(
            id: AhaKeyRuntimeOperationID(),
            device: deviceID,
            state: .accepted,
            pageID: .key(modeSlot: 0, role: .voice),
            queueOrder: 1
        )
        let running = summary(
            id: AhaKeyRuntimeOperationID(),
            device: deviceID,
            state: .running,
            pageID: .lights(modeSlot: 0),
            queueOrder: 2
        )
        let paused = summary(
            id: AhaKeyRuntimeOperationID(),
            device: deviceID,
            state: .paused,
            pageID: .screen(modeSlot: 0),
            queueOrder: 3
        )
        let resumable = summary(
            id: AhaKeyRuntimeOperationID(),
            device: deviceID,
            state: .resumablePartial,
            pageID: .key(modeSlot: 0, role: .approve),
            residual: AhaKeyRuntimePageResidual(fieldIDs: [.keyDescription(modeSlot: 0, role: .approve)]),
            queueOrder: 4
        )
        let store = makeStore()
        store.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: deviceID,
                    operations: [queued, running, paused, resumable]
                )
            )
        )
        XCTAssertEqual(store.operation(for: .key(modeSlot: 0, role: .voice))?.id, queued.id)
        XCTAssertEqual(store.operation(for: .lights(modeSlot: 0))?.id, running.id)
        XCTAssertEqual(store.operation(for: .screen(modeSlot: 0))?.id, paused.id)
        XCTAssertEqual(store.operation(for: .key(modeSlot: 0, role: .approve))?.id, resumable.id)
        XCTAssertTrue(store.isPageLocked(.key(modeSlot: 0, role: .voice)))
        XCTAssertTrue(store.isPageLocked(.lights(modeSlot: 0)))
        XCTAssertTrue(store.isPageLocked(.screen(modeSlot: 0)))
        XCTAssertTrue(store.isPageLocked(.key(modeSlot: 0, role: .approve)))
        XCTAssertEqual(store.deviceFIFO.count, 4)
        XCTAssertEqual(store.deviceFIFO.first?.pageID, queued.pageID)
    }

    func testDuplicateSubmitAndQueuedRemoveKeepOwnershipUntilTerminal() async throws {
        let harness = try makeHarness()
        let keyPage = AhaKeyStudioPageID.key(modeSlot: 0, role: .voice)
        let lightsPage = AhaKeyStudioPageID.lights(modeSlot: 0)
        let queuedID = AhaKeyRuntimeOperationID()
        let runningID = AhaKeyRuntimeOperationID()
        let queued = summary(id: queuedID, device: harness.deviceID, state: .accepted, pageID: keyPage, queueOrder: 2)
        let running = summary(id: runningID, device: harness.deviceID, state: .running, pageID: lightsPage, queueOrder: 1)
        harness.store.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [running, queued]))
        )

        do {
            _ = try await harness.store.commitFrozenPage(keySnapshot(text: "again"))
            XCTFail("同页排队中必须拒绝重复提交")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .pageAlreadyInFlight)
        }

        let removed = try await harness.store.removeQueuedPage(keyPage)
        XCTAssertEqual(removed, .requested)
        harness.store.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [
                running,
                try queued.withState(.cancellationRequested),
            ]))
        )
        XCTAssertEqual(harness.store.operation(for: keyPage)?.state, .cancellationRequested)
        XCTAssertTrue(harness.store.isPageLocked(keyPage))
        do {
            _ = try await harness.store.commitFrozenPage(keySnapshot(text: "third"))
            XCTFail("cancellationRequested 仍占用页")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .pageAlreadyInFlight)
        }

        do {
            _ = try await harness.store.removeQueuedPage(lightsPage)
            XCTFail("running 必须拒绝普通取消")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .runningCannotBeCancelled)
        }
        XCTAssertEqual(harness.store.operation(for: lightsPage)?.id, runningID)
        await harness.facade.stop()
    }

    func testAbandonUsesSnapshotEligibilityNotLocalClock() async throws {
        let harness = try makeHarness()
        let page = AhaKeyStudioPageID.screen(modeSlot: 0)
        let operationID = AhaKeyRuntimeOperationID()
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let tooEarly = summary(
            id: operationID,
            device: harness.deviceID,
            state: .paused,
            pageID: page,
            abandonEligibility: .init(epochStartedAt: epoch, eligible: false)
        )
        harness.store.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [tooEarly], connected: false))
        )
        do {
            _ = try await harness.store.requestAbandon(of: page)
            XCTFail("未投影 eligible 不得放弃")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .abandonNotEligible)
        }

        let ready = tooEarly.withOwnership(
            pageID: page,
            abandonEligibility: .init(epochStartedAt: epoch, eligible: true)
        )
        let reopened = makeStore()
        reopened.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [ready], connected: false))
        )
        let abandoned = try await reopened.requestAbandon(of: page)
        XCTAssertEqual(abandoned, .abandoned)
        await harness.facade.stop()
    }

    func testResumablePartialCannotStartNewResidualOperation() async throws {
        let harness = try makeHarness()
        let page = AhaKeyStudioPageID.screen(modeSlot: 0)
        let operationID = AhaKeyRuntimeOperationID()
        let partial = summary(
            id: operationID,
            device: harness.deviceID,
            state: .resumablePartial,
            pageID: page,
            residual: AhaKeyRuntimePageResidual(fieldIDs: [.screenStatusLine(modeSlot: 0)])
        )
        harness.store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [partial])))
        do {
            _ = try await harness.store.commitFrozenPage(screenSnapshot(), retryResidual: true)
            XCTFail("resumablePartial 不得另起 residual operation")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .pageAlreadyInFlight)
        }
        XCTAssertTrue(harness.store.isPageLocked(page))
        await harness.facade.stop()
    }

    func testFailedWithoutWritesResidualRetryStartsNewOperation() async throws {
        let harness = try makeHarness()
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: []))
        let page = AhaKeyStudioPageID.screen(modeSlot: 0)
        let failed = summary(
            id: AhaKeyRuntimeOperationID(),
            device: harness.deviceID,
            state: .failedWithoutWrites,
            pageID: page,
            residual: AhaKeyRuntimePageResidual(fieldIDs: [.screenStatusLine(modeSlot: 0)])
        )
        harness.store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [failed])))
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: [failed]))

        let bothDirty = screenSnapshot(extraFPS: true)
        let result = try await harness.store.commitFrozenPage(bothDirty, retryResidual: true)
        guard case .accepted = result else {
            return XCTFail("failedWithoutWrites residual 应允许新 operation")
        }
        XCTAssertEqual(harness.transport.appliedPackage?.pageOperation?.fieldMask, [.screenStatusLine(modeSlot: 0)])
        XCTAssertFalse(
            harness.transport.appliedPackage?.pageOperation?.fieldMask.contains(.screenFramesPerSecond(modeSlot: 0)) ?? true
        )
        await harness.facade.stop()
    }

    func testDeviceSwitchIgnoresOtherDeviceOperationsAndBaselines() throws {
        let active = try AhaKeyRuntimeDeviceID("DEVICE-A")
        let other = try AhaKeyRuntimeDeviceID("DEVICE-B")
        let foreignOp = summary(
            id: AhaKeyRuntimeOperationID(),
            device: other,
            state: .running,
            pageID: .screen(modeSlot: 0)
        )
        let foreignBaseline = AhaKeyRuntimeFieldBaseline(
            deviceID: other,
            pageID: .screen(modeSlot: 0),
            fieldID: .screenStatusLine(modeSlot: 0),
            value: .text("other"),
            trust: .verified,
            provenance: .deviceReadback
        )
        let store = makeStore()
        store.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: active,
                    extraDevices: [other],
                    operations: [foreignOp],
                    pageBaselines: [foreignBaseline]
                )
            )
        )
        XCTAssertNil(store.operation(for: .screen(modeSlot: 0)))
        XCTAssertFalse(store.isPageLocked(.screen(modeSlot: 0)))
        XCTAssertTrue(store.fieldAuthorities().isEmpty)
        XCTAssertTrue(store.deviceFIFO.isEmpty)
    }

    func testActiveDevicePageBaselinesPreserveTaskIdentity() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let digest = try AhaKeySHA256Digest(String(repeating: "cd", count: 32))
        let media = try AhaKeyMediaType("gif")
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done)
        let baseline = AhaKeyRuntimeFieldBaseline(
            deviceID: deviceID,
            pageID: .screen(modeSlot: 0),
            fieldID: field,
            value: .taskAsset(
                sha256: digest,
                byteCount: 48,
                mediaType: media,
                framesPerSecond: 12,
                declaredFrameCount: 2
            ),
            trust: .writeConfirmed,
            provenance: .writeConfirmation
        )
        let store = makeStore()
        store.applyViewStateForTesting(
            onlineState(snapshot: makeSnapshot(deviceID: deviceID, pageBaselines: [baseline]))
        )
        let authority = try XCTUnwrap(store.fieldAuthorities()[field])
        XCTAssertEqual(authority.trust, .writeConfirmed)
        XCTAssertEqual(authority.value?.taskAssetValue?.sha256, digest)
        XCTAssertEqual(authority.value?.taskAssetValue?.byteCount, 48)
        XCTAssertEqual(authority.value?.taskAssetValue?.mediaType, media)
    }

    func testOLEDProfileUsesSealedFactNotProtocolState() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let cases: [(AhaKeyRuntimeOLEDCompatibilityFact?, AhaKeyOLEDCompatibilityProfile)] = [
            (nil, .unsupported),
            (.init(family: .legacyStandard), .legacyStandard),
            (.init(family: .rhinoDualSet, sessionUploadAdvertised: false), .rhinoDualSet(sessionUploadAdvertised: false)),
            (.init(family: .rhinoDualSet, sessionUploadAdvertised: true), .rhinoDualSet(sessionUploadAdvertised: true)),
            (.init(family: .currentSessionCapable, sessionUploadAdvertised: true), .currentSessionCapable),
        ]
        for (fact, expected) in cases {
            let store = makeStore()
            store.applyViewStateForTesting(
                onlineState(
                    snapshot: makeSnapshot(
                        deviceID: deviceID,
                        protocolState: .currentReady,
                        oledCompatibility: fact
                    )
                )
            )
            XCTAssertEqual(store.oledProfile, expected)
        }
        let denied = makeStore()
        denied.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: deviceID,
                    protocolState: .legacyDenied,
                    oledCompatibility: nil
                )
            )
        )
        XCTAssertEqual(denied.oledProfile, .unsupported)
    }

    func testSealedRhinoFactOpensDualSetPlanWithoutCreatingAnOperation() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let store = makeStore()
        store.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: deviceID,
                    oledCompatibility: .init(family: .rhinoDualSet, sessionUploadAdvertised: false)
                )
            )
        )
        XCTAssertEqual(store.taskPictureProtocolPlan?.setIndices, [0, 1])
        XCTAssertEqual(store.taskPictureProtocolPlan?.supportsActiveSet, true)
        XCTAssertTrue(store.allowsTaskPictureConfiguration)
        XCTAssertTrue(store.deviceFIFO.isEmpty)
        XCTAssertNil(store.operation(for: .screen(modeSlot: 0)))
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 0,
                draftSet: 1,
                previousPlan: nil,
                nextPlan: store.taskPictureProtocolPlan
            ),
            1
        )
    }

    func testNilThenRhinoRestoresDraftBWithoutCreatingAnOperation() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let store = makeStore()
        store.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(deviceID: deviceID, oledCompatibility: nil)
            )
        )
        XCTAssertNil(store.taskPictureProtocolPlan)
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterDraftRefresh(draftSet: 1, plan: store.taskPictureProtocolPlan),
            1
        )
        XCTAssertTrue(store.deviceFIFO.isEmpty)
        XCTAssertNil(store.operation(for: .screen(modeSlot: 0)))

        store.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: deviceID,
                    oledCompatibility: .init(family: .rhinoDualSet, sessionUploadAdvertised: false)
                )
            )
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 0,
                draftSet: 1,
                previousPlan: nil,
                nextPlan: store.taskPictureProtocolPlan
            ),
            1
        )
        XCTAssertTrue(store.deviceFIFO.isEmpty)
        XCTAssertNil(store.operation(for: .screen(modeSlot: 0)))
    }

    func testOnlineStoreDoesNotOpenDualSetFromProtocolModeOrForeignFact() throws {
        let active = try AhaKeyRuntimeDeviceID("ACTIVE")
        let other = try AhaKeyRuntimeDeviceID("OTHER")
        let missingFact = makeStore()
        missingFact.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: active,
                    protocolState: .currentReady,
                    oledCompatibility: nil
                )
            )
        )
        XCTAssertEqual(missingFact.protocolMode, .current)
        XCTAssertNil(missingFact.taskPictureProtocolPlan)
        XCTAssertFalse(missingFact.allowsTaskPictureConfiguration)

        let standard = makeStore()
        standard.applyViewStateForTesting(
            onlineState(
                snapshot: makeSnapshot(
                    deviceID: active,
                    oledCompatibility: .init(family: .legacyStandard)
                )
            )
        )
        XCTAssertEqual(standard.taskPictureProtocolPlan?.supportsActiveSet, false)
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterDraftRefresh(
                draftSet: 1,
                plan: standard.taskPictureProtocolPlan
            ),
            0
        )

        let foreignSnapshot = AhaKeyRuntimeSnapshot(
            supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
            lifecycleState: .running,
            devices: [
                AhaKeyRuntimeDeviceSnapshot(
                    id: active,
                    displayName: "Active",
                    protocolState: .currentReady,
                    preferredTransport: .bluetooth,
                    usbAttached: false,
                    bluetoothConnected: true
                ),
                AhaKeyRuntimeDeviceSnapshot(
                    id: other,
                    displayName: "Other",
                    protocolState: .currentReady,
                    preferredTransport: .bluetooth,
                    usbAttached: false,
                    bluetoothConnected: true,
                    oledCompatibility: .init(family: .rhinoDualSet, sessionUploadAdvertised: false)
                ),
            ],
            activeDeviceID: active,
            configurationRevision: .init(0),
            operations: [],
            policy: .init(),
            permissions: .init(states: [:]),
            keepAliveReasons: [],
            latestEventSequence: .init(0),
            pageBaselines: []
        )
        let foreign = makeStore()
        foreign.applyViewStateForTesting(onlineState(snapshot: foreignSnapshot))
        XCTAssertEqual(foreign.deviceKey, "ACTIVE")
        XCTAssertNil(foreign.taskPictureProtocolPlan)
        XCTAssertTrue(foreign.deviceFIFO.isEmpty)
    }

    func testExplicitActiveSetUnknownBaselineTwoClickCommitGoesThroughFacade() async throws {
        let harness = try makeHarness()
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: []))
        harness.store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [])))

        let coordinator = AhaKeyStudioPageCommitCoordinator(
            registry: AhaKeyStudioPageCommitExecutionRegistry()
        )
        coordinator.attach()
        let port = RecordingStoreCommitPort(store: harness.store)
        let current = AhaKeyStudioDraft.default
        let synced = current
        let context = AhaKeyStudioPageEditIntentContext(
            deviceID: harness.deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
        )

        coordinator.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: harness.deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )

        // 与 View 一致：每次点击都从当前状态重建一次冻结输入。
        func makeInput() -> AhaKeyStudioPageSubmissionInput {
            let intentFieldIDs = coordinator.matchingExplicitIntentFieldIDs(context)
            let snapshot = current.frozenPageSnapshot(
                pageID: .screen(modeSlot: 0),
                lastSyncedDraft: synced,
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                selectedTaskSet: 0,
                overwriteConfirmed: false,
                explicitIntentFieldIDs: intentFieldIDs
            )
            return AhaKeyStudioPageSubmissionInput(
                deviceID: harness.deviceID,
                sessionGeneration: .init(0),
                transportGeneration: .init(0),
                snapshot: snapshot,
                explicitIntentFieldIDs: intentFieldIDs,
                retryResidual: false
            )
        }

        let firstInput = makeInput()
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(firstInput.snapshot),
            .requiresOverwriteConfirmation
        )
        coordinator.observeIdentity(firstInput.confirmationIdentity)

        let first = await runCoordinatorSubmit(coordinator, firstInput, port: port)
        XCTAssertEqual(first.outcome, .requiresOverwriteConfirmation)
        XCTAssertEqual(port.snapshots.count, 1)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        XCTAssertEqual(coordinator.pendingPrompt, firstInput.confirmationIdentity)
        var counts = await harness.facade.pageSubmitRecordingCountsForTesting()
        XCTAssertEqual(counts.ingest, 0)
        XCTAssertEqual(counts.apply, 0)
        XCTAssertNil(harness.transport.appliedPackage)

        // 历史同页 completed operation 不得消费 pending。
        let completed = summary(
            id: AhaKeyRuntimeOperationID(UUID(uuidString: "844F52E4-D601-441F-942D-682A69DBF91F")!),
            device: harness.deviceID,
            state: .completed,
            pageID: .screen(modeSlot: 0),
            terminalOrder: 10
        )
        harness.store.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [completed]))
        )
        XCTAssertEqual(coordinator.pendingPrompt, firstInput.confirmationIdentity)

        // 第二次 exact 点击：重建的冻结输入必须与第一次等价。
        let secondInput = makeInput()
        XCTAssertEqual(secondInput, firstInput, "第二击必须是同一份 exact 冻结输入")

        let second = await runCoordinatorSubmit(coordinator, secondInput, port: port)
        guard case .accepted = second.outcome else {
            return XCTFail("第二次相同 identity 必须进入 Facade apply：\(second)")
        }
        XCTAssertEqual(port.snapshots.count, 2)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true, "第二 snapshot 必须是 confirmed")
        XCTAssertNil(coordinator.pendingPrompt)
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.clickCount, 2)
        XCTAssertEqual(coordinator.portCallCount, 2)

        counts = await harness.facade.pageSubmitRecordingCountsForTesting()
        XCTAssertEqual(counts.ingest, 0)
        XCTAssertEqual(counts.apply, 1)
        XCTAssertNotNil(harness.transport.appliedPackage)
        XCTAssertEqual(
            harness.transport.appliedPackage?.pageOperation?.fieldMask,
            [.screenActiveSet(modeSlot: 0)]
        )
        XCTAssertEqual(
            coordinator.matchingExplicitIntentFieldIDs(context),
            []
        )
        await harness.facade.stop()
    }

    /// C5GR5：生产 port 必须弱持有 RuntimeClient，否则
    /// `client → registry → execution → port → client` 会形成闭环，hung port 永远钉住整条图。
    func testProductionCommitPortDoesNotRetainRuntimeStore() {
        weak var weakStore: AhaKeyStudioRuntimeClient?
        var port: AhaKeyStudioRuntimeStoreCommitPort?
        do {
            let store = makeStore()
            weakStore = store
            port = AhaKeyStudioRuntimeStoreCommitPort(store: store)
            XCTAssertNotNil(port?.store)
        }
        XCTAssertNil(weakStore, "生产 port 不得强持有 RuntimeClient")
        XCTAssertNil(port?.store, "持有的 client 释放后 port 必须 fail-closed，而不是继续钉住它")
    }

    /// C5GR6：真实关闭生命周期（applicationWillTerminate → disconnect）必须 one-way 关闭注册表。
    func testDisconnectShutsDownCommitRegistry() {
        let store = makeStore()
        XCTAssertFalse(store.pageCommitExecutions.isClosed)

        store.disconnect()

        XCTAssertTrue(store.pageCommitExecutions.isClosed, "disconnect 必须关闭 page-commit 注册表")
        let coordinator = AhaKeyStudioPageCommitCoordinator(registry: store.pageCommitExecutions)
        XCTAssertFalse(coordinator.isAttached, "关闭后不得再 attach")
    }

    /// C5GR6：已进入 production invocation 时，store 会被 async 调用强持有跨 await；
    /// 这段生命周期也必须按契约收口——disconnect 是 one-way fence，迟到结果不再写 trace。
    func testProductionInvocationInFlightSurvivesDisconnectAndSettlesItOut() async throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let transport = SuspendingApplyTransport(snapshot: makeSnapshot(deviceID: deviceID, operations: []))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        let store = AhaKeyStudioRuntimeClient(facade: facade)
        await facade.installSnapshotForTesting(makeSnapshot(deviceID: deviceID, operations: []))
        store.applyViewStateForTesting(onlineState(snapshot: makeSnapshot(deviceID: deviceID, operations: [])))

        let coordinator = AhaKeyStudioPageCommitCoordinator(registry: store.pageCommitExecutions)
        coordinator.attach()
        let port = AhaKeyStudioRuntimeStoreCommitPort(store: store)
        let profile = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false)
        let current = AhaKeyStudioDraft.default
        let context = AhaKeyStudioPageEditIntentContext(
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            pageID: .screen(modeSlot: 0),
            profile: profile,
            currentValues: [.screenActiveSet(modeSlot: 0): .integer(0)]
        )
        coordinator.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            profile: profile
        )

        func makeInput() -> AhaKeyStudioPageSubmissionInput {
            let intentFieldIDs = coordinator.matchingExplicitIntentFieldIDs(context)
            let snapshot = current.frozenPageSnapshot(
                pageID: .screen(modeSlot: 0),
                lastSyncedDraft: current,
                profile: profile,
                selectedTaskSet: 0,
                overwriteConfirmed: false,
                explicitIntentFieldIDs: intentFieldIDs
            )
            return AhaKeyStudioPageSubmissionInput(
                deviceID: deviceID,
                sessionGeneration: .init(0),
                transportGeneration: .init(0),
                snapshot: snapshot,
                explicitIntentFieldIDs: intentFieldIDs,
                retryResidual: false
            )
        }

        // 第一次点击：unknown baseline → requires（不进入 port）。
        let first = makeInput()
        coordinator.observeIdentity(first.confirmationIdentity)
        _ = coordinator.start(first, port: port)
        while coordinator.inFlight != nil { await Task.yield() }
        XCTAssertFalse(transport.reachedApply)

        // 第二次点击：进入 production invocation 并挂起在 apply。
        let second = makeInput()
        _ = coordinator.start(second, port: port)
        while !transport.reachedApply { await Task.yield() }
        XCTAssertNotNil(store.pageCommitExecutions.lease, "invocation 已进入，租约必须在场")

        // 真实关闭生命周期：one-way fence，放弃租约。
        store.disconnect()
        XCTAssertTrue(store.pageCommitExecutions.isClosed)
        XCTAssertNil(store.pageCommitExecutions.lease, "shutdown 必须 fence 并放弃在途租约")
        let traceAfterShutdown = coordinator.trace.count

        // 迟到的 production 返回不得改动任何状态。
        transport.releaseApply()
        for _ in 0..<16 { await Task.yield() }
        XCTAssertEqual(coordinator.trace.count, traceAfterShutdown, "关闭后迟到返回不得再写 trace")
        XCTAssertNil(store.pageCommitExecutions.lease)
        XCTAssertFalse(coordinator.isSubmitting)
    }

    /// C5GR7：退出路径的 terminal fence 必须在回调返回前**同步**完成，
    /// 不能只排一个未等待的 Task（进程可能在它获得调度前结束）。
    func testTerminationFenceRunsSynchronouslyBeforeReturn() {
        let store = makeStore()
        XCTAssertFalse(store.pageCommitExecutions.isClosed)

        AhaKeyAppTerminationFence.fence(store: store)

        // 这里没有任何 await / yield：返回时就必须已经 closed。
        XCTAssertTrue(store.pageCommitExecutions.isClosed, "fence 必须同步完成")
        XCTAssertNil(store.pageCommitExecutions.lease)

        // fence 之后不得再 attach 或提交。
        let coordinator = AhaKeyStudioPageCommitCoordinator(registry: store.pageCommitExecutions)
        XCTAssertFalse(coordinator.isAttached)
    }

    /// C5H：R5 场景永久集成红测。无 whole-object、activeSet live baseline=`writeConfirmed(1)`、
    /// 显式 Picker A=0 —— 第一击必须只要求确认（apply=0），第二击确认后必须 accepted（apply=1），
    /// 不得再次返回 `.requiresOverwriteConfirmation`（R5 的无限确认循环）。
    func testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation() async throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let profile = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false)
        let pageID = AhaKeyStudioPageID.screen(modeSlot: 0)
        let activeSetField = AhaKeyStudioFieldID.screenActiveSet(modeSlot: 0)

        // live baseline：activeSet=1 且 trust=writeConfirmed（R5 的真实设备事实）。
        let baselines = [
            AhaKeyRuntimeFieldBaseline(
                deviceID: deviceID,
                pageID: pageID,
                fieldID: activeSetField,
                value: .integer(1),
                trust: .writeConfirmed,
                provenance: .writeConfirmation
            ),
        ]
        let snapshotWithBaseline = makeSnapshot(
            deviceID: deviceID,
            pageBaselines: baselines,
            authoritativeObject: nil
        )
        let transport = FakeTransport(snapshot: snapshotWithBaseline)
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        let store = AhaKeyStudioRuntimeClient(facade: facade)
        await facade.installSnapshotForTesting(snapshotWithBaseline)
        store.applyViewStateForTesting(onlineState(snapshot: snapshotWithBaseline))

        let coordinator = AhaKeyStudioPageCommitCoordinator(registry: store.pageCommitExecutions)
        coordinator.attach()
        let port = RecordingStoreCommitPort(store: store)

        let current = AhaKeyStudioDraft.default
        let context = AhaKeyStudioPageEditIntentContext(
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            pageID: pageID,
            profile: profile,
            currentValues: [activeSetField: .integer(0)]
        )
        // 显式 Picker A=0（默认选中不会触发 setter）。
        coordinator.notePickerSelection(
            activeSet: 0,
            modeSlot: 0,
            deviceID: deviceID,
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            profile: profile
        )

        func makeInput() -> AhaKeyStudioPageSubmissionInput {
            let intentFieldIDs = coordinator.matchingExplicitIntentFieldIDs(context)
            let snapshot = current.frozenPageSnapshot(
                pageID: pageID,
                lastSyncedDraft: current,
                fieldAuthorities: [
                    activeSetField: AhaKeyStudioFieldAuthority(
                        value: .integer(1),
                        trust: .writeConfirmed,
                        // 注意：resolvedBaseline() 只在 provenance == .writeConfirmation 时
                        // 才给出 writeConfirmed；配 .deviceReadback 会被降级成 .unknown，
                        // 于是 acceptedUnknown=true，反而绕过 C5H 的判别。
                        provenance: .writeConfirmation
                    ),
                ],
                profile: profile,
                selectedTaskSet: 0,
                overwriteConfirmed: false,
                explicitIntentFieldIDs: intentFieldIDs
            )
            return AhaKeyStudioPageSubmissionInput(
                deviceID: deviceID,
                sessionGeneration: .init(0),
                transportGeneration: .init(0),
                snapshot: snapshot,
                explicitIntentFieldIDs: intentFieldIDs,
                retryResidual: false
            )
        }

        // ---- 第一击：未确认 → requires，零 apply/ingest ----
        let firstInput = makeInput()
        coordinator.observeIdentity(firstInput.confirmationIdentity)
        let first = await runCoordinatorSubmit(coordinator, firstInput, port: port)
        XCTAssertEqual(first.outcome, .requiresOverwriteConfirmation, "第一击必须只要求确认")
        XCTAssertEqual(port.snapshots.count, 1)
        XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false)
        var counts = await facade.pageSubmitRecordingCountsForTesting()
        XCTAssertEqual(counts.apply, 0, "未确认不得 apply")
        XCTAssertEqual(counts.ingest, 0, "未确认不得 ingest")

        // ---- 第二击：exact 同输入 → confirmed=true → accepted ----
        let secondInput = makeInput()
        XCTAssertEqual(secondInput, firstInput, "两击必须是同一份 exact 冻结输入")
        let second = await runCoordinatorSubmit(coordinator, secondInput, port: port)
        guard case .accepted = second.outcome else {
            return XCTFail("C5H：确认后必须越过 authority，实得 \(second.outcome)")
        }
        XCTAssertEqual(port.snapshots.count, 2)
        XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true, "第二击必须携带 confirmed=true")

        counts = await facade.pageSubmitRecordingCountsForTesting()
        XCTAssertEqual(counts.apply, 1)
        XCTAssertEqual(counts.ingest, 0)

        // ---- package 形状：schema=3、仅 activeSet、零 resource ----
        let package = try XCTUnwrap(transport.appliedPackage)
        XCTAssertEqual(package.schemaVersion, AhaKeyConfigurationPackage.fieldBaselineSchemaVersion)
        let pageOperation = try XCTUnwrap(package.pageOperation)
        XCTAssertEqual(pageOperation.fieldMask, [activeSetField], "fieldMask 必须只有 activeSet")
        XCTAssertNil(pageOperation.baseObjectFingerprint, "该场景必须无 whole-object")
        XCTAssertNotNil(pageOperation.fieldBaselines, "schema=3 必须走 field-baseline proof")
        XCTAssertTrue(pageOperation.resourceBindings.isEmpty, "activeSet-only 必须零 resource binding")
        XCTAssertTrue(package.resources.isEmpty, "activeSet-only 必须零 resource")

        // ---- C5HR1：canonical wire —— actions 恰好一项 `.setActiveSet`/0x97/set0 ----
        // 任务卡「action 仅 0x97 set0」必须被永久锁住，而不是只断言 schema/fieldMask。
        let fingerprint = pageOperation.compatibilityFingerprint
        XCTAssertEqual(fingerprint.actions.count, 1, "activeSet-only 必须恰好一个 emitted action")
        let action = try XCTUnwrap(fingerprint.actions.first)
        XCTAssertEqual(action.fieldID, activeSetField)
        XCTAssertEqual(action.command, .setActiveSet)
        XCTAssertEqual(action.opcode, 0x97)
        XCTAssertEqual(action.opcode, AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet)
        XCTAssertNil(action.subtype)
        XCTAssertEqual(action.logicalSet, 0)
        XCTAssertEqual(action.physicalSlot, 0)
        XCTAssertNil(action.displayState)
        XCTAssertEqual(action.activation, .setActiveSetOpcode)
        XCTAssertEqual(action.binding, .none)
        XCTAssertEqual(action.session, .none)
        XCTAssertEqual(action.geometry, .none)
        XCTAssertNil(action.resourceIdentity)
        XCTAssertNil(action.encodedFrameCount)
        // 显式排除 status/FPS/task-asset（picture）action。
        XCTAssertFalse(fingerprint.actions.contains { action in
            switch action.command {
            case .screenStatus, .screenFramesPerSecond, .picture:
                return true
            default:
                return false
            }
        })
        XCTAssertTrue(fingerprint.lightMappingRows.isEmpty, "不得混入 0x84 light 行")
        XCTAssertNil(fingerprint.prepareStrategy)
        XCTAssertNil(fingerprint.defaultBindOpcode)
        XCTAssertEqual(fingerprint.family, .rhinoDualSet(sessionUpload: false))
        await facade.stop()
    }

    /// C5HR1：非 whole-group 的 key/light schema=3 写路径必须走真实 Store→Facade，
    /// 未确认时 authority requires 且零 apply；exact 确认后 accepted，wire 精确。
    func testNonWholeGroupKeyAndLightSchema3RequiresThenAccepts() async throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let profile = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false)

        struct Row {
            let name: String
            let pageID: AhaKeyStudioPageID
            let mutate: (inout AhaKeyStudioDraft) -> Void
            let expectedFieldID: AhaKeyStudioFieldID
            let expectedCommand: AhaKeyRuntimeEmittedAction.Command
            let expectedOpcode: UInt8
            let expectedSubtype: UInt8?
        }

        let rows: [Row] = [
            Row(
                name: "key-description",
                pageID: .key(modeSlot: 0, role: .voice),
                mutate: { draft in
                    var mode = draft.draft(for: .mode0)
                    mode.updateKey(AhaKeyKeyDraft(
                        role: .voice,
                        shortcut: mode.key(for: .voice).shortcut,
                        description: "new-desc",
                        voicePreset: mode.key(for: .voice).voicePreset
                    ))
                    draft.updateMode(mode)
                },
                expectedFieldID: .keyDescription(modeSlot: 0, role: .voice),
                expectedCommand: .keyDescription,
                expectedOpcode: 0x73,
                expectedSubtype: 0x75
            ),
            Row(
                name: "light-brightness",
                pageID: .lights(modeSlot: 0),
                mutate: { draft in
                    var mode = draft.draft(for: .mode0)
                    mode.lightBar.brightness = 80
                    draft.updateMode(mode)
                },
                expectedFieldID: .lightBrightness(modeSlot: 0),
                expectedCommand: .lightBrightness,
                expectedOpcode: 0x85,
                expectedSubtype: nil
            ),
            Row(
                name: "light-mapping",
                pageID: .lights(modeSlot: 0),
                mutate: { draft in
                    var mode = draft.draft(for: .mode0)
                    if let index = mode.lightBar.stateMappings.firstIndex(where: { $0.state.rawValue == 1 }) {
                        mode.lightBar.stateMappings[index].effect =
                            mode.lightBar.stateMappings[index].effect == .off ? .singleMove : .off
                    }
                    draft.updateMode(mode)
                },
                expectedFieldID: .lightMapping(modeSlot: 0, state: 1),
                expectedCommand: .lightMapping,
                expectedOpcode: 0x84,
                expectedSubtype: nil
            ),
        ]

        for row in rows {
            var current = AhaKeyStudioDraft.default
            let synced = current
            row.mutate(&current)

            // 该页全部字段都有 verified live baseline（非 whole-group、无 unknown sibling）。
            let syncedSnapshot = synced.frozenPageSnapshot(
                pageID: row.pageID,
                lastSyncedDraft: synced,
                profile: profile
            )
            var authorities: [AhaKeyStudioFieldID: AhaKeyStudioFieldAuthority] = [:]
            var pageBaselines: [AhaKeyRuntimeFieldBaseline] = []
            for field in syncedSnapshot.fields {
                authorities[field.id] = AhaKeyStudioFieldAuthority(
                    value: field.value,
                    trust: .verified,
                    provenance: .deviceReadback
                )
                if let baselineValue = runtimeBaselineValue(field.value) {
                    pageBaselines.append(AhaKeyRuntimeFieldBaseline(
                        deviceID: deviceID,
                        pageID: row.pageID,
                        fieldID: field.id,
                        value: baselineValue,
                        trust: .verified,
                        provenance: .deviceReadback
                    ))
                }
            }

            let snapshotWithBaselines = makeSnapshot(
                deviceID: deviceID,
                pageBaselines: pageBaselines,
                authoritativeObject: nil
            )
            let transport = FakeTransport(snapshot: snapshotWithBaselines)
            let facade = AhaKeyStudioRuntimeFacade(
                transport: transport,
                clientBuildID: "test",
                reconnectBackoffBase: 0,
                idlePollInterval: 0
            )
            let store = AhaKeyStudioRuntimeClient(facade: facade)
            await facade.installSnapshotForTesting(snapshotWithBaselines)
            store.applyViewStateForTesting(onlineState(snapshot: snapshotWithBaselines))
            let coordinator = AhaKeyStudioPageCommitCoordinator(registry: store.pageCommitExecutions)
            coordinator.attach()
            let port = RecordingStoreCommitPort(store: store)

            func makeInput() -> AhaKeyStudioPageSubmissionInput {
                AhaKeyStudioPageSubmissionInput(
                    deviceID: deviceID,
                    sessionGeneration: .init(0),
                    transportGeneration: .init(0),
                    snapshot: current.frozenPageSnapshot(
                        pageID: row.pageID,
                        lastSyncedDraft: synced,
                        fieldAuthorities: authorities,
                        profile: profile,
                        overwriteConfirmed: false
                    ),
                    explicitIntentFieldIDs: [],
                    retryResidual: false
                )
            }

            // ---- 第一击：未确认 → Facade schema=3 authority requires，零 apply/ingest ----
            let firstInput = makeInput()
            coordinator.observeIdentity(firstInput.confirmationIdentity)
            let first = await runCoordinatorSubmit(coordinator, firstInput, port: port)
            XCTAssertEqual(
                first.outcome,
                .requiresOverwriteConfirmation,
                "\(row.name) 未确认必须由 Facade schema=3 authority 要求确认"
            )
            XCTAssertEqual(port.snapshots.count, 1, "\(row.name)")
            XCTAssertEqual(port.snapshots[0].overwriteConfirmed, false, "\(row.name)")
            var counts = await facade.pageSubmitRecordingCountsForTesting()
            XCTAssertEqual(counts.apply, 0, "\(row.name) 未确认不得 apply")
            XCTAssertEqual(counts.ingest, 0, "\(row.name) 未确认不得 ingest")
            XCTAssertNil(transport.appliedPackage, "\(row.name) 未确认不得产出 package")

            // ---- 第二击：exact 同输入 → confirmed=true → accepted，wire 精确 ----
            let secondInput = makeInput()
            XCTAssertEqual(secondInput, firstInput, "\(row.name) 两击必须是同一份 exact 冻结输入")
            let second = await runCoordinatorSubmit(coordinator, secondInput, port: port)
            guard case .accepted = second.outcome else {
                return XCTFail("\(row.name) 确认后必须 accepted，实得 \(second.outcome)")
            }
            XCTAssertEqual(port.snapshots.count, 2, "\(row.name)")
            XCTAssertEqual(port.snapshots[1].overwriteConfirmed, true, "\(row.name)")

            counts = await facade.pageSubmitRecordingCountsForTesting()
            XCTAssertEqual(counts.apply, 1, "\(row.name) 确认后必须恰好 apply 一次")
            XCTAssertEqual(counts.ingest, 0, "\(row.name) key/light 不得 ingest")

            let package = try XCTUnwrap(transport.appliedPackage, "\(row.name)")
            XCTAssertEqual(
                package.schemaVersion,
                AhaKeyConfigurationPackage.fieldBaselineSchemaVersion,
                "\(row.name) 无 whole-object 必须走 schema=3"
            )
            let pageOperation = try XCTUnwrap(package.pageOperation, "\(row.name)")
            XCTAssertEqual(pageOperation.fieldMask, [row.expectedFieldID], "\(row.name)")
            XCTAssertNil(pageOperation.baseObjectFingerprint, "\(row.name) 不得伪造 whole-object")
            XCTAssertNotNil(pageOperation.fieldBaselines, "\(row.name) schema=3 必须有 field-baseline proof")
            XCTAssertTrue(pageOperation.resourceBindings.isEmpty, "\(row.name)")
            XCTAssertTrue(package.resources.isEmpty, "\(row.name)")

            let actions = pageOperation.compatibilityFingerprint.actions
            XCTAssertEqual(actions.count, 1, "\(row.name) 必须恰好一个 emitted action")
            let action = try XCTUnwrap(actions.first, "\(row.name)")
            XCTAssertEqual(action.fieldID, row.expectedFieldID, "\(row.name)")
            XCTAssertEqual(action.command, row.expectedCommand, "\(row.name)")
            XCTAssertEqual(action.opcode, row.expectedOpcode, "\(row.name)")
            XCTAssertEqual(action.subtype, row.expectedSubtype, "\(row.name)")
            XCTAssertNil(action.logicalSet, "\(row.name)")
            XCTAssertNil(action.physicalSlot, "\(row.name)")
            XCTAssertNil(action.displayState, "\(row.name)")
            XCTAssertEqual(action.activation, .none, "\(row.name)")
            XCTAssertEqual(action.binding, .none, "\(row.name)")
            XCTAssertEqual(action.session, .none, "\(row.name)")
            XCTAssertEqual(action.geometry, .none, "\(row.name)")
            XCTAssertNil(action.resourceIdentity, "\(row.name)")
            XCTAssertNil(action.encodedFrameCount, "\(row.name)")
            // 显式排除其它语义 action。
            XCTAssertFalse(actions.contains { candidate in
                switch candidate.command {
                case .setActiveSet, .screenStatus, .screenFramesPerSecond, .picture:
                    return true
                default:
                    return false
                }
            }, "\(row.name) 不得混入 activeSet/status/FPS/picture action")
            if row.expectedCommand == .lightMapping {
                XCTAssertEqual(
                    pageOperation.compatibilityFingerprint.lightMappingRows.count,
                    1,
                    "\(row.name) 必须冻结一行 9-state 0x84 行"
                )
            } else {
                XCTAssertTrue(
                    pageOperation.compatibilityFingerprint.lightMappingRows.isEmpty,
                    "\(row.name) 不得混入 0x84 light 行"
                )
            }
            await facade.stop()
        }
    }

    func testTwoPagesCanQueueInDeviceFIFOFromSnapshot() async throws {
        let harness = try makeHarness()
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: []))
        harness.store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [])))
        let first = try await harness.store.commitFrozenPage(keySnapshot(text: "one"))
        let second = try await harness.store.commitFrozenPage(
            AhaKeyStudioPageSnapshot(
                pageID: .lights(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .lightBrightness(modeSlot: 0),
                        value: .integer(40),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .integer(35))
                    ),
                ]
            )
        )
        guard case .accepted(let firstID) = first, case .accepted(let secondID) = second else {
            return XCTFail("两页都应独立进入队列")
        }
        XCTAssertNotEqual(firstID, secondID)
        let queued = [
            summary(id: firstID, device: harness.deviceID, state: .accepted, pageID: .key(modeSlot: 0, role: .voice), queueOrder: 1),
            summary(id: secondID, device: harness.deviceID, state: .accepted, pageID: .lights(modeSlot: 0), queueOrder: 2),
        ]
        let fresh = makeStore()
        fresh.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: queued)))
        XCTAssertEqual(fresh.deviceFIFO.count, 2)
        XCTAssertEqual(fresh.deviceFIFO.map(\.pageID), queued.map(\.pageID))
        await harness.facade.stop()
    }

    func testDeviceFIFOAndCurrentOperationFollowDurableOrderNotUUID() throws {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let earlierID = AhaKeyRuntimeOperationID(
            UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!
        )
        let laterID = AhaKeyRuntimeOperationID(
            UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!
        )
        XCTAssertGreaterThan(earlierID.rawValue.uuidString, laterID.rawValue.uuidString)
        let uuidOrderedLive = [
            summary(
                id: laterID,
                device: deviceID,
                state: .accepted,
                pageID: .lights(modeSlot: 0),
                queueOrder: 2
            ),
            summary(
                id: earlierID,
                device: deviceID,
                state: .running,
                pageID: .screen(modeSlot: 0),
                queueOrder: 1
            ),
        ]
        let liveStore = makeStore()
        liveStore.applyViewStateForTesting(onlineState(snapshot: makeSnapshot(
            deviceID: deviceID,
            operations: uuidOrderedLive
        )))
        XCTAssertEqual(liveStore.deviceFIFO.map(\.id), [earlierID, laterID])
        XCTAssertEqual(liveStore.operation(for: .screen(modeSlot: 0))?.id, earlierID)

        let uuidOrderedTerminals = [
            summary(
                id: laterID,
                device: deviceID,
                state: .completed,
                pageID: .screen(modeSlot: 0),
                terminalOrder: 2
            ),
            summary(
                id: earlierID,
                device: deviceID,
                state: .completed,
                pageID: .screen(modeSlot: 0),
                terminalOrder: 1
            ),
        ]
        let terminalStore = makeStore()
        terminalStore.applyViewStateForTesting(onlineState(snapshot: makeSnapshot(
            deviceID: deviceID,
            operations: uuidOrderedTerminals
        )))
        XCTAssertEqual(terminalStore.operation(for: .screen(modeSlot: 0))?.id, laterID)
    }

    private struct Harness {
        var deviceID: AhaKeyRuntimeDeviceID
        var transport: FakeTransport
        var facade: AhaKeyStudioRuntimeFacade
        var store: AhaKeyStudioRuntimeClient

        func snapshot(
            operations: [AhaKeyRuntimeOperationSummary],
            connected: Bool = true
        ) -> AhaKeyRuntimeSnapshot {
            makeSnapshot(
                deviceID: deviceID,
                connected: connected,
                operations: operations
            )
        }
    }

    /// C5HR1：用 studio 冻结值构造 durable live baseline 行（只覆盖 key/light 矩阵用到的标量类型）。
    private func runtimeBaselineValue(_ value: AhaKeyStudioFieldValue) -> AhaKeyRuntimeBaselineValue? {
        switch value {
        case .text(let text):
            return .text(text)
        case .optionalText(let text):
            return .optionalText(text)
        case .integer(let number):
            return .integer(number)
        case .keyAction(let action):
            return .keyAction(action)
        case .taskAsset:
            return nil
        }
    }

    private func makeStore() -> AhaKeyStudioRuntimeClient {
        let transport = FakeTransport(snapshot: makeSnapshot(deviceID: try! AhaKeyRuntimeDeviceID("DEVICE-1")))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        return AhaKeyStudioRuntimeClient(facade: facade)
    }

    private func makeHarness() throws -> Harness {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let transport = FakeTransport(snapshot: makeSnapshot(deviceID: deviceID, operations: []))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport,
            clientBuildID: "test",
            reconnectBackoffBase: 0,
            idlePollInterval: 0
        )
        let store = AhaKeyStudioRuntimeClient(facade: facade)
        let harness = Harness(deviceID: deviceID, transport: transport, facade: facade, store: store)
        store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [])))
        return harness
    }

    private func onlineState(snapshot: AhaKeyRuntimeSnapshot) -> AhaKeyStudioRuntimeViewState {
        AhaKeyStudioRuntimeViewState(connection: .online, snapshot: snapshot)
    }

    private func keySnapshot(text: String) -> AhaKeyStudioPageSnapshot {
        AhaKeyStudioPageSnapshot(
            pageID: .key(modeSlot: 0, role: .voice),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            fields: [
                AhaKeyStudioFrozenField(
                    id: .keyDescription(modeSlot: 0, role: .voice),
                    value: .text(text),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .text("old"))
                ),
            ]
        )
    }

    private func screenSnapshot(extraFPS: Bool = false) -> AhaKeyStudioPageSnapshot {
        var fields = [
            AhaKeyStudioFrozenField(
                id: .screenStatusLine(modeSlot: 0),
                value: .text("remain"),
                isDirty: true,
                baseline: .init(trust: .verified, value: .text("old"))
            ),
        ]
        if extraFPS {
            fields.append(
                AhaKeyStudioFrozenField(
                    id: .screenFramesPerSecond(modeSlot: 0),
                    value: .integer(18),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(12))
                )
            )
        }
        return AhaKeyStudioPageSnapshot(
            pageID: .screen(modeSlot: 0),
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            fields: fields
        )
    }

    private func summary(
        id: AhaKeyRuntimeOperationID,
        device: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        pageID: AhaKeyStudioPageID? = nil,
        residual: AhaKeyRuntimePageResidual? = nil,
        abandonEligibility: AhaKeyRuntimeAbandonEligibility? = nil,
        queueOrder: UInt64? = nil,
        terminalOrder: UInt64? = nil
    ) -> AhaKeyRuntimeOperationSummary {
        try! AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: device,
            state: state,
            residual: residual,
            pageID: pageID,
            abandonEligibility: abandonEligibility,
            durableOrdering: state.isTerminal
                ? .terminal(terminalOrder: terminalOrder ?? 1)
                : .live(queueOrder: queueOrder ?? 1)
        )
    }
}

private func makeSnapshot(
    deviceID: AhaKeyRuntimeDeviceID,
    extraDevices: [AhaKeyRuntimeDeviceID] = [],
    connected: Bool = true,
    protocolState: AhaKeyRuntimeDeviceProtocolState = .currentReady,
    oledCompatibility: AhaKeyRuntimeOLEDCompatibilityFact? = .init(
        family: .rhinoDualSet,
        sessionUploadAdvertised: false
    ),
    operations: [AhaKeyRuntimeOperationSummary] = [],
    pageBaselines: [AhaKeyRuntimeFieldBaseline] = [],
    /// C5H：schema=3（field-baseline）路径只在**无 whole-object** 时被选中；
    /// 传 nil 才能复现 R5 的 `PageBaseAuthority` 二次确认门。
    authoritativeObject: Data? = Data("base-object".utf8)
) -> AhaKeyRuntimeSnapshot {
    var devices = [
        AhaKeyRuntimeDeviceSnapshot(
            id: deviceID,
            displayName: "Test AhaKey",
            protocolState: protocolState,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: connected,
            capabilities: [AhaKeyOLEDWritePreflight.routingCapability],
            authoritativeObject: authoritativeObject,
            oledCompatibility: oledCompatibility
        ),
    ]
    for extra in extraDevices {
        devices.append(
            AhaKeyRuntimeDeviceSnapshot(
                id: extra,
                displayName: extra.rawValue,
                protocolState: .currentReady,
                preferredTransport: .bluetooth,
                usbAttached: false,
                bluetoothConnected: true
            )
        )
    }
    return AhaKeyRuntimeSnapshot(
        supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
        lifecycleState: .running,
        devices: devices,
        activeDeviceID: deviceID,
        configurationRevision: .init(0),
        operations: operations,
        policy: .init(),
        permissions: .init(states: [:]),
        keepAliveReasons: [],
        latestEventSequence: .init(0),
        pageBaselines: pageBaselines
    )
}

/// C5GR6：可控挂起 `.apply` 的 transport，用来把 production invocation 停在「已进入 port」的状态。
private final class SuspendingApplyTransport: AhaKeyStudioRuntimeTransport, @unchecked Sendable {
    var snapshot: AhaKeyRuntimeSnapshot
    private(set) var reachedApply = false
    private var applyContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: AhaKeyRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func releaseApply() {
        let pending = applyContinuation
        applyContinuation = nil
        pending?.resume()
    }

    func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        switch request {
        case .handshake:
            return .handshakeAccepted(.init(
                runtimeVersion: .development,
                interfaceVersion: .current,
                supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
                capabilities: [.snapshot, .eventReplay, .configuration]
            ))
        case .snapshot:
            return .snapshot(snapshot)
        case .events:
            return .eventReplay(.events([]))
        case .ingestResources:
            return .resourcesIngested
        case .apply(let package, _):
            reachedApply = true
            await withCheckedContinuation { applyContinuation = $0 }
            return .operationAccepted(package.operationID)
        default:
            return .failure(try AhaKeyRuntimeEventCode("unsupported"))
        }
    }
}

/// C5G：记录每次冻结 snapshot，再转发给真实 Store→Facade 写入口。
@MainActor
private final class RecordingStoreCommitPort: AhaKeyStudioPageCommitPort {
    let store: AhaKeyStudioRuntimeClient
    private(set) var snapshots: [AhaKeyStudioPageSnapshot] = []

    init(store: AhaKeyStudioRuntimeClient) {
        self.store = store
    }

    func commitFrozenPage(
        _ snapshot: AhaKeyStudioPageSnapshot,
        retryResidual: Bool
    ) async throws -> AhaKeyStudioPageCommitResult {
        snapshots.append(snapshot)
        return try await store.commitFrozenPage(snapshot, retryResidual: retryResidual)
    }
}

private final class FakeTransport: AhaKeyStudioRuntimeTransport, @unchecked Sendable {
    var snapshot: AhaKeyRuntimeSnapshot
    var cancellationDisposition: AhaKeyRuntimeCancellationDisposition = .requested
    var abandonDisposition: AhaKeyRuntimeAbandonDisposition = .abandoned
    private(set) var appliedPackage: AhaKeyConfigurationPackage?
    private(set) var cancelledOperation: AhaKeyRuntimeOperationID?
    private(set) var abandonedOperation: AhaKeyRuntimeOperationID?

    init(snapshot: AhaKeyRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        switch request {
        case .handshake:
            return .handshakeAccepted(.init(
                runtimeVersion: .development,
                interfaceVersion: .current,
                supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
                capabilities: [.snapshot, .eventReplay, .configuration]
            ))
        case .snapshot:
            return .snapshot(snapshot)
        case .events:
            return .eventReplay(.events([]))
        case .ingestResources:
            return .resourcesIngested
        case .apply(let package, _):
            appliedPackage = package
            return .operationAccepted(package.operationID)
        case .requestCancellation(let operationID):
            cancelledOperation = operationID
            return .cancellation(cancellationDisposition)
        case .requestAbandon(let operationID):
            abandonedOperation = operationID
            return .abandon(abandonDisposition)
        default:
            return .failure(try AhaKeyRuntimeEventCode("unsupported"))
        }
    }
}

/// C5GR2：生产路径是同步 `start`；终结投影经 `projectionRevision` 事件发布。
@MainActor
private func runCoordinatorSubmit(
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
