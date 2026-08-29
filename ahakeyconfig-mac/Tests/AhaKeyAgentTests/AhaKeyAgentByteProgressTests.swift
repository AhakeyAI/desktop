import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class AhaKeyAgentByteProgressTests: XCTestCase {
    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-byte-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for agent in agents { agent.shutdown() }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    private func runTest(_ work: @escaping () async throws -> Void) {
        let finished = expectation(description: "byte-progress-test")
        Task {
            do { try await work() }
            catch { XCTFail("byte-progress test error: \(error)") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 45)
    }

    func testConfirmedChunksAppearOnSnapshotAndEventsAndSurviveResnapshot() {
        runTest { [self] in
            let agent = makeAgent()
            let package = try await startApply(agent)
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let stepA = try AhaKeyRuntimeStepIdentifier("resource:a")
            let stepB = try AhaKeyRuntimeStepIdentifier("resource:b")
            await MainActor.run {
                agent.beginByteProgressForTesting(operationID: package.operationID, totalBytes: 300)
                agent.noteConfirmedResourceChunkForTesting(
                    operationID: package.operationID, stepID: stepA, bytes: 100, now: now
                )
                agent.noteConfirmedResourceChunkForTesting(
                    operationID: package.operationID, stepID: stepB, bytes: 100, now: now.addingTimeInterval(0.3)
                )
            }
            let first = try await snapshotOperation(agent, id: package.operationID)
            XCTAssertEqual(first?.completedBytes, 200)
            XCTAssertEqual(first?.totalBytes, 300)
            XCTAssertEqual(first?.currentStepID, stepB)
            let replayed = try await eventBytes(agent, operationID: package.operationID)
            XCTAssertEqual(replayed.last, 200)
            let again = try await snapshotOperation(agent, id: package.operationID)
            XCTAssertEqual(again?.completedBytes, 200, "重取 snapshot 不得回到 0 或旧 operation")
            XCTAssertEqual(again?.id, package.operationID)
        }
    }

    func testThrottledChunksStillAdvanceSnapshotWithoutDuplicateEvents() {
        runTest { [self] in
            let agent = makeAgent()
            let package = try await startApply(agent)
            let now = Date(timeIntervalSince1970: 1_800_000_100)
            let step = try AhaKeyRuntimeStepIdentifier("resource:a")
            await MainActor.run {
                agent.beginByteProgressForTesting(operationID: package.operationID, totalBytes: 400)
                agent.noteConfirmedResourceChunkForTesting(
                    operationID: package.operationID, stepID: step, bytes: 50, now: now
                )
                agent.noteConfirmedResourceChunkForTesting(
                    operationID: package.operationID, stepID: step, bytes: 50, now: now.addingTimeInterval(0.05)
                )
            }
            let summary = try await snapshotOperation(agent, id: package.operationID)
            XCTAssertEqual(summary?.completedBytes, 100, "节流只限制发布，确认块仍必须进入权威 snapshot")
            let byteEvents = try await eventBytes(agent, operationID: package.operationID)
            XCTAssertEqual(byteEvents.filter { $0 == 50 }.count, 1)
            XCTAssertFalse(byteEvents.contains(100), "250ms 内第二块不得再发 event")
        }
    }

    private func makeAgent() -> AhaKeyAgent {
        let agent = AhaKeyAgent(
            socketPath: testRoot.appendingPathComponent("agent-\(UUID().uuidString.prefix(6)).sock").path,
            hookSocketURL: testRoot.appendingPathComponent("hook-\(UUID().uuidString.prefix(6)).sock"),
            enableRuntimeModules: false
        )
        let storeDir = testRoot.appendingPathComponent("store-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        agent.executionTestHooks = AhaKeyAgentExecutionTestHooks(storeDirectory: storeDir)
        agents.append(agent)
        return agent
    }

    private func startApply(_ agent: AhaKeyAgent) async throws -> AhaKeyConfigurationPackage {
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 8, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
        hooks?.stepExecutor = { _ in
            try? await Task.sleep(nanoseconds: 300_000_000)
            return .success
        }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(AhaKeyRuntimeDeviceSnapshot(
            id: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            displayName: "Test AhaKey",
            protocolState: .currentReady,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: true
        ))
        let emptySet = AhaKeyStudioTaskSetInput(assets: [
            AhaKeyStudioTaskAssetInput(state: .idle, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .working, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .waiting, framesPerSecond: 12),
            AhaKeyStudioTaskAssetInput(state: .done, framesPerSecond: 12),
        ])
        let mode = AhaKeyStudioModeInput(
            slot: 0,
            keys: [
                AhaKeyStudioKeyInput(
                    role: .approve,
                    action: .shortcut(try .init(modifiers: [], keyCode: 0x28)),
                    description: "Accept"
                ),
            ],
            oled: AhaKeyStudioOLEDInput(
                statusLine: "s", framesPerSecond: 12, taskSets: [emptySet, emptySet], activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove")],
                brightness: 35
            )
        )
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [mode])
        let package = try AhaKeyConfigurationPackage(
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(0),
            desiredConfiguration: assembled.configuration.canonicalData(),
            resources: []
        )
        let response = try await agent.handleRuntimeXPCRequest(.apply(package))
        guard case .operationAccepted = response else {
            throw NSError(domain: "byte-progress", code: 1)
        }
        return package
    }

    private func snapshotOperation(
        _ agent: AhaKeyAgent,
        id: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimeOperationSummary? {
        let response = try await agent.handleRuntimeXPCRequest(.snapshot)
        guard case .snapshot(let snapshot) = response else { return nil }
        return snapshot.operations.first { $0.id == id }
    }

    private func eventBytes(
        _ agent: AhaKeyAgent,
        operationID: AhaKeyRuntimeOperationID
    ) async throws -> [UInt64] {
        let response = try await agent.handleRuntimeXPCRequest(.events(after: .init(0)))
        guard case .eventReplay(.events(let events)) = response else { return [] }
        return events.compactMap { event in
            guard case .operationChanged(let summary) = event.payload,
                  summary.id == operationID else { return nil }
            return summary.completedBytes
        }
    }
}
