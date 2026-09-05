import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class AhaKeyAgentPageExecutionTests: XCTestCase {
    private final class EndpointClient: @unchecked Sendable {
        private let endpoint: AhaKeyRuntimeXPCSessionEndpoint

        init(agent: AhaKeyAgent) {
            endpoint = AhaKeyRuntimeXPCSessionEndpoint(
                serverHandshake: agent.runtimeServerHandshake
            ) { request in
                try await agent.handleRuntimeXPCRequest(request)
            }
        }

        func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
            let data = try JSONEncoder().encode(request)
            let response = try await endpoint.exchange(data)
            return try JSONDecoder().decode(AhaKeyRuntimeXPCResponse.self, from: response)
        }

        func handshake() async throws {
            let response = try await exchange(.handshake(.init(
                interfaceVersion: .current, clientBuildID: "c3b-page-exec"
            )))
            guard case .handshakeAccepted = response else {
                throw AhaKeyRuntimeXPCTransportError.invalidResponse
            }
        }
    }

    private actor StepGate {
        private var released = false
        private var entered = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if !entered {
                entered = true
                let pendingEntered = enteredWaiters
                enteredWaiters.removeAll()
                pendingEntered.forEach { $0.resume() }
            }
            if released { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { enteredWaiters.append($0) }
        }

        func release() {
            released = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("c3b-agent-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        agents.forEach { $0.shutdown() }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    func testHandshakeAdvertisesPageScopedSchema() {
        runTest { [self] in
            let agent = makeAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            let handshake = agent.runtimeServerHandshake
            XCTAssertTrue(
                handshake.supportedConfigurationSchemaVersions.contains(
                    AhaKeyConfigurationPackage.pageScopedSchemaVersion
                )
            )
            guard case .snapshot(let snapshot) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot 必须可读")
            }
            XCTAssertEqual(
                snapshot.supportedConfigurationSchemaVersions,
                handshake.supportedConfigurationSchemaVersions
            )
            XCTAssertEqual(
                handshake.supportedConfigurationSchemaVersions,
                AhaKeyConfigurationPackage.advertisedSchemaVersions
            )
        }
    }

    func testSameDeviceFIFOKeepsQueuedBehindHead() {
        runTest { [self] in
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            let gate = StepGate()
            var hooks = agent.executionTestHooks
            var executed: [String] = []
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                await gate.wait()
                return .success
            }
            agent.executionTestHooks = hooks

            let head = try statusPackage(device: "TEST-DEVICE", seed: "one")
            let queued = try statusPackage(device: "TEST-DEVICE", seed: "two")
            guard case .operationAccepted = try await client.exchange(.apply(head)) else {
                return XCTFail("head apply")
            }
            guard case .operationAccepted = try await client.exchange(.apply(queued)) else {
                return XCTFail("queued apply")
            }
            await waitUntil(agent, head.operationID, states: [.running, .paused, .resumablePartial])
            guard case .snapshot(let mid) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            XCTAssertEqual(mid.operations.first { $0.id == queued.operationID }?.state, .accepted)
            XCTAssertFalse(executed.contains { $0.hasPrefix("base:mode:") })
            await gate.release()
            await expectTerminal(agent, head.operationID, .completed)
            await expectTerminal(agent, queued.operationID, .completed)
        }
    }

    func testQueuedCancelRemovesWithoutWritesRunningCancelRefused() {
        runTest { [self] in
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            let queued = try statusPackage(device: "TEST-DEVICE", seed: "queued")
            let running = try statusPackage(device: "TEST-DEVICE", seed: "running")
            let gate = StepGate()
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { _ in
                await gate.wait()
                return .success
            }
            agent.executionTestHooks = hooks

            guard case .operationAccepted = try await client.exchange(.apply(running)) else {
                return XCTFail("running apply")
            }
            guard case .operationAccepted = try await client.exchange(.apply(queued)) else {
                return XCTFail("queued apply")
            }
            await waitUntil(agent, running.operationID, states: [.running])

            let refused = try await client.exchange(.requestCancellation(running.operationID))
            XCTAssertEqual(refused, .cancellation(.refused))
            guard case .snapshot(let mid) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            XCTAssertEqual(mid.operations.first { $0.id == running.operationID }?.state, .running)

            let removed = try await client.exchange(.requestCancellation(queued.operationID))
            XCTAssertEqual(removed, .cancellation(.requested))
            await gate.release()
            await expectTerminal(agent, running.operationID, .completed)
            await expectTerminal(agent, queued.operationID, .failedWithoutWrites)
        }
    }

    func testXPCAbandonAfterSixtySecondDisconnectReleasesHead() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let head = try statusPackage(device: "TEST-DEVICE", seed: "abandon-head")
            let queued = try statusPackage(device: "TEST-DEVICE", seed: "abandon-queued")
            guard case .operationAccepted = try await client.exchange(.apply(head)) else {
                return XCTFail("head apply")
            }
            await waitUntil(agent, head.operationID, states: [.paused, .resumablePartial])
            guard case .operationAccepted = try await client.exchange(.apply(queued)) else {
                return XCTFail("queued apply")
            }
            await agent.noteProductionDisconnectForTesting()
            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            await agent.simulateDeviceForTesting(
                simulatedDevice(protocolState: .disconnected, bluetoothConnected: false)
            )
            var disconnected = agent.executionTestHooks
            disconnected?.wallClock = { now }
            agent.executionTestHooks = disconnected
            guard case .abandon(let disposition) = try await client.exchange(.requestAbandon(head.operationID)) else {
                return XCTFail("abandon response")
            }
            XCTAssertEqual(disposition, .abandoned)
            await expectTerminal(agent, head.operationID, .failedWithoutWrites)

            var resumeHooks = agent.executionTestHooks
            resumeHooks?.isReady = true
            resumeHooks?.configurationCharacteristics = .allPresent
            resumeHooks?.stepExecutor = { _ in .success }
            agent.executionTestHooks = resumeHooks
            guard case .operationAccepted = try await client.exchange(.apply(queued)) else {
                return XCTFail("queued resume apply")
            }
            await expectTerminal(agent, queued.operationID, .completed)
        }
    }

    func testAbandonClockSurvivesAgentReopen() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "reopen-clock")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            await agent.closeRuntimeStoreForTesting()
            agent.shutdown()

            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            let reopened = try await makePreparedAgent(storeDirectory: storeDir)
            await reopened.simulateDeviceForTesting(
                simulatedDevice(protocolState: .disconnected, bluetoothConnected: false)
            )
            var reopenHooks = reopened.executionTestHooks
            reopenHooks?.wallClock = { now }
            reopened.executionTestHooks = reopenHooks
            let reopenClient = EndpointClient(agent: reopened)
            try await reopenClient.handshake()
            guard case .abandon(let disposition) = try await reopenClient.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("reopen abandon")
            }
            XCTAssertEqual(disposition, .abandoned)
            await expectTerminal(reopened, package.operationID, .failedWithoutWrites)
        }
    }

    func testFreshReopenDisconnectBeforeReadyMintsNewEpoch() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "reopen-new-epoch")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            await agent.closeRuntimeStoreForTesting()
            let firstLease: AhaKeyRuntimeAuthoritativeWriterLease
            do {
                let firstStore = try AhaKeyRuntimePersistentStore(
                    rootDirectory: storeDir,
                    acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
                )
                let stored = try await firstStore.disconnectEpoch(package.operationID)
                let firstEpoch = try XCTUnwrap(stored)
                firstLease = try XCTUnwrap(firstEpoch.identity.writerLease)
            }
            agent.shutdown()

            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            let reopened = makeAgent(storeDirectory: storeDir)
            await reopened.simulateDeviceForTesting(simulatedDevice())
            var reopenHooks = reopened.executionTestHooks
            reopenHooks?.isReady = false
            reopenHooks?.wallClock = { now }
            reopened.executionTestHooks = reopenHooks
            try await reopened.ensureWriterLeaseForTesting()
            let reopenedLease = try XCTUnwrap(reopened.cachedWriterLeaseForTesting())
            XCTAssertNotEqual(reopenedLease, firstLease)
            await reopened.noteProductionDisconnectForTesting()
            await reopened.simulateDeviceForTesting(
                simulatedDevice(protocolState: .disconnected, bluetoothConnected: false)
            )
            let reopenClient = EndpointClient(agent: reopened)
            try await reopenClient.handshake()
            guard case .abandon(let disposition) = try await reopenClient.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("reopen abandon")
            }
            XCTAssertEqual(disposition, .refused)
            await reopened.closeRuntimeStoreForTesting()
            let inspect = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let storedSecond = try await inspect.disconnectEpoch(package.operationID)
            let secondEpoch = try XCTUnwrap(storedSecond)
            XCTAssertEqual(secondEpoch.identity.writerLease, reopenedLease)
            XCTAssertEqual(secondEpoch.startedAt, now)
            let state = try await inspect.transaction(package.operationID)?.state
            XCTAssertTrue(state == .paused || state == .resumablePartial)
        }
    }

    func testFreshReopenConnectedWithoutLeaseRefusesOldEpochAbandon() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "connected-no-lease")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            await agent.closeRuntimeStoreForTesting()
            agent.shutdown()

            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            let reopened = makeAgent(storeDirectory: storeDir)
            var reopenHooks = reopened.executionTestHooks
            reopenHooks?.simulatedDevice = simulatedDevice(
                protocolState: .probing,
                bluetoothConnected: true
            )
            reopenHooks?.isReady = false
            reopenHooks?.wallClock = { now }
            reopened.executionTestHooks = reopenHooks
            XCTAssertNil(reopened.cachedWriterLeaseForTesting())
            let reopenClient = EndpointClient(agent: reopened)
            try await reopenClient.handshake()
            guard case .abandon(let disposition) = try await reopenClient.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("reopen abandon")
            }
            XCTAssertEqual(disposition, .refused)
            await reopened.closeRuntimeStoreForTesting()
            let inspect = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let remainingEpoch = try await inspect.disconnectEpoch(package.operationID)
            XCTAssertNotNil(remainingEpoch)
            let state = try await inspect.transaction(package.operationID)?.state
            XCTAssertTrue(state == .paused || state == .resumablePartial)
        }
    }

    func testProductionLeaseAllocationFailureStaysOfflineThenRetryConnectsWithSameLease() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "lease-fail-offline")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            await agent.closeRuntimeStoreForTesting()
            let firstEpoch: AhaKeyRuntimeDisconnectEpoch
            do {
                let firstStore = try AhaKeyRuntimePersistentStore(
                    rootDirectory: storeDir,
                    acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
                )
                let stored = try await firstStore.disconnectEpoch(package.operationID)
                firstEpoch = try XCTUnwrap(stored)
            }
            agent.shutdown()

            let reopened = makeAgent(storeDirectory: storeDir)
            var logs: [String] = []
            reopened.onLog = { logs.append($0) }
            var reopenHooks = reopened.executionTestHooks
            reopenHooks?.writerLeaseAllocationError = .databaseFailure("c3cr5-forced")
            reopenHooks?.bluetoothPoweredOnForConnect = true
            reopenHooks?.wallClock = { now }
            reopened.executionTestHooks = reopenHooks
            let connectBeforeFail = reopened.connectAutomaticallyCallCountForTesting()
            let allocateBeforeFail = reopened.writerLeaseAllocateCallCountForTesting()
            await reopened.prepareWriterLeaseThenConnectForTesting()
            XCTAssertEqual(reopened.connectAutomaticallyCallCountForTesting(), connectBeforeFail)
            XCTAssertEqual(reopened.writerLeaseAllocateCallCountForTesting(), allocateBeforeFail)
            XCTAssertNil(reopened.cachedWriterLeaseForTesting())
            XCTAssertTrue(logs.contains { $0.contains("writer lease 分配失败") })
            await reopened.closeRuntimeStoreForTesting()
            let afterFail: AhaKeyRuntimeDisconnectEpoch
            let failState: AhaKeyRuntimeOperationState?
            do {
                let inspect = try AhaKeyRuntimePersistentStore(
                    rootDirectory: storeDir,
                    acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
                )
                let stored = try await inspect.disconnectEpoch(package.operationID)
                afterFail = try XCTUnwrap(stored)
                failState = try await inspect.transaction(package.operationID)?.state
            }
            XCTAssertEqual(afterFail, firstEpoch)
            XCTAssertTrue(failState == .paused || failState == .resumablePartial)

            var retryHooks = reopened.executionTestHooks
            retryHooks?.writerLeaseAllocationError = nil
            retryHooks?.bluetoothPoweredOnForConnect = true
            reopened.executionTestHooks = retryHooks
            await reopened.prepareWriterLeaseThenConnectForTesting()
            let lease = try XCTUnwrap(reopened.cachedWriterLeaseForTesting())
            XCTAssertEqual(reopened.writerLeaseAllocateCallCountForTesting(), allocateBeforeFail + 1)
            XCTAssertEqual(reopened.connectAutomaticallyCallCountForTesting(), connectBeforeFail + 1)
            await reopened.prepareWriterLeaseThenConnectForTesting()
            XCTAssertEqual(reopened.cachedWriterLeaseForTesting(), lease)
            XCTAssertEqual(reopened.writerLeaseAllocateCallCountForTesting(), allocateBeforeFail + 1)
            XCTAssertEqual(reopened.connectAutomaticallyCallCountForTesting(), connectBeforeFail + 2)
        }
    }

    func testProductionLeaseConnectRechecksPoweredOnAfterAllocation() {
        runTest { [self] in
            let agent = makeAgent()
            let gate = StepGate()
            var hooks = agent.executionTestHooks
            hooks?.bluetoothPoweredOnForConnect = true
            hooks?.beforeWriterLeaseAllocation = { await gate.wait() }
            agent.executionTestHooks = hooks
            let connectBefore = agent.connectAutomaticallyCallCountForTesting()
            let task = Task { await agent.prepareWriterLeaseThenConnectForTesting() }
            await gate.waitUntilEntered()
            var flipped = agent.executionTestHooks
            flipped?.bluetoothPoweredOnForConnect = false
            agent.executionTestHooks = flipped
            await gate.release()
            await task.value
            XCTAssertNotNil(agent.cachedWriterLeaseForTesting())
            XCTAssertEqual(agent.writerLeaseAllocateCallCountForTesting(), 1)
            XCTAssertEqual(agent.connectAutomaticallyCallCountForTesting(), connectBefore)
        }
    }

    func testRetryablePauseWithoutDisconnectEventRefusesAbandon() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "no-epoch")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            await agent.simulateDeviceForTesting(
                simulatedDevice(protocolState: .disconnected, bluetoothConnected: false)
            )
            var later = agent.executionTestHooks
            later?.wallClock = { now }
            agent.executionTestHooks = later
            guard case .abandon(let disposition) = try await client.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("abandon response")
            }
            XCTAssertEqual(disposition, .refused)
            guard case .snapshot(let snapshot) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            let state = snapshot.operations.first { $0.id == package.operationID }?.state
            XCTAssertTrue(state == .paused || state == .resumablePartial)
        }
    }

    func testConnectedNotReadyRefusesAbandonAfterTrueDisconnectClock() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "not-ready")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            var notReady = agent.executionTestHooks
            notReady?.isReady = false
            notReady?.configurationCharacteristics = .init(peripheral: false, command: false, data: false)
            notReady?.wallClock = { now }
            agent.executionTestHooks = notReady
            guard case .abandon(let disposition) = try await client.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("abandon response")
            }
            XCTAssertEqual(disposition, .refused)
        }
    }

    func testReconnectClearsFrozenDisconnectBeforeAbandon() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "reconnect-cas")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            now = now.addingTimeInterval(AhaKeyRuntimeAbandonPolicy.requiredDisconnectedDuration)
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "n-plus-1", transportGeneration: 1)
            )
            try await agent.noteProductionReconnectForTesting()
            await agent.simulateDeviceForTesting(
                simulatedDevice(
                    transportGeneration: 1,
                    protocolState: .disconnected,
                    bluetoothConnected: false
                )
            )
            var later = agent.executionTestHooks
            later?.wallClock = { now }
            agent.executionTestHooks = later
            guard case .abandon(let disposition) = try await client.exchange(
                .requestAbandon(package.operationID)
            ) else {
                return XCTFail("abandon response")
            }
            XCTAssertEqual(disposition, .refused)
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let cleared = try await store.disconnectEpoch(package.operationID)
            XCTAssertNil(cleared)
            let state = try await store.transaction(package.operationID)?.state
            XCTAssertTrue(state == .paused || state == .resumablePartial)
        }
    }

    func testDelayedDisconnectMintAfterReconnectDoesNotRecreateOldEpoch() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "delayed-mint")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            await agent.noteProductionDisconnectForTesting()
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let minted = try await store.disconnectEpoch(package.operationID)
            let oldEpoch = try XCTUnwrap(minted)
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "n-plus-1", transportGeneration: 1)
            )
            try await agent.noteProductionReconnectForTesting()
            let afterReconnect = try await store.disconnectEpoch(package.operationID)
            XCTAssertNil(afterReconnect)
            now = now.addingTimeInterval(5)
            await agent.noteFrozenDisconnectForTesting(identity: oldEpoch.identity, at: oldEpoch.startedAt)
            let afterDelayedMint = try await store.disconnectEpoch(package.operationID)
            XCTAssertNil(afterDelayedMint)
        }
    }

    func testFrozenDisconnectWithoutLeaseDoesNotMint() {
        runTest { [self] in
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var hooks = agent.executionTestHooks
            hooks?.wallClock = { now }
            hooks?.stepExecutor = { _ in .retryableFailure }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE", seed: "nil-lease-freeze")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await waitUntil(agent, package.operationID, states: [.paused, .resumablePartial])
            let identity = AhaKeyRuntimeConnectionIdentity(
                deviceID: package.targetDeviceID,
                sessionGeneration: .init(0),
                transportGeneration: .init(0)
            )
            await agent.noteFrozenDisconnectForTesting(identity: identity, at: now)
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let epoch = try await store.disconnectEpoch(package.operationID)
            XCTAssertNil(epoch)
        }
    }

    func testPictureDisconnectResumesZeroResendAcrossAgentReopen() {
        runTest { [self] in
            let agent = try await makeReadyAgent(userSlotLimit: 64)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            let fixture = try picturePackage()
            try await ingest(agent, fixture)
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            var seen: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                seen.append(step.rawValue)
                if seen.count == 3 { return .retryableFailure }
                return .success
            }
            agent.executionTestHooks = hooks
            guard case .operationAccepted = try await client.exchange(.apply(fixture.package)) else {
                return XCTFail("picture apply")
            }
            let paused = await waitUntil(
                agent,
                fixture.package.operationID,
                states: [.resumablePartial, .paused]
            )
            XCTAssertEqual(paused, .resumablePartial)
            await agent.closeRuntimeStoreForTesting()
            let confirmed = try await confirmedSteps(storeDir, fixture.package.operationID)
            XCTAssertEqual(confirmed.count, 2)
            XCTAssertTrue(confirmed.allSatisfy { $0.rawValue.hasPrefix("page:chunk:") })
            agent.shutdown()

            let resumedAgent = try await makeReadyAgent(storeDirectory: storeDir, userSlotLimit: 64)
            var resumed: [String] = []
            var resumeHooks = resumedAgent.executionTestHooks
            resumeHooks?.stepExecutor = { step in
                resumed.append(step.rawValue)
                return .success
            }
            resumedAgent.executionTestHooks = resumeHooks
            let resumeClient = EndpointClient(agent: resumedAgent)
            try await resumeClient.handshake()
            guard case .operationAccepted = try await resumeClient.exchange(.apply(fixture.package)) else {
                return XCTFail("reopen apply must resume")
            }
            await expectTerminal(resumedAgent, fixture.package.operationID, .completed)
            XCTAssertFalse(resumed.contains { confirmed.map(\.rawValue).contains($0) })
            XCTAssertFalse(resumed.contains { $0.hasPrefix("base:mode:") })
            XCTAssertTrue(resumed.first?.hasPrefix("page:chunk:") == true)
        }
    }

    func testWrongDeviceAndCASRefuseBeforeAnyStep() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "live-mismatch")
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await expectTerminal(agent, package.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed, [])

            executed.removeAll()
            await agent.simulateDeviceForTesting(simulatedDevice(id: "OTHER-DEVICE"))
            var deviceHooks = agent.executionTestHooks
            deviceHooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            agent.executionTestHooks = deviceHooks
            let mismatched = try statusPackage(device: "TEST-DEVICE", seed: "device-mismatch")
            guard case .operationAccepted = try await client.exchange(.apply(mismatched)) else {
                return XCTFail("device mismatch apply")
            }
            await expectTerminal(agent, mismatched.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed, [])
        }
    }

    func testDeterministicRejectStopsAndKeepsMinimalConfirm() {
        runTest { [self] in
            let agent = try await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                if executed.count == 1 {
                    return .failure(.init(
                        retryable: false,
                        messageCode: .configurationDeviceRejected,
                        context: .init(failedStepID: step, opcode: 0x73, deviceStatus: 1)
                    ))
                }
                return .success
            }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await expectTerminal(agent, package.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed.count, 1)
        }
    }

    func testProductionLiveCASRefusesAfterAcceptAndAcrossReopen() {
        runTest { [self] in
            let agent = try await makeReadyAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let package = try statusPackage(device: "TEST-DEVICE")
            let sawBase = await waitUntilAuthoritativeObject(agent, Data("base-object".utf8))
            XCTAssertTrue(sawBase)
            await agent.closeRuntimeStoreForTesting()
            let confirmedBefore: [AhaKeyRuntimeStepIdentifier]
            do {
                let store = try AhaKeyRuntimePersistentStore(
                    rootDirectory: storeDir,
                    acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
                )
                _ = try await store.accept(package, resourceFiles: [:])
                confirmedBefore = try await store.confirmedSteps(for: package.operationID)
            }
            XCTAssertEqual(confirmedBefore, [])
            try await replaceLiveObject(
                storeDir: storeDir,
                content: Data("changed-after-accept".utf8),
                session: 1,
                transport: 1
            )
            agent.shutdown()

            var executed: [String] = []
            let resumed = try await makeReadyAgent(
                storeDirectory: storeDir
            )
            var resumeHooks = resumed.executionTestHooks
            resumeHooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            resumed.executionTestHooks = resumeHooks
            let resumeClient = EndpointClient(agent: resumed)
            try await resumeClient.handshake()
            guard case .operationAccepted = try await resumeClient.exchange(.apply(package)) else {
                return XCTFail("reopen apply")
            }
            await expectTerminal(resumed, package.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed, [])
            await resumed.closeRuntimeStoreForTesting()
            let confirmedAfter = try await confirmedSteps(storeDir, package.operationID)
            XCTAssertEqual(confirmedAfter, [])
        }
    }

    func testMissingLiveObjectFingerprintFailsClosed() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: nil)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            agent.executionTestHooks = hooks
            let package = try statusPackage(device: "TEST-DEVICE")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await expectTerminal(agent, package.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed, [])
        }
    }

    func testDeviceConfirmedResumeSurvivesMissingAndChangedAuthoritativeObject() {
        runTest { [self] in
            let agent = try await makeReadyAgent(userSlotLimit: 64)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            let fixture = try picturePackage()
            try await ingest(agent, fixture)
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            var seen: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                seen.append(step.rawValue)
                if seen.count == 3 { return .retryableFailure }
                return .success
            }
            agent.executionTestHooks = hooks
            guard case .operationAccepted = try await client.exchange(.apply(fixture.package)) else {
                return XCTFail("picture apply")
            }
            let paused = await waitUntil(
                agent,
                fixture.package.operationID,
                states: [.resumablePartial, .paused]
            )
            XCTAssertEqual(paused, .resumablePartial)
            await agent.closeRuntimeStoreForTesting()
            let confirmed = try await confirmedSteps(storeDir, fixture.package.operationID)
            XCTAssertEqual(confirmed.count, 2)
            XCTAssertTrue(confirmed.allSatisfy { $0.rawValue.hasPrefix("page:chunk:") })
            agent.shutdown()

            try deleteAuthoritativeObject(storeDir: storeDir, device: "TEST-DEVICE")
            let missingAgent = try await makeReadyAgent(
                storeDirectory: storeDir,
                userSlotLimit: 64,
                objectSeed: nil
            )
            var missingResumed: [String] = []
            var missingHooks = missingAgent.executionTestHooks
            missingHooks?.stepExecutor = { step in
                missingResumed.append(step.rawValue)
                return .success
            }
            missingAgent.executionTestHooks = missingHooks
            let missingClient = EndpointClient(agent: missingAgent)
            try await missingClient.handshake()
            guard case .operationAccepted = try await missingClient.exchange(.apply(fixture.package)) else {
                return XCTFail("missing CAS reopen must resume")
            }
            await expectTerminal(missingAgent, fixture.package.operationID, .completed)
            XCTAssertFalse(missingResumed.contains { confirmed.map(\.rawValue).contains($0) })
            await missingAgent.closeRuntimeStoreForTesting()
            missingAgent.shutdown()

            let changedFixture = try picturePackage()
            let changedAgent = try await makeReadyAgent(userSlotLimit: 64)
            let changedClient = EndpointClient(agent: changedAgent)
            try await changedClient.handshake()
            try await ingest(changedAgent, changedFixture)
            let changedDir = try XCTUnwrap(changedAgent.executionTestHooks?.storeDirectory)
            var changedSeen: [String] = []
            var changedHooks = changedAgent.executionTestHooks
            changedHooks?.stepExecutor = { step in
                changedSeen.append(step.rawValue)
                if changedSeen.count == 3 { return .retryableFailure }
                return .success
            }
            changedAgent.executionTestHooks = changedHooks
            guard case .operationAccepted = try await changedClient.exchange(.apply(changedFixture.package)) else {
                return XCTFail("changed CAS apply")
            }
            let changedPaused = await waitUntil(
                changedAgent,
                changedFixture.package.operationID,
                states: [.resumablePartial, .paused]
            )
            XCTAssertEqual(changedPaused, .resumablePartial)
            await changedAgent.closeRuntimeStoreForTesting()
            try await replaceLiveObject(
                storeDir: changedDir,
                content: Data("mutated-after-device-write".utf8),
                session: 1,
                transport: 1
            )
            changedAgent.shutdown()

            let resumedChanged = try await makeReadyAgent(
                storeDirectory: changedDir,
                userSlotLimit: 64
            )
            var changedResumed: [String] = []
            var resumeHooks = resumedChanged.executionTestHooks
            resumeHooks?.stepExecutor = { step in
                changedResumed.append(step.rawValue)
                return .success
            }
            resumedChanged.executionTestHooks = resumeHooks
            let resumeClient = EndpointClient(agent: resumedChanged)
            try await resumeClient.handshake()
            guard case .operationAccepted = try await resumeClient.exchange(.apply(changedFixture.package)) else {
                return XCTFail("changed CAS reopen must resume")
            }
            await expectTerminal(resumedChanged, changedFixture.package.operationID, .completed)
            XCTAssertFalse(changedResumed.isEmpty)
        }
    }

    func testDeviceChangedAuthoritativeObjectDrivesPagePreflight() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            agent.executionTestHooks = hooks

            let firstObject = Data("base-object".utf8)
            let sawFirst = await waitUntilAuthoritativeObject(agent, firstObject)
            XCTAssertTrue(sawFirst)
            let first = try statusPackage(device: "TEST-DEVICE", seed: "first")
            guard case .operationAccepted = try await client.exchange(.apply(first)) else {
                return XCTFail("matching deviceChanged apply")
            }
            await expectTerminal(agent, first.operationID, .completed)
            XCTAssertFalse(executed.isEmpty)

            executed.removeAll()
            await agent.closeRuntimeStoreForTesting()
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("generation-2".utf8)
            )
            await agent.simulateDeviceForTesting(
                simulatedDevice(transportGeneration: 1)
            )
            let sawGeneration = await waitUntilAuthoritativeObject(agent, Data("generation-2".utf8))
            XCTAssertTrue(sawGeneration)
            let stale = try statusPackage(device: "TEST-DEVICE", seed: "stale")
            guard case .operationAccepted = try await client.exchange(.apply(stale)) else {
                return XCTFail("stale fingerprint apply")
            }
            await expectTerminal(agent, stale.operationID, .failedWithoutWrites)
            XCTAssertEqual(executed, [])

            let next = try statusPackage(
                device: "TEST-DEVICE",
                seed: "next",
                objectSeed: "generation-2"
            )
            guard case .operationAccepted = try await client.exchange(.apply(next)) else {
                return XCTFail("generation apply")
            }
            await expectTerminal(agent, next.operationID, .completed)
            XCTAssertFalse(executed.isEmpty)

            await agent.closeRuntimeStoreForTesting()
            agent.shutdown()
            executed.removeAll()
            let reopened = try await makeReadyAgent(storeDirectory: storeDir, objectSeed: nil)
            var reopenHooks = reopened.executionTestHooks
            reopenHooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            reopened.executionTestHooks = reopenHooks
            let reopenClient = EndpointClient(agent: reopened)
            try await reopenClient.handshake()
            let sawReopen = await waitUntilAuthoritativeObject(reopened, Data("generation-2".utf8))
            XCTAssertTrue(sawReopen)
            let reopenMatch = try statusPackage(
                device: "TEST-DEVICE",
                seed: "reopen",
                objectSeed: "generation-2"
            )
            guard case .operationAccepted = try await reopenClient.exchange(.apply(reopenMatch)) else {
                return XCTFail("fresh Agent reopen apply")
            }
            await expectTerminal(reopened, reopenMatch.operationID, .completed)
            XCTAssertFalse(executed.isEmpty)
        }
    }

    func testDelayedAuthoritativeCommitDoesNotOverrideNewerGeneration() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let sawBase = await waitUntilAuthoritativeObject(agent, Data("base-object".utf8))
            XCTAssertTrue(sawBase)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "n"))
            await gate.waitUntilEntered()
            await agent.closeRuntimeStoreForTesting()
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("generation-2".utf8)
            )
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "n-plus-1", transportGeneration: 1)
            )
            let sawGeneration = await waitUntilAuthoritativeObject(agent, Data("generation-2".utf8))
            XCTAssertTrue(sawGeneration)
            await gate.release()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await agent.closeRuntimeStoreForTesting()
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let live = try await store.authoritativeObjectFingerprint(
                for: AhaKeyRuntimeDeviceID("TEST-DEVICE")
            )
            XCTAssertEqual(live, try AhaKeyRuntimeObjectFingerprint.hashing(Data("generation-2".utf8)))
        }
    }

    func testAuthoritativePersistFailureDoesNotPublishObject() {
        runTest { [self] in
            let agent = makeAgent()
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("base-object".utf8)
            )
            var hooks = agent.executionTestHooks
            hooks?.isReady = true
            hooks?.oledContext = .standard
            hooks?.configurationCharacteristics = .allPresent
            hooks?.failAuthoritativeObjectCommit = true
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice())
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard case .snapshot(let snapshot) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            XCTAssertNil(snapshot.devices.first?.authoritativeObject)
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var applyHooks = agent.executionTestHooks
            applyHooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            agent.executionTestHooks = applyHooks
            let package = try statusPackage(device: "TEST-DEVICE")
            guard case .operationAccepted = try await client.exchange(.apply(package)) else {
                return XCTFail("apply")
            }
            await expectTerminal(agent, package.operationID, .completed)
            XCTAssertFalse(executed.isEmpty)
        }
    }

    func testStaleAuthoritativeTaskDoesNotPublishOlderConnection() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let sawBase = await waitUntilAuthoritativeObject(
                agent,
                Data("base-object".utf8),
                transportGeneration: 0
            )
            XCTAssertTrue(sawBase)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "n"))
            await gate.waitUntilEntered()
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "n-plus-1", transportGeneration: 1)
            )
            let sawNext = await waitUntilAuthoritativeObject(
                agent,
                Data("base-object".utf8),
                transportGeneration: 1
            )
            XCTAssertTrue(sawNext)
            guard case .eventReplay(let beforeReplay) = try await agent.handleRuntimeXPCRequest(
                .events(after: .init(0))
            ),
            case .events(let beforeRelease) = beforeReplay else {
                return XCTFail("events")
            }
            let cursor = beforeRelease.last?.sequence ?? .init(0)
            await gate.release()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard case .eventReplay(let afterReplay) = try await agent.handleRuntimeXPCRequest(
                .events(after: cursor)
            ),
            case .events(let afterRelease) = afterReplay else {
                return XCTFail("tail events")
            }
            let staleAuthoritative = afterRelease.contains { event in
                if case .deviceChanged(let device) = event.payload {
                    return device.transportGeneration == .init(0)
                        && device.authoritativeObject != nil
                }
                return false
            }
            XCTAssertFalse(staleAuthoritative)
            guard case .snapshot(let snapshot) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            XCTAssertEqual(snapshot.devices.first?.transportGeneration, .init(1))
            XCTAssertEqual(snapshot.devices.first?.authoritativeObject, Data("base-object".utf8))
        }
    }

    func testSameGenerationSchema1ReplacementRejectsDelayedRollback() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "object-a")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let sawA = await waitUntilAuthoritativeObject(agent, Data("object-a".utf8))
            XCTAssertTrue(sawA)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "hold-a"))
            await gate.waitUntilEntered()
            await agent.closeRuntimeStoreForTesting()
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("object-b".utf8)
            )
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "commit-b"))
            let sawB = await waitUntilAuthoritativeObject(agent, Data("object-b".utf8))
            XCTAssertTrue(sawB)
            await gate.release()
            try? await Task.sleep(nanoseconds: 80_000_000)
            await agent.closeRuntimeStoreForTesting()
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let live = try await store.authoritativeObjectContent(
                for: AhaKeyRuntimeDeviceID("TEST-DEVICE")
            )
            XCTAssertEqual(live, Data("object-b".utf8))
        }
    }

    func testReconnectDoesNotAttachPreviousConnectionObjectBeforeCommit() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let sawBase = await waitUntilAuthoritativeObject(
                agent,
                Data("base-object".utf8),
                transportGeneration: 0
            )
            XCTAssertTrue(sawBase)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "reconnect", transportGeneration: 1)
            )
            await gate.waitUntilEntered()
            guard case .snapshot(let beforeCommit) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("snapshot")
            }
            XCTAssertEqual(beforeCommit.devices.first?.transportGeneration, .init(1))
            XCTAssertNil(beforeCommit.devices.first?.authoritativeObject)
            await gate.release()
            let sawReconnect = await waitUntilAuthoritativeObject(
                agent,
                Data("base-object".utf8),
                transportGeneration: 1
            )
            XCTAssertTrue(sawReconnect)

            var failHooks = agent.executionTestHooks
            failHooks?.beforeAuthoritativeObjectCommit = nil
            failHooks?.failAuthoritativeObjectCommit = true
            agent.executionTestHooks = failHooks
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "failed-reconnect", transportGeneration: 2)
            )
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard case .snapshot(let failed) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("failed snapshot")
            }
            XCTAssertEqual(failed.devices.first?.transportGeneration, .init(2))
            XCTAssertNil(failed.devices.first?.authoritativeObject)
        }
    }

    func testDelayedForeignDeviceTaskDoesNotPublish() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let sawOriginal = await waitUntilAuthoritativeObject(agent, Data("base-object".utf8))
            XCTAssertTrue(sawOriginal)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "original"))
            await gate.waitUntilEntered()
            await agent.simulateDeviceForTesting(simulatedDevice(id: "OTHER-DEVICE", displayName: "other"))
            guard case .snapshot(let other) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("other snapshot")
            }
            XCTAssertEqual(other.devices.first?.id, try AhaKeyRuntimeDeviceID("OTHER-DEVICE"))
            XCTAssertNil(other.devices.first?.authoritativeObject)
            await gate.release()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard case .snapshot(let stillOther) = try await agent.handleRuntimeXPCRequest(.snapshot) else {
                return XCTFail("post-release snapshot")
            }
            XCTAssertEqual(stillOther.devices.first?.id, try AhaKeyRuntimeDeviceID("OTHER-DEVICE"))
            XCTAssertNil(stillOther.devices.first?.authoritativeObject)
        }
    }

    func testFreshAgentRestartAcceptsLowerGeneration() {
        runTest { [self] in
            let agent = try await makeReadyAgent(objectSeed: "base-object")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let sawBase = await waitUntilAuthoritativeObject(agent, Data("base-object".utf8))
            XCTAssertTrue(sawBase)
            await agent.closeRuntimeStoreForTesting()
            try await replaceLiveObject(
                storeDir: storeDir,
                content: Data("base-object".utf8),
                session: 9,
                transport: 9
            )
            agent.shutdown()
            let restarted = try await makeReadyAgent(storeDirectory: storeDir)
            await restarted.simulateDeviceForTesting(simulatedDevice())
            let sawRestart = await waitUntilAuthoritativeObject(
                restarted,
                Data("base-object".utf8),
                sessionGeneration: 0,
                transportGeneration: 0
            )
            XCTAssertTrue(sawRestart)
        }
    }

    func testFreshFirstCommitDelayedTaskDoesNotRollbackCAS() {
        runTest { [self] in
            let agent = try await makePreparedAgent(objectSeed: "object-n")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "n"))
            await gate.waitUntilEntered()
            await agent.closeRuntimeStoreForTesting()
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("object-n-plus-1".utf8)
            )
            await agent.simulateDeviceForTesting(
                simulatedDevice(displayName: "n-plus-1", transportGeneration: 1)
            )
            let sawNext = await waitUntilAuthoritativeObject(
                agent,
                Data("object-n-plus-1".utf8),
                transportGeneration: 1
            )
            XCTAssertTrue(sawNext)
            guard case .eventReplay(let beforeReplay) = try await agent.handleRuntimeXPCRequest(
                .events(after: .init(0))
            ),
            case .events(let beforeRelease) = beforeReplay else {
                return XCTFail("events")
            }
            let cursor = beforeRelease.last?.sequence ?? .init(0)
            await gate.release()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard case .eventReplay(let afterReplay) = try await agent.handleRuntimeXPCRequest(
                .events(after: cursor)
            ),
            case .events(let afterRelease) = afterReplay else {
                return XCTFail("tail events")
            }
            let staleAuthoritative = afterRelease.contains { event in
                if case .deviceChanged(let device) = event.payload {
                    return device.transportGeneration == .init(0)
                        && device.authoritativeObject != nil
                }
                return false
            }
            XCTAssertFalse(staleAuthoritative)
            await agent.closeRuntimeStoreForTesting()
            let live = try await liveAuthoritativeObject(storeDir: storeDir)
            XCTAssertEqual(live, Data("object-n-plus-1".utf8))
        }
    }

    func testFreshSameGenerationSchema1ReplacementRejectsDelayedRollback() {
        runTest { [self] in
            let agent = try await makePreparedAgent(objectSeed: "object-a")
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            let gate = StepGate()
            var delayOnce = true
            var hooks = agent.executionTestHooks
            hooks?.beforeAuthoritativeObjectCommit = {
                if delayOnce {
                    delayOnce = false
                    await gate.wait()
                }
            }
            agent.executionTestHooks = hooks
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "hold-a"))
            await gate.waitUntilEntered()
            await agent.closeRuntimeStoreForTesting()
            try await seedAuthoritativeBaseline(
                storeDir: storeDir,
                content: Data("object-b".utf8)
            )
            await agent.simulateDeviceForTesting(simulatedDevice(displayName: "commit-b"))
            let sawB = await waitUntilAuthoritativeObject(agent, Data("object-b".utf8))
            XCTAssertTrue(sawB)
            await gate.release()
            try? await Task.sleep(nanoseconds: 80_000_000)
            await agent.closeRuntimeStoreForTesting()
            let live = try await liveAuthoritativeObject(storeDir: storeDir)
            XCTAssertEqual(live, Data("object-b".utf8))
        }
    }

    func testFreshAgentTakesOverLowThenHighHistoricalLeaseDevices() {
        runTest { [self] in
            let storeDir = testRoot.appendingPathComponent(
                "store-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            let content = Data("shared-object".utf8)
            let historicalA = try await seedProjectedObject(
                storeDir: storeDir,
                device: "DEVICE-A",
                content: content
            )
            let historicalB = try await seedProjectedObject(
                storeDir: storeDir,
                device: "DEVICE-B",
                content: content
            )
            XCTAssertGreaterThan(historicalB, historicalA)
            let agent = try await makePreparedAgent(storeDirectory: storeDir, objectSeed: nil)
            await agent.simulateDeviceForTesting(simulatedDevice(id: "DEVICE-A"))
            let sawA = await waitUntilAuthoritativeObject(agent, content)
            XCTAssertTrue(sawA)
            await agent.simulateDeviceForTesting(simulatedDevice(id: "DEVICE-B"))
            let sawB = await waitUntilAuthoritativeObject(agent, content)
            XCTAssertTrue(sawB)
            await agent.closeRuntimeStoreForTesting()
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            let versionA = try await store.authoritativeVersion(for: AhaKeyRuntimeDeviceID("DEVICE-A"))
            let versionB = try await store.authoritativeVersion(for: AhaKeyRuntimeDeviceID("DEVICE-B"))
            let leaseA = try XCTUnwrap(versionA?.writerLease)
            let leaseB = try XCTUnwrap(versionB?.writerLease)
            XCTAssertEqual(leaseA, leaseB)
            XCTAssertGreaterThan(leaseA, historicalB)
        }
    }

    func testFreshReopenTakesOverMultiDeviceHighGenerationHistory() {
        runTest { [self] in
            let storeDir = testRoot.appendingPathComponent(
                "store-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            let contentA = Data("device-a-object".utf8)
            let contentB = Data("device-b-object".utf8)
            let historicalA = try await seedProjectedObject(
                storeDir: storeDir,
                device: "DEVICE-A",
                content: contentA,
                session: 9,
                transport: 9
            )
            _ = try await seedProjectedObject(
                storeDir: storeDir,
                device: "DEVICE-B",
                content: contentB,
                session: 8,
                transport: 8
            )
            let agent = try await makePreparedAgent(storeDirectory: storeDir, objectSeed: nil)
            await agent.simulateDeviceForTesting(simulatedDevice(id: "DEVICE-A"))
            let sawA = await waitUntilAuthoritativeObject(
                agent,
                contentA,
                sessionGeneration: 0,
                transportGeneration: 0
            )
            XCTAssertTrue(sawA)
            await agent.simulateDeviceForTesting(simulatedDevice(id: "DEVICE-B"))
            let sawB = await waitUntilAuthoritativeObject(
                agent,
                contentB,
                sessionGeneration: 0,
                transportGeneration: 0
            )
            XCTAssertTrue(sawB)
            await agent.closeRuntimeStoreForTesting()
            let store = try AhaKeyRuntimePersistentStore(
                rootDirectory: storeDir,
                acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
            )
            do {
                try await store.persistProjectedAuthoritativeObject(
                    contentA,
                    version: AhaKeyRuntimeAuthoritativeVersion(
                        deviceID: try AhaKeyRuntimeDeviceID("DEVICE-A"),
                        writerLease: historicalA,
                        sessionGeneration: .init(9),
                        transportGeneration: .init(9),
                        sourceRevision: .first,
                        sourceDigest: try AhaKeyRuntimeObjectFingerprint.hashing(contentA)
                    )
                )
                XCTFail("old lease must fail-closed after fresh reopen")
            } catch {
                XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .staleAuthoritativeGeneration)
            }
            let liveA = try await store.authoritativeObjectContent(
                for: AhaKeyRuntimeDeviceID("DEVICE-A")
            )
            let liveB = try await store.authoritativeObjectContent(
                for: AhaKeyRuntimeDeviceID("DEVICE-B")
            )
            XCTAssertEqual(liveA, contentA)
            XCTAssertEqual(liveB, contentB)
        }
    }

    // MARK: - helpers

    private func runTest(_ work: @escaping () async throws -> Void) {
        let finished = expectation(description: "c3b-agent")
        Task {
            do { try await work() }
            catch { XCTFail("agent page execution error: \(error)") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 120)
    }

    private func makeAgent(
        storeDirectory: URL? = nil,
        userSlotLimit: Int = 64
    ) -> AhaKeyAgent {
        let agent = AhaKeyAgent(
            socketPath: testRoot.appendingPathComponent("agent-\(UUID().uuidString.prefix(6)).sock").path,
            hookSocketURL: testRoot.appendingPathComponent("hook-\(UUID().uuidString.prefix(6)).sock"),
            enableRuntimeModules: false
        )
        let storeDir = storeDirectory ?? testRoot.appendingPathComponent(
            "store-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        agent.executionTestHooks = AhaKeyAgentExecutionTestHooks(storeDirectory: storeDir)
        agents.append(agent)
        return agent
    }

    private func makePreparedAgent(
        storeDirectory: URL? = nil,
        userSlotLimit: Int = 64,
        objectSeed: String? = "base-object"
    ) async throws -> AhaKeyAgent {
        let agent = makeAgent(storeDirectory: storeDirectory, userSlotLimit: userSlotLimit)
        if storeDirectory == nil, let objectSeed {
            let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
            try await seedAuthoritativeBaseline(storeDir: storeDir, content: Data(objectSeed.utf8))
        }
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.oledContext = .standard
        hooks?.configurationCharacteristics = .allPresent
        agent.executionTestHooks = hooks
        try await agent.ensureWriterLeaseForTesting()
        return agent
    }

    private func makeReadyAgent(
        storeDirectory: URL? = nil,
        userSlotLimit: Int = 64,
        objectSeed: String? = "base-object"
    ) async throws -> AhaKeyAgent {
        let agent = try await makePreparedAgent(
            storeDirectory: storeDirectory,
            userSlotLimit: userSlotLimit,
            objectSeed: objectSeed
        )
        await agent.simulateDeviceForTesting(simulatedDevice())
        return agent
    }

    private func simulatedDevice(
        id: String = "TEST-DEVICE",
        displayName: String = "Test",
        sessionGeneration: UInt64 = 0,
        transportGeneration: UInt64 = 0,
        protocolState: AhaKeyRuntimeDeviceProtocolState = .currentReady,
        bluetoothConnected: Bool = true
    ) -> AhaKeyRuntimeDeviceSnapshot {
        AhaKeyRuntimeDeviceSnapshot(
            id: try! AhaKeyRuntimeDeviceID(id),
            displayName: displayName,
            protocolState: protocolState,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: bluetoothConnected,
            sessionGeneration: .init(sessionGeneration),
            transportGeneration: .init(transportGeneration)
        )
    }

    private func seedAuthoritativeBaseline(
        storeDir: URL,
        content: Data,
        device: String = "TEST-DEVICE"
    ) async throws {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir
        )
        let deviceID = try AhaKeyRuntimeDeviceID(device)
        let current = try await store.syncBaseline(for: deviceID)
        let baseRevision = current?.revision.rawValue ?? 7
        let package = try AhaKeyConfigurationPackage(
            operationID: .init(),
            targetDeviceID: deviceID,
            baseRevision: .init(baseRevision),
            desiredConfiguration: content,
            resources: []
        )
        _ = try await store.accept(package, resourceFiles: [:])
        try await store.updateOperation(
            .init(
                id: package.operationID,
                targetDeviceID: package.targetDeviceID,
                state: .running,
                completedSteps: 1,
                totalSteps: 1
            )
        )
        try await store.commitOperationOutcome(
            .init(
                id: package.operationID,
                targetDeviceID: package.targetDeviceID,
                state: .completed,
                completedSteps: 1,
                totalSteps: 1
            ),
            syncBaseline: try .init(
                deviceID: package.targetDeviceID,
                revision: .init(baseRevision + 1),
                confirmedConfiguration: content
            )
        )
    }

    private func replaceLiveObject(
        storeDir: URL,
        content: Data,
        device: String = "TEST-DEVICE",
        session: UInt64,
        transport: UInt64
    ) async throws {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        let deviceID = try AhaKeyRuntimeDeviceID(device)
        let existing = try await store.authoritativeVersion(for: deviceID)
        let lease: AhaKeyRuntimeAuthoritativeWriterLease
        if let existingLease = existing?.writerLease {
            lease = existingLease
        } else {
            lease = try await store.allocateAuthoritativeWriterLease()
        }
        let revision = try existing?.sourceRevision.advanced() ?? .first
        try await store.persistProjectedAuthoritativeObject(
            content,
            version: AhaKeyRuntimeAuthoritativeVersion(
                deviceID: deviceID,
                writerLease: lease,
                sessionGeneration: .init(session),
                transportGeneration: .init(transport),
                sourceRevision: revision,
                sourceDigest: try AhaKeyRuntimeObjectFingerprint.hashing(content)
            )
        )
    }

    private func seedProjectedObject(
        storeDir: URL,
        device: String,
        content: Data,
        session: UInt64 = 0,
        transport: UInt64 = 0,
        revision: UInt64 = 1
    ) async throws -> AhaKeyRuntimeAuthoritativeWriterLease {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        let deviceID = try AhaKeyRuntimeDeviceID(device)
        let lease = try await store.allocateAuthoritativeWriterLease()
        try await store.persistProjectedAuthoritativeObject(
            content,
            version: AhaKeyRuntimeAuthoritativeVersion(
                deviceID: deviceID,
                writerLease: lease,
                sessionGeneration: .init(session),
                transportGeneration: .init(transport),
                sourceRevision: try AhaKeyRuntimeAuthoritativeSourceRevision(revision),
                sourceDigest: try AhaKeyRuntimeObjectFingerprint.hashing(content)
            )
        )
        return lease
    }

    private func liveAuthoritativeObject(
        storeDir: URL,
        device: String = "TEST-DEVICE"
    ) async throws -> Data? {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        return try await store.authoritativeObjectContent(for: AhaKeyRuntimeDeviceID(device))
    }

    private func waitUntilAuthoritativeObject(
        _ agent: AhaKeyAgent,
        _ expected: Data,
        sessionGeneration: UInt64? = nil,
        transportGeneration: UInt64? = nil,
        timeout: TimeInterval = 8
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .snapshot(let snapshot) = try? await agent.handleRuntimeXPCRequest(.snapshot),
               let device = snapshot.devices.first,
               device.authoritativeObject == expected {
                let sessionOK = sessionGeneration.map { device.sessionGeneration == .init($0) } ?? true
                let transportOK = transportGeneration.map { device.transportGeneration == .init($0) } ?? true
                if sessionOK && transportOK {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func statusPackage(
        device: String,
        seed: String = "status-text",
        objectSeed: String = "base-object"
    ) throws -> AhaKeyConfigurationPackage {
        let field = AhaKeyStudioFieldID.screenStatusLine(modeSlot: 0)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [field: .text(seed)],
            overwriteSemantic: false,
            writeTaskSetA: false,
            writeTaskSetB: false,
            activateTaskSet: nil,
            emitsSetActiveSetOpcode: false,
            statusLine: seed
        )
        return try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID(device),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(objectSeed),
            verifiedResources: []
        )
    }

    private func deleteAuthoritativeObject(storeDir: URL, device: String) throws {
        try mutateMetadata(
            storeDir: storeDir,
            sql: "DELETE FROM runtime_metadata WHERE key = ?",
            key: "authoritative-object:\(device)"
        )
    }

    private func mutateMetadata(storeDir: URL, sql: String, key: String) throws {
        let databaseURL = storeDir.appendingPathComponent("runtime.sqlite3")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        key.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private struct PictureApply {
        var package: AhaKeyConfigurationPackage
        var bytes: [AhaKeyResourceIdentifier: Data]
        var resources: [AhaKeyConfigurationResource]
    }

    private func picturePackage() throws -> PictureApply {
        let bytes = Data("gif-agent".utf8)
        let identifier = AhaKeyStudioPackageAssembler.taskAssetIdentifier(
            mode: 0,
            set: 0,
            state: .working
        )
        let digest = SHA256.hash(data: bytes)
        let resource = try AhaKeyConfigurationResource(
            logicalIdentifier: identifier,
            sha256: digest.map { String(format: "%02x", $0) }.joined(),
            byteCount: UInt64(bytes.count),
            mediaType: "image/gif"
        )
        let field = AhaKeyStudioFieldID.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .working)
        let plan = AhaKeyStudioScopedWritePlan(
            pageID: .screen(modeSlot: 0),
            fieldMask: [field],
            values: [
                field: .asset(
                    path: nil,
                    framesPerSecond: 10,
                    declaredFrameCount: 2,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ],
            overwriteSemantic: false,
            writeTaskSetA: true,
            writeTaskSetB: false,
            activateTaskSet: 0,
            emitsSetActiveSetOpcode: false,
            resources: [
                AhaKeyStudioResourceInput(
                    logicalIdentifier: resource.logicalIdentifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(identifier).gif"),
                    declaredFrameCount: 2,
                    pixelWidth: 160,
                    pixelHeight: 80
                ),
            ]
        )
        let package = try AhaKeyConfigurationPackage.assemblePageScoped(
            plan: plan,
            profile: .legacyStandard,
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(1),
            baseObjectFingerprint: try baseFingerprint(),
            verifiedResources: [resource]
        )
        return PictureApply(
            package: package,
            bytes: [resource.logicalIdentifier: bytes],
            resources: [resource]
        )
    }

    private func ingest(_ agent: AhaKeyAgent, _ fixture: PictureApply) async throws {
        let items = fixture.resources.map { resource in
            AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: resource.logicalIdentifier,
                sha256: resource.sha256,
                byteCount: resource.byteCount,
                data: fixture.bytes[resource.logicalIdentifier]!
            )
        }
        let response = try await agent.handleRuntimeXPCRequest(.ingestResources(items))
        guard case .resourcesIngested = response else {
            XCTFail("ingest failed: \(response)")
            return
        }
    }

    private func transaction(
        _ agent: AhaKeyAgent,
        _ operationID: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimePersistedTransaction? {
        let storeDir = try XCTUnwrap(agent.executionTestHooks?.storeDirectory)
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        return try await store.transaction(operationID)
    }

    private func confirmedSteps(
        _ storeDir: URL,
        _ operationID: AhaKeyRuntimeOperationID
    ) async throws -> [AhaKeyRuntimeStepIdentifier] {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDir,
            acceptanceValidator: AhaKeyRuntimeSchemaAwareAcceptanceValidator()
        )
        return try await store.confirmedSteps(for: operationID)
    }

    @discardableResult
    private func waitUntil(
        _ agent: AhaKeyAgent,
        _ operationID: AhaKeyRuntimeOperationID,
        states: Set<AhaKeyRuntimeOperationState>,
        timeout: TimeInterval = 8
    ) async -> AhaKeyRuntimeOperationState? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .snapshot(let snapshot) = try? await agent.handleRuntimeXPCRequest(.snapshot),
               let state = snapshot.operations.first(where: { $0.id == operationID })?.state,
               states.contains(state) {
                return state
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func expectTerminal(
        _ agent: AhaKeyAgent,
        _ operationID: AhaKeyRuntimeOperationID,
        _ expected: AhaKeyRuntimeOperationState,
        timeout: TimeInterval = 15
    ) async {
        let state = await waitTerminal(agent, operationID, timeout: timeout)
        XCTAssertEqual(state, expected)
    }

    private func waitTerminal(
        _ agent: AhaKeyAgent,
        _ operationID: AhaKeyRuntimeOperationID,
        timeout: TimeInterval = 15
    ) async -> AhaKeyRuntimeOperationState? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .snapshot(let snapshot) = try? await agent.handleRuntimeXPCRequest(.snapshot),
               let state = snapshot.operations.first(where: { $0.id == operationID })?.state,
               state.isTerminal {
                return state
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    private func baseFingerprint(_ seed: String = "base-object") throws -> AhaKeyRuntimeObjectFingerprint {
        try AhaKeyRuntimeObjectFingerprint.hashing(Data(seed.utf8))
    }
}
