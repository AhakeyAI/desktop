import CryptoKit
import ImageIO
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

    func testProductionAckChainAdvancesSnapshotAndEventsAndSurvivesResnapshot() async throws {
        let agent = makeAgent(skipBLE: true)
        let package = try await startResourceApply(agent)
        try await waitUntil {
            let summary = try await self.snapshotOperation(agent, id: package.operationID)
            return summary?.state.isTerminal == true || summary?.completedBytes == summary?.totalBytes
        }
        let first = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertGreaterThan(first?.completedBytes ?? 0, 0)
        XCTAssertEqual(first?.totalBytes, 3 * 25_600)
        XCTAssertNotNil(first?.currentStepID)
        let replayed = try await operationSummaries(agent, operationID: package.operationID)
        XCTAssertEqual(replayed.last?.completedBytes, first?.completedBytes)
        let again = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(again?.completedBytes, first?.completedBytes, "重取 snapshot 不得回到 0 或旧 operation")
        XCTAssertEqual(again?.id, package.operationID)
    }

    func testThrottledChunksStillAdvanceSnapshotWithoutDuplicateEvents() async throws {
        let agent = makeAgent(skipBLE: true)
        let ticks = FrozenTick(1_000_000_000)
        var hooks = agent.executionTestHooks
        hooks?.progressMonotonicNanos = { ticks.value }
        hooks?.failConfigurationWriteAfterAckCount = 3
        hooks?.failConfigurationChunkWith = .deviceRejected
        agent.executionTestHooks = hooks
        let package = try await startResourceApply(agent)
        try await waitUntil {
            (try await self.snapshotOperation(agent, id: package.operationID))?.state.isTerminal == true
        }
        let summary = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(summary?.completedBytes, 12_288, "节流只限制发布，确认块仍必须进入权威 snapshot")
        XCTAssertEqual(summary?.state, .failedWithoutWrites)
        let summaries = try await operationSummaries(agent, operationID: package.operationID)
        let running = summaries.filter { $0.state == .running }
        XCTAssertLessThanOrEqual(
            running.count, 1,
            "冻结 tick 时 250ms 内 running operationChanged 必须共享门控（含 step-end），实际 \(running.map(\.completedSteps))"
        )
        let runningBytes = summaries
            .filter { !$0.state.isTerminal }
            .compactMap(\.completedBytes)
        let distinctPositive = Set(runningBytes.filter { $0 > 0 })
        XCTAssertLessThanOrEqual(
            distinctPositive.count, 1,
            "冻结单调时钟时运行中不得把窗口内每一块都发成独立 event"
        )
        XCTAssertFalse(
            runningBytes.contains(4096) && runningBytes.contains(8192),
            "250ms 内中间块不得再发 event"
        )
    }

    func testIdenticalSummariesAreNotRepublishedOnStepEnd() async throws {
        let agent = makeAgent(skipBLE: true)
        let package = try await startResourceApply(agent)
        try await waitUntil {
            (try await self.snapshotOperation(agent, id: package.operationID))?.state.isTerminal == true
        }
        let summaries = try await operationSummaries(agent, operationID: package.operationID)
        XCTAssertGreaterThan(summaries.count, 1)
        for index in 1..<summaries.count {
            XCTAssertNotEqual(
                summaries[index], summaries[index - 1],
                "相同 summary 不得重复发 operationChanged"
            )
        }
    }

    func testEnteringNextResourceStepSwitchesCurrentStepBeforeFirstAck() async throws {
        let agent = makeAgent(skipBLE: true)
        let probe = StepProbe()
        let package = try await prepareResourcePackage(agent)
        await probe.setOperationID(package.operationID)
        var hooks = agent.executionTestHooks
        hooks?.afterEnteringConfigurationStep = { step in
            guard step.rawValue.hasPrefix("resource:") else { return }
            let count = await probe.appendResourceStep(step)
            guard count == 2 else { return }
            if let summary = try? await self.snapshotOperation(agent, id: package.operationID) {
                await probe.setSecondEnter(summary)
            }
        }
        agent.executionTestHooks = hooks
        try await applyPrepared(agent, package: package)
        try await waitUntil { await probe.secondEnter != nil }
        let entered = await probe.secondEnter
        let expectedStep = await probe.secondResourceStep()
        XCTAssertEqual(entered?.currentStepID, expectedStep)
        XCTAssertEqual(entered?.completedBytes, 25_600)
    }

    func testFailureDoesNotAdvancePastLastAckAndPublishesTerminalImmediately() async throws {
        let agent = makeAgent(skipBLE: true)
        let ticks = FrozenTick(1_000_000_000)
        var hooks = agent.executionTestHooks
        hooks?.progressMonotonicNanos = { ticks.value }
        hooks?.failConfigurationWriteAfterAckCount = 2
        hooks?.failConfigurationChunkWith = .deviceRejected
        agent.executionTestHooks = hooks
        let package = try await startResourceApply(agent)
        try await waitUntil {
            (try await self.snapshotOperation(agent, id: package.operationID))?.state.isTerminal == true
        }
        let summary = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(summary?.completedBytes, 8192)
        XCTAssertEqual(summary?.state, .failedWithoutWrites)
        let last = try await operationSummaries(agent, operationID: package.operationID).last
        XCTAssertEqual(last?.state, .failedWithoutWrites)
        XCTAssertEqual(last?.completedBytes, 8192)
    }

    func testCancelAfterFirstResourceDoesNotAdvanceIntoNextResourceBytes() async throws {
        let agent = makeAgent(skipBLE: true)
        let probe = StepProbe()
        let package = try await prepareResourcePackage(agent)
        await probe.setOperationID(package.operationID)
        var hooks = agent.executionTestHooks
        hooks?.afterEnteringConfigurationStep = { step in
            guard step.rawValue.hasPrefix("resource:") else { return }
            let count = await probe.appendResourceStep(step)
            guard count == 2 else { return }
            _ = try? await agent.handleRuntimeXPCRequest(.requestCancellation(package.operationID))
            if let summary = try? await self.snapshotOperation(agent, id: package.operationID) {
                await probe.setSecondEnter(summary)
            }
        }
        agent.executionTestHooks = hooks
        try await applyPrepared(agent, package: package)
        try await waitUntil {
            let state = try await self.snapshotOperation(agent, id: package.operationID)?.state
            return state == .resumablePartial || state == .failedWithoutWrites || state == .paused
        }
        let summary = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(summary?.completedBytes, 25_600)
        XCTAssertLessThanOrEqual(summary?.completedBytes ?? .max, 25_600)
        let states = try await operationSummaries(agent, operationID: package.operationID).map(\.state)
        XCTAssertTrue(
            states.contains(.cancellationRequested),
            "真实 requestCancellation 必须发布 cancellationRequested，实际 \(states)"
        )
        XCTAssertTrue(
            states.contains(.resumablePartial) || states.contains(.failedWithoutWrites) || states.contains(.paused),
            "取消后必须进入结算态，实际 \(states)"
        )
        XCTAssertNotEqual(summary?.state, .running)
        XCTAssertNotEqual(summary?.state, .accepted)
    }

    func testDisconnectReconnectKeepsSameProcessSnapshotFromRollingBack() async throws {
        let agent = makeAgent(skipBLE: true)
        var hooks = agent.executionTestHooks
        hooks?.failConfigurationWriteAfterAckCount = 2
        hooks?.failConfigurationChunkWith = .disconnected
        agent.executionTestHooks = hooks
        let package = try await startResourceApply(agent)
        try await waitUntil {
            (try await self.snapshotOperation(agent, id: package.operationID))?.completedBytes ?? 0 >= 8192
        }
        let mid = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(mid?.completedBytes, 8192)
        var disconnected = agent.executionTestHooks
        disconnected?.isReady = false
        agent.executionTestHooks = disconnected
        let whileDown = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(whileDown?.completedBytes, 8192)
        XCTAssertEqual(whileDown?.id, package.operationID)
        var reconnected = agent.executionTestHooks
        reconnected?.isReady = true
        agent.executionTestHooks = reconnected
        let again = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(again?.id, package.operationID)
        XCTAssertGreaterThanOrEqual(again?.completedBytes ?? 0, 8192)
        XCTAssertNotEqual(again?.completedBytes, 0)
    }

    func testIdempotentApplyDoesNotResetInFlightProgress() async throws {
        let agent = makeAgent(skipBLE: true)
        let gate = ApplyReplayGate()
        var hooks = agent.executionTestHooks
        hooks?.beforeConfigurationChunkWrite = { count in
            guard count == 1 else { return }
            await gate.markReady()
            await gate.waitForReplay()
        }
        agent.executionTestHooks = hooks
        let package = try await startResourceApply(agent)
        try await waitUntil { await gate.isReady }
        let before = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(before?.completedBytes, 4096)
        let replay = try await agent.handleRuntimeXPCRequest(.apply(package))
        guard case .operationAccepted = replay else {
            await gate.allowContinue()
            return XCTFail("幂等 apply 必须再次 accepted，实际 \(replay)")
        }
        let after = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertEqual(after?.completedBytes, before?.completedBytes)
        XCTAssertEqual(after?.currentStepID, before?.currentStepID)
        XCTAssertNotEqual(after?.state, .accepted, "重放不得把进行中 operation 打回 accepted")
        await gate.allowContinue()
        try await waitUntil {
            let summary = try await self.snapshotOperation(agent, id: package.operationID)
            return (summary?.completedBytes ?? 0) > 4096 || summary?.state.isTerminal == true
        }
        let later = try await snapshotOperation(agent, id: package.operationID)
        XCTAssertGreaterThanOrEqual(later?.completedBytes ?? 0, 4096)
    }

    func testTerminalCacheEvictionDropsByteProgress() async throws {
        let agent = makeAgent(skipBLE: false)
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = testCapabilities()
        hooks?.stepExecutor = { _ in .permanentFailure }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())
        let assembled = try makeAssembledResources(fileCount: 1)
        try await ingest(agent, assembled: assembled)
        var firstPackage: AhaKeyConfigurationPackage?
        var firstTerminal: AhaKeyRuntimeOperationState?
        for index in 0..<65 {
            let package = try makePackage(from: assembled)
            if index == 0 { firstPackage = package }
            let response = try await agent.handleRuntimeXPCRequest(.apply(package))
            guard case .operationAccepted = response else {
                return XCTFail("apply 必须受理，实际 \(response)")
            }
            try await waitUntil {
                (try await self.snapshotOperation(agent, id: package.operationID))?.state.isTerminal == true
            }
            if index == 0 {
                firstTerminal = try await snapshotOperation(agent, id: package.operationID)?.state
            }
        }
        let count = await MainActor.run { agent.byteProgressCacheCountForTesting() }
        XCTAssertLessThanOrEqual(count, 64)
        let evicted = try XCTUnwrap(firstPackage)
        let durable = try XCTUnwrap(firstTerminal)
        XCTAssertTrue(durable.isTerminal)
        let beforeReplay = try await latestEventSequence(agent)
        let replay = try await agent.handleRuntimeXPCRequest(.apply(evicted))
        guard case .operationAccepted = replay else {
            return XCTFail("终态幂等 apply 仍须受理，实际 \(replay)")
        }
        let after = try await snapshotOperation(agent, id: evicted.operationID)
        XCTAssertEqual(after?.state, durable, "淘汰后重放必须投影 durable 终态，不得合成 accepted")
        XCTAssertNotEqual(after?.state, .accepted)
        XCTAssertNil(after?.completedBytes, "终态重放不得重建 0 字节 projector")
        let replayed = try await operationSummaries(agent, operationID: evicted.operationID, after: beforeReplay)
        XCTAssertFalse(
            replayed.contains { $0.state == .accepted },
            "终态淘汰后重放不得再发 accepted，实际 \(replayed.map(\.state))"
        )
        XCTAssertEqual(replayed.last?.state, durable)
    }

    // MARK: - Helpers

    private func makeAgent(skipBLE: Bool) -> AhaKeyAgent {
        let agent = AhaKeyAgent(
            socketPath: testRoot.appendingPathComponent("agent-\(UUID().uuidString.prefix(6)).sock").path,
            hookSocketURL: testRoot.appendingPathComponent("hook-\(UUID().uuidString.prefix(6)).sock"),
            enableRuntimeModules: false
        )
        let storeDir = testRoot.appendingPathComponent("store-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        var hooks = AhaKeyAgentExecutionTestHooks(storeDirectory: storeDir)
        hooks.isReady = true
        hooks.capabilities = testCapabilities()
        hooks.skipConfigurationBLEWriteGates = skipBLE
        agent.executionTestHooks = hooks
        agents.append(agent)
        return agent
    }

    private func testCapabilities() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 288, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private func simulatedDevice() -> AhaKeyRuntimeDeviceSnapshot {
        AhaKeyRuntimeDeviceSnapshot(
            id: try! AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            displayName: "Test AhaKey",
            protocolState: .currentReady,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: true
        )
    }

    private func startResourceApply(_ agent: AhaKeyAgent, fileCount: Int = 3) async throws -> AhaKeyConfigurationPackage {
        let package = try await prepareResourcePackage(agent, fileCount: fileCount)
        try await applyPrepared(agent, package: package)
        return package
    }

    private func prepareResourcePackage(_ agent: AhaKeyAgent, fileCount: Int = 3) async throws -> AhaKeyConfigurationPackage {
        await agent.simulateDeviceForTesting(simulatedDevice())
        let assembled = try makeAssembledResources(fileCount: fileCount)
        try await ingest(agent, assembled: assembled)
        return try makePackage(from: assembled)
    }

    private func applyPrepared(_ agent: AhaKeyAgent, package: AhaKeyConfigurationPackage) async throws {
        let response = try await agent.handleRuntimeXPCRequest(.apply(package))
        guard case .operationAccepted = response else {
            throw NSError(domain: "byte-progress", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(response)"])
        }
    }

    private func ingest(_ agent: AhaKeyAgent, assembled: AhaKeyStudioAssembledConfiguration) async throws {
        let items: [AhaKeyXPCResourceIngestionItem] = try assembled.resources.map { input in
            let data = try Data(contentsOf: input.fileURL)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return AhaKeyXPCResourceIngestionItem(
                logicalIdentifier: input.logicalIdentifier,
                sha256: try AhaKeySHA256Digest(digest),
                byteCount: UInt64(data.count),
                data: data
            )
        }
        let ingested = try await agent.handleRuntimeXPCRequest(.ingestResources(items))
        guard case .resourcesIngested = ingested else {
            throw NSError(domain: "byte-progress", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(ingested)"])
        }
    }

    private func makePackage(from assembled: AhaKeyStudioAssembledConfiguration) throws -> AhaKeyConfigurationPackage {
        let gif = try AhaKeyMediaType("gif")
        let resources: [AhaKeyConfigurationResource] = try assembled.resources.map { input in
            let data = try Data(contentsOf: input.fileURL)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return AhaKeyConfigurationResource(
                logicalIdentifier: input.logicalIdentifier,
                sha256: try AhaKeySHA256Digest(digest),
                byteCount: UInt64(data.count),
                mediaType: gif
            )
        }
        return try AhaKeyConfigurationPackage(
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(0),
            desiredConfiguration: assembled.configuration.canonicalData(),
            resources: resources
        )
    }

    private func makeAssembledResources(fileCount: Int) throws -> AhaKeyStudioAssembledConfiguration {
        func gifURL(_ name: String, fill: UInt8) throws -> URL {
            let url = testRoot.appendingPathComponent("\(name).gif")
            try makeGIFData(fill: fill).write(to: url)
            return url
        }
        func asset(
            _ state: AhaKeyDesiredConfiguration.TaskDisplayState,
            url: URL?
        ) -> AhaKeyStudioTaskAssetInput {
            AhaKeyStudioTaskAssetInput(
                state: state,
                localFileURL: url,
                framesPerSecond: 12,
                declaredFrameCount: url == nil ? nil : 1,
                pixelWidth: url == nil ? nil : 160,
                pixelHeight: url == nil ? nil : 80
            )
        }
        let working = fileCount >= 2 ? try gifURL("working", fill: 40) : nil
        let waiting = fileCount >= 3 ? try gifURL("waiting", fill: 80) : nil
        let done = try gifURL("done", fill: 120)
        let setA = AhaKeyStudioTaskSetInput(assets: [
            asset(.idle, url: nil),
            asset(.working, url: working),
            asset(.waiting, url: waiting),
            asset(.done, url: done),
        ])
        let emptySet = AhaKeyStudioTaskSetInput(assets: [
            asset(.idle, url: nil),
            asset(.working, url: nil),
            asset(.waiting, url: nil),
            asset(.done, url: nil),
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
                statusLine: "s", framesPerSecond: 12, taskSets: [setA, emptySet], activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove")],
                brightness: 35
            )
        )
        return try AhaKeyStudioPackageAssembler.assemble(modes: [mode])
    }

    private func makeGIFData(width: Int = 160, height: Int = 80, fill: UInt8) -> Data {
        let buffer = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            buffer, "com.compuserve.gif" as CFString, 1, nil
        )!
        var rgba = [UInt8](repeating: fill, count: width * height * 4)
        let context = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return buffer as Data
    }

    private func snapshotOperation(
        _ agent: AhaKeyAgent,
        id: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimeOperationSummary? {
        let response = try await agent.handleRuntimeXPCRequest(.snapshot)
        guard case .snapshot(let snapshot) = response else { return nil }
        return snapshot.operations.first { $0.id == id }
    }

    private func operationSummaries(
        _ agent: AhaKeyAgent,
        operationID: AhaKeyRuntimeOperationID,
        after sequence: AhaKeyRuntimeEventSequence = .init(0)
    ) async throws -> [AhaKeyRuntimeOperationSummary] {
        let response = try await agent.handleRuntimeXPCRequest(.events(after: sequence))
        guard case .eventReplay(.events(let events)) = response else { return [] }
        return events.compactMap { event in
            guard case .operationChanged(let summary) = event.payload,
                  summary.id == operationID else { return nil }
            return summary
        }
    }

    private func latestEventSequence(_ agent: AhaKeyAgent) async throws -> AhaKeyRuntimeEventSequence {
        let response = try await agent.handleRuntimeXPCRequest(.snapshot)
        guard case .snapshot(let snapshot) = response else {
            return AhaKeyRuntimeEventSequence(0)
        }
        return snapshot.latestEventSequence
    }

    private func waitUntil(
        timeout: TimeInterval = 12,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("waitUntil timed out", file: file, line: line)
    }
}

private final class FrozenTick: @unchecked Sendable {
    var value: UInt64
    init(_ value: UInt64) { self.value = value }
}

private actor StepProbe {
    var operationID = AhaKeyRuntimeOperationID()
    var resourceSteps: [AhaKeyRuntimeStepIdentifier] = []
    var secondEnter: AhaKeyRuntimeOperationSummary?

    func setOperationID(_ id: AhaKeyRuntimeOperationID) {
        operationID = id
    }

    func appendResourceStep(_ step: AhaKeyRuntimeStepIdentifier) -> Int {
        resourceSteps.append(step)
        return resourceSteps.count
    }

    func secondResourceStep() -> AhaKeyRuntimeStepIdentifier? {
        resourceSteps.dropFirst().first
    }

    func setSecondEnter(_ summary: AhaKeyRuntimeOperationSummary) {
        secondEnter = summary
    }
}

private actor ApplyReplayGate {
    private var continueWaiters: [CheckedContinuation<Void, Never>] = []
    private var ready = false
    private var allowed = false

    var isReady: Bool { ready }

    func markReady() {
        ready = true
    }

    func waitForReplay() async {
        if allowed { return }
        await withCheckedContinuation { continueWaiters.append($0) }
    }

    func allowContinue() {
        allowed = true
        let waiters = continueWaiters
        continueWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
