import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyRuntimeContractTests: XCTestCase {
    func testPackageRejectsUnsafeOrDuplicateResourceIdentifiers() throws {
        let digest = String(repeating: "a", count: 64)
        XCTAssertThrowsError(
            try AhaKeyConfigurationResource(
                logicalIdentifier: "../image.gif",
                sha256: digest,
                byteCount: 10,
                mediaType: "image/gif"
            )
        )

        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: "mode1-setA-working",
            sha256: digest,
            byteCount: 10,
            mediaType: "image/gif"
        )
        XCTAssertThrowsError(
            try package(resources: [resource, resource])
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .duplicateResourceIdentifier)
        }
    }

    func testCodableDecodingCannotBypassContractValidation() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeDeviceID.self, from: Data("\"   \"".utf8))
        )

        let invalidResource = Data(
            """
            {"logicalIdentifier":"../escape","sha256":"bad","byteCount":1,"mediaType":"image/gif"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyConfigurationResource.self, from: invalidResource)
        )

        let validPackage = try package()
        let encoded = try JSONEncoder().encode(validPackage)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["desiredConfiguration"] = ""
        let invalidPackage = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyConfigurationPackage.self, from: invalidPackage)
        )
    }

    func testApplyIsIdempotentButRejectsOperationIDReuseWithDifferentContent() async throws {
        let adapter = try makeAdapter()
        let operationID = AhaKeyRuntimeOperationID()
        let first = try package(operationID: operationID, desiredConfiguration: Data("one".utf8))

        let firstAcceptance = try await adapter.apply(first)
        let repeatedAcceptance = try await adapter.apply(first)
        XCTAssertEqual(firstAcceptance, operationID)
        XCTAssertEqual(repeatedAcceptance, operationID)

        let conflicting = try package(operationID: operationID, desiredConfiguration: Data("two".utf8))
        do {
            _ = try await adapter.apply(conflicting)
            XCTFail("Expected operation identifier conflict")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .operationIdentifierConflict)
        }
    }

    func testApplyRejectsStaleRevisionAndWrongTargetDevice() async throws {
        let adapter = try makeAdapter(revision: 3)

        do {
            _ = try await adapter.apply(package(baseRevision: 2))
            XCTFail("Expected stale revision")
        } catch {
            XCTAssertEqual(
                error as? AhaKeyRuntimeContractError,
                .staleConfigurationRevision(expected: .init(3), received: .init(2))
            )
        }

        do {
            _ = try await adapter.apply(package(targetDeviceID: "OTHER", baseRevision: 3))
            XCTFail("Expected target mismatch")
        } catch {
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .targetDeviceMismatch)
        }
    }

    func testSubscriberReceivesAcceptedOperationAndCanReplayIt() async throws {
        let adapter = try makeAdapter()
        let stream = await adapter.events(after: nil)
        let package = try package()
        _ = try await adapter.apply(package)

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.sequence, .init(1))
        XCTAssertEqual(first?.context.operationID, package.operationID)
        XCTAssertEqual(first?.context.deviceID, package.targetDeviceID)
        XCTAssertEqual(first?.context.sessionGeneration, .init(4))
        XCTAssertEqual(first?.context.transportGeneration, .init(9))
        XCTAssertEqual(
            first?.payload,
            .operationChanged(
                AhaKeyRuntimeOperationSummary(
                    id: package.operationID,
                    targetDeviceID: package.targetDeviceID,
                    state: .accepted
                )
            )
        )

        let replay = await adapter.events(after: .init(0))
        var replayIterator = replay.makeAsyncIterator()
        let replayedEvent = try await replayIterator.next()
        XCTAssertEqual(replayedEvent, first)
    }

    func testCompletionAdvancesRevisionAndCancellationDoesNot() async throws {
        let adapter = try makeAdapter(revision: 7)
        let first = try package(baseRevision: 7)
        _ = try await adapter.apply(first)
        let cancellation = try await adapter.requestCancellation(of: first.operationID)
        let revisionAfterCancellation = try await adapter.snapshot().configurationRevision
        XCTAssertEqual(cancellation, .requested)
        XCTAssertEqual(revisionAfterCancellation, .init(7))

        let second = try package(baseRevision: 7)
        _ = try await adapter.apply(second)
        try await adapter.complete(operation: second.operationID, state: .completed)
        let completedRevision = try await adapter.snapshot().configurationRevision
        let completedCancellation = try await adapter.requestCancellation(of: second.operationID)
        XCTAssertEqual(completedRevision, .init(8))
        XCTAssertEqual(completedCancellation, .alreadyFinished)
    }

    func testPartialCompletionDoesNotConfirmTargetRevision() async throws {
        let adapter = try makeAdapter(revision: 11)
        let package = try package(baseRevision: 11)
        _ = try await adapter.apply(package)

        try await adapter.recordResumablePartial(
            operation: package.operationID,
            completedSteps: 2,
            totalSteps: 5
        )

        let snapshot = try await adapter.snapshot()
        XCTAssertEqual(snapshot.configurationRevision, .init(11))
        XCTAssertEqual(snapshot.operations.first?.state, .resumablePartial)
        XCTAssertEqual(snapshot.operations.first?.completedSteps, 2)
        XCTAssertEqual(snapshot.operations.first?.totalSteps, 5)
    }

    func testCompletedOperationCanBeReplayedIdempotentlyAfterRevisionAdvances() async throws {
        let adapter = try makeAdapter(revision: 2)
        let package = try package(baseRevision: 2)
        _ = try await adapter.apply(package)
        try await adapter.complete(operation: package.operationID, state: .completed)

        let replayedID = try await adapter.apply(package)
        let replayedSnapshot = try await adapter.snapshot()

        XCTAssertEqual(replayedID, package.operationID)
        XCTAssertEqual(replayedSnapshot.configurationRevision, .init(3))
    }

    func testPolicyKeepsRuntimeOnlyForComputerSideEnhancements() {
        XCTAssertFalse(AhaKeyRuntimePolicy().requiresPersistentRuntime)
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                aiHooks: .init(enabledTools: [.codex], approvalPolicy: .manual)
            ).requiresPersistentRuntime
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                ahaType: .init(enabled: true, trigger: .f18)
            ).requiresPersistentRuntime
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(voiceRouting: .latestActionableSession).requiresPersistentRuntime
        )
        XCTAssertFalse(AhaKeyRuntimePolicy().requiresDeviceConnection)
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                aiHooks: .init(
                    enabledTools: [.kimi],
                    approvalPolicy: .followLever(automaticPosition: .up)
                )
            ).requiresDeviceConnection
        )
        XCTAssertTrue(
            AhaKeyRuntimePolicy(
                devicePresentation: .init(ledEnabled: true, oledEnabled: false)
            ).requiresDeviceConnection
        )
    }

    func testEquivalentPolicyUpdateDoesNotPublishRuntimeState() async throws {
        let adapter = try makeAdapter()

        try await adapter.updatePolicy(.init())
        let unchangedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(unchangedSnapshot.latestEventSequence, .init(0))

        let changed = AhaKeyRuntimePolicy(voiceRouting: .latestActionableSession)
        try await adapter.updatePolicy(changed)
        let changedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(changedSnapshot.latestEventSequence, .init(1))
        XCTAssertEqual(changedSnapshot.policy, changed)
        XCTAssertEqual(changedSnapshot.keepAliveReasons, [.sessionRouting])
    }

    func testRuntimePolicyRoundTripPreservesTriggerApprovalRoutingAndDiagnostics() throws {
        let policy = AhaKeyRuntimePolicy(
            ahaType: .init(
                enabled: true,
                trigger: .init(hidUsage: 0x6D, modifiers: [.function])
            ),
            aiHooks: .init(
                enabledTools: [.claude, .codex, .cursor, .kimi],
                approvalPolicy: .followLever(automaticPosition: .up)
            ),
            voiceRouting: .latestActionableSession,
            devicePresentation: .init(ledEnabled: true, oledEnabled: true),
            powerProtectionEnabled: true,
            diagnostics: .init(verboseProtocolLoggingUntil: Date(timeIntervalSince1970: 1_800))
        )

        let encoded = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimePolicy.self, from: encoded)

        XCTAssertEqual(decoded, policy)
        XCTAssertTrue(decoded.requiresPersistentRuntime)
        XCTAssertTrue(decoded.requiresDeviceConnection)
        XCTAssertEqual(
            decoded.keepAliveReasons,
            [.ahaType, .aiHooks, .dynamicDeviceState, .sessionRouting, .powerProtection, .temporaryDiagnostics]
        )
    }

    func testSnapshotCodableRoundTripPreservesRuntimeAndDeviceDiagnostics() async throws {
        let adapter = try makeAdapter()
        let snapshot = try await adapter.snapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimeSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.runtimeVersion, .init(major: 0, minor: 1, patch: 0, buildMetadata: "development"))
        XCTAssertEqual(decoded.permissions[.microphone], .notDetermined)
        XCTAssertEqual(decoded.devices.first?.capabilities, [.configurationV4, .usbConfiguration])
        XCTAssertEqual(decoded.devices.first?.sessionGeneration, .init(4))
        XCTAssertEqual(decoded.devices.first?.transportGeneration, .init(9))
        XCTAssertEqual(decoded.devices.first?.state.leverPosition, .middle)
        XCTAssertEqual(
            decoded.devices.first?.state.activeTaskPictureSets,
            [.init(2): .init(1)]
        )
    }

    func testStructuredDiagnosticAndSecurityEventsRoundTrip() throws {
        let events = [
            AhaKeyRuntimeEvent(
                sequence: .init(1),
                payload: .diagnostic(.init(code: try .init("transport-timeout"), severity: .warning))
            ),
            AhaKeyRuntimeEvent(
                sequence: .init(2),
                payload: .security(.init(code: try .init("hook-rate-limited"), severity: .error))
            ),
        ]

        let encoded = try JSONEncoder().encode(events)
        XCTAssertEqual(try JSONDecoder().decode([AhaKeyRuntimeEvent].self, from: encoded), events)
    }

    func testPermanentFailureStatesDistinguishWhetherDeviceWasModified() {
        XCTAssertTrue(AhaKeyRuntimeOperationState.failedWithoutWrites.isTerminal)
        XCTAssertTrue(AhaKeyRuntimeOperationState.failedWithPartialCommit.isTerminal)
        XCTAssertTrue(AhaKeyRuntimeOperationState.resumablePartial.isRecoveryCandidate)
        XCTAssertFalse(AhaKeyRuntimeOperationState.resumablePartial.isTerminal)
        XCTAssertNotEqual(
            AhaKeyRuntimeOperationState.failedWithoutWrites,
            AhaKeyRuntimeOperationState.failedWithPartialCommit
        )
    }

    private func makeAdapter(revision: UInt64 = 0) throws -> AhaKeyInMemoryRuntimeAdapter {
        let id = try AhaKeyRuntimeDeviceID("505c")
        let device = AhaKeyRuntimeDeviceSnapshot(
            id: id,
            displayName: "AhaKey 505C",
            protocolState: .currentReady,
            preferredTransport: .usb,
            usbAttached: true,
            bluetoothConnected: false,
            capabilities: [.configurationV4, .usbConfiguration],
            sessionGeneration: .init(4),
            transportGeneration: .init(9),
            state: .init(
                batteryLevel: try .init(85),
                workMode: .init(2),
                lightMode: .init(1),
                leverPosition: .middle,
                brightness: try .init(35),
                firmwareVersion: "3.0",
                activeTaskPictureSets: [.init(2): .init(1)]
            )
        )
        return AhaKeyInMemoryRuntimeAdapter(
            snapshot: AhaKeyRuntimeSnapshot(
                lifecycleState: .running,
                devices: [device],
                activeDeviceID: id,
                configurationRevision: .init(revision),
                operations: [],
                policy: .init(),
                permissions: .init(states: [.microphone: .notDetermined]),
                keepAliveReasons: [],
                latestEventSequence: .init(0)
            )
        )
    }

    private func package(
        operationID: AhaKeyRuntimeOperationID = .init(),
        targetDeviceID: String = "505C",
        baseRevision: UInt64 = 0,
        desiredConfiguration: Data = Data("configuration".utf8),
        resources: [AhaKeyConfigurationResource] = []
    ) throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage(
            operationID: operationID,
            targetDeviceID: AhaKeyRuntimeDeviceID(targetDeviceID),
            baseRevision: .init(baseRevision),
            desiredConfiguration: desiredConfiguration,
            resources: resources
        )
    }
}
