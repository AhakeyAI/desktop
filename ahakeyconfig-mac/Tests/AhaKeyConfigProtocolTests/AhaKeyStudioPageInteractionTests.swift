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

    func testDuplicateSubmitAndQueuedRemoveVersusRunningRefuse() async throws {
        let harness = try makeHarness()
        let keyPage = AhaKeyStudioPageID.key(modeSlot: 0, role: .voice)
        let lightsPage = AhaKeyStudioPageID.lights(modeSlot: 0)
        let queuedID = AhaKeyRuntimeOperationID()
        let runningID = AhaKeyRuntimeOperationID()
        let queued = summary(id: queuedID, device: harness.deviceID, state: .accepted)
        let running = summary(id: runningID, device: harness.deviceID, state: .running)
        harness.store.applyViewStateForTesting(
            onlineState(snapshot: harness.snapshot(operations: [running, queued]))
        )
        harness.store.bindPageOperationForTesting(pageID: keyPage, operationID: queuedID)
        harness.store.bindPageOperationForTesting(pageID: lightsPage, operationID: runningID)

        do {
            _ = try await harness.store.commitFrozenPage(keySnapshot(text: "again"))
            XCTFail("同页排队中必须拒绝重复提交")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .pageAlreadyInFlight)
        }

        let removed = try await harness.store.removeQueuedPage(keyPage)
        XCTAssertEqual(removed, .requested)
        XCTAssertNil(harness.store.operation(for: keyPage))

        do {
            _ = try await harness.store.removeQueuedPage(lightsPage)
            XCTFail("running 必须拒绝普通取消")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .runningCannotBeCancelled)
        }
        XCTAssertEqual(harness.store.operation(for: lightsPage)?.id, runningID)
        await harness.facade.stop()
    }

    func testAbandonRequiresSixtySecondDisconnect() async throws {
        let harness = try makeHarness()
        let page = AhaKeyStudioPageID.screen(modeSlot: 0)
        let operationID = AhaKeyRuntimeOperationID()
        let paused = summary(id: operationID, device: harness.deviceID, state: .paused)
        let snapshot = harness.snapshot(operations: [paused], connected: false)
        harness.store.applyViewStateForTesting(onlineState(snapshot: snapshot))
        harness.store.bindPageOperationForTesting(pageID: page, operationID: operationID)
        harness.store.markDisconnectedForTesting(since: Date().addingTimeInterval(-59))
        do {
            _ = try await harness.store.requestAbandon(of: page)
            XCTFail("未满 60 秒不得放弃")
        } catch {
            XCTAssertEqual(error as? AhaKeyStudioStoreApplyError, .abandonNotEligible)
        }

        let readyAt = Date().addingTimeInterval(-AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
        harness.store.markDisconnectedForTesting(since: readyAt)
        let abandoned = try await harness.store.requestAbandon(of: page, now: Date())
        XCTAssertEqual(abandoned, .abandoned)
        XCTAssertNil(harness.store.operation(for: page))
        await harness.facade.stop()
    }

    func testResidualRetryUsesOverlayAndAllowsPartialRecommit() async throws {
        let harness = try makeHarness()
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: []))
        let page = AhaKeyStudioPageID.screen(modeSlot: 0)
        let operationID = AhaKeyRuntimeOperationID()
        let partial = summary(
            id: operationID,
            device: harness.deviceID,
            state: .resumablePartial,
            residual: AhaKeyRuntimePageResidual(fieldIDs: [.screenStatusLine(modeSlot: 0)])
        )
        harness.store.applyViewStateForTesting(onlineState(snapshot: harness.snapshot(operations: [partial])))
        harness.store.bindPageOperationForTesting(pageID: page, operationID: operationID)
        await harness.facade.installSnapshotForTesting(harness.snapshot(operations: [partial]))

        let bothDirty = AhaKeyStudioPageSnapshot(
            pageID: page,
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            fields: [
                AhaKeyStudioFrozenField(
                    id: .screenStatusLine(modeSlot: 0),
                    value: .text("remain"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .text("old"))
                ),
                AhaKeyStudioFrozenField(
                    id: .screenFramesPerSecond(modeSlot: 0),
                    value: .integer(18),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(12))
                ),
            ]
        )
        let result = try await harness.store.commitFrozenPage(bothDirty, retryResidual: true)
        guard case .accepted = result else {
            return XCTFail("partial residual 应允许再次提交")
        }
        XCTAssertEqual(harness.transport.appliedPackage?.pageOperation?.fieldMask, [.screenStatusLine(modeSlot: 0)])
        XCTAssertFalse(
            harness.transport.appliedPackage?.pageOperation?.fieldMask.contains(.screenFramesPerSecond(modeSlot: 0)) ?? true
        )
        await harness.facade.stop()
    }

    func testTwoPagesCanQueueInDeviceFIFO() async throws {
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
        XCTAssertEqual(harness.store.pageOperationIDs.count, 2)
        await harness.facade.stop()
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
            let device = AhaKeyRuntimeDeviceSnapshot(
                id: deviceID,
                displayName: "Test AhaKey",
                protocolState: .currentReady,
                preferredTransport: .bluetooth,
                usbAttached: false,
                bluetoothConnected: connected,
                capabilities: [AhaKeyOLEDWritePreflight.routingCapability],
                authoritativeObject: Data("base-object".utf8)
            )
            return AhaKeyRuntimeSnapshot(
                supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
                lifecycleState: .running,
                devices: [device],
                activeDeviceID: deviceID,
                configurationRevision: .init(0),
                operations: operations,
                policy: .init(),
                permissions: .init(states: [:]),
                keepAliveReasons: [],
                latestEventSequence: .init(0)
            )
        }
    }

    private func makeHarness() throws -> Harness {
        let deviceID = try AhaKeyRuntimeDeviceID("DEVICE-1")
        let transport = FakeTransport(
            snapshot: AhaKeyRuntimeSnapshot(
                supportedConfigurationSchemaVersions: AhaKeyConfigurationPackage.advertisedSchemaVersions,
                lifecycleState: .running,
                devices: [],
                activeDeviceID: nil,
                configurationRevision: .init(0),
                operations: [],
                policy: .init(),
                permissions: .init(states: [:]),
                keepAliveReasons: [],
                latestEventSequence: .init(0)
            )
        )
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

    private func summary(
        id: AhaKeyRuntimeOperationID,
        device: AhaKeyRuntimeDeviceID,
        state: AhaKeyRuntimeOperationState,
        residual: AhaKeyRuntimePageResidual? = nil
    ) -> AhaKeyRuntimeOperationSummary {
        AhaKeyRuntimeOperationSummary(
            id: id,
            targetDeviceID: device,
            state: state,
            residual: residual
        )
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
