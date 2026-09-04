import CryptoKit
import Foundation
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
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if released { return }
            await withCheckedContinuation { waiters.append($0) }
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
        }
    }

    func testSameDeviceFIFOKeepsQueuedBehindHead() {
        runTest { [self] in
            let agent = await makeReadyAgent()
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
            let agent = await makeReadyAgent()
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

    func testPictureDisconnectResumesZeroResendAcrossAgentReopen() {
        runTest { [self] in
            let agent = await makeReadyAgent(userSlotLimit: 64)
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

            let resumedAgent = await makeReadyAgent(storeDirectory: storeDir, userSlotLimit: 64)
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
            let agent = await makeReadyAgent()
            let client = EndpointClient(agent: agent)
            try await client.handshake()
            var executed: [String] = []
            var hooks = agent.executionTestHooks
            hooks?.stepExecutor = { step in
                executed.append(step.rawValue)
                return .success
            }
            hooks?.sealedObjectFingerprint = try baseFingerprint("live-mismatch")
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
            deviceHooks?.sealedObjectFingerprint = nil
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
            let agent = await makeReadyAgent()
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

    private func makeReadyAgent(
        storeDirectory: URL? = nil,
        userSlotLimit: Int = 64
    ) async -> AhaKeyAgent {
        let agent = makeAgent(storeDirectory: storeDirectory, userSlotLimit: userSlotLimit)
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.oledContext = .standard
        hooks?.configurationCharacteristics = .allPresent
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())
        return agent
    }

    private func simulatedDevice(id: String = "TEST-DEVICE") -> AhaKeyRuntimeDeviceSnapshot {
        AhaKeyRuntimeDeviceSnapshot(
            id: try! AhaKeyRuntimeDeviceID(id),
            displayName: "Test",
            protocolState: .currentReady,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: true
        )
    }

    private func statusPackage(
        device: String,
        seed: String = "base-object"
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
            baseObjectFingerprint: try baseFingerprint(seed),
            verifiedResources: []
        )
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
