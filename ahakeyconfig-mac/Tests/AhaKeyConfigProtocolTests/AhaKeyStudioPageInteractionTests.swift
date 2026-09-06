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
                queued.withState(.cancellationRequested),
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
        AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: device,
            state: state,
            residual: residual,
            pageID: pageID,
            abandonEligibility: abandonEligibility,
            queueOrder: queueOrder,
            terminalOrder: terminalOrder
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
    pageBaselines: [AhaKeyRuntimeFieldBaseline] = []
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
            authoritativeObject: Data("base-object".utf8),
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
        case .apply(let package):
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
