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

        try await adapter.complete(operation: package.operationID, state: .partiallyCompleted)

        let snapshot = try await adapter.snapshot()
        XCTAssertEqual(snapshot.configurationRevision, .init(11))
        XCTAssertEqual(snapshot.operations.first?.state, .partiallyCompleted)
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
        XCTAssertTrue(AhaKeyRuntimePolicy(aiHooksEnabled: true).requiresPersistentRuntime)
        XCTAssertTrue(AhaKeyRuntimePolicy(ahaTypeEnabled: true).requiresPersistentRuntime)
        XCTAssertTrue(AhaKeyRuntimePolicy(sessionRoutingEnabled: true).requiresPersistentRuntime)
        XCTAssertFalse(AhaKeyRuntimePolicy().requiresDeviceConnection)
        XCTAssertTrue(AhaKeyRuntimePolicy(dynamicDeviceStateEnabled: true).requiresDeviceConnection)
    }

    func testEquivalentPolicyUpdateDoesNotPublishRuntimeState() async throws {
        let adapter = try makeAdapter()

        try await adapter.updatePolicy(.init())
        let unchangedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(unchangedSnapshot.latestEventSequence, .init(0))

        let changed = AhaKeyRuntimePolicy(sessionRoutingEnabled: true)
        try await adapter.updatePolicy(changed)
        let changedSnapshot = try await adapter.snapshot()
        XCTAssertEqual(changedSnapshot.latestEventSequence, .init(1))
        XCTAssertEqual(changedSnapshot.policy, changed)
        XCTAssertEqual(changedSnapshot.keepAliveReasons, [.sessionRouting])
    }

    func testSnapshotCodableRoundTripPreservesRuntimeAndDeviceDiagnostics() async throws {
        let adapter = try makeAdapter()
        let snapshot = try await adapter.snapshot()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AhaKeyRuntimeSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.permissions[.microphone], .notDetermined)
        XCTAssertEqual(decoded.devices.first?.capabilities, [.configurationV4, .usbConfiguration])
        XCTAssertEqual(decoded.devices.first?.sessionGeneration, .init(4))
        XCTAssertEqual(decoded.devices.first?.transportGeneration, .init(9))
        XCTAssertEqual(decoded.devices.first?.state.leverPosition, 1)
        XCTAssertEqual(decoded.devices.first?.state.activeTaskPictureSets, [2: 1])
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
                batteryLevel: 85,
                workMode: 2,
                lightMode: 1,
                leverPosition: 1,
                brightness: 35,
                firmwareVersion: "3.0",
                activeTaskPictureSets: [2: 1]
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
