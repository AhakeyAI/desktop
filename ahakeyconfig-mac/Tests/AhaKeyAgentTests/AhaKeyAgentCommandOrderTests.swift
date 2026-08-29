import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

/// C-1R2：JSON 命令时序与生产事务窗口 begin/end 配对。
final class AhaKeyAgentCommandOrderTests: XCTestCase {
    private final class TraceLog: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [AhaKeyAgentCommandTraceEvent] = []

        func append(_ event: AhaKeyAgentCommandTraceEvent) {
            lock.lock()
            events.append(event)
            lock.unlock()
        }

        var snapshot: [AhaKeyAgentCommandTraceEvent] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }

        var windowEvents: [AhaKeyAgentCommandTraceEvent] {
            snapshot.filter {
                switch $0 {
                case .transportWindowBegin, .transportWindowEnd: return true
                default: return false
                }
            }
        }
    }

    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-cmd-order-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for agent in agents { agent.shutdown() }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    private func runTest(_ work: @escaping () async throws -> Void) {
        let finished = expectation(description: "command-order-test")
        Task {
            do { try await work() }
            catch { XCTFail("command-order test error: \(error)") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 45)
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

    private func attachTrace(_ agent: AhaKeyAgent) -> TraceLog {
        let log = TraceLog()
        var hooks = agent.executionTestHooks ?? AhaKeyAgentExecutionTestHooks()
        hooks.commandTrace = { log.append($0) }
        agent.executionTestHooks = hooks
        return log
    }

    func testStateWithResetSendsBeforeInstallingReset() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            await MainActor.run {
                agent.handleJsonCommandForTesting(cmd: "state_with_reset", obj: [
                    "value": 3,
                    "resetValue": 4,
                    "delayMs": 60_000,
                ])
                XCTAssertEqual(log.snapshot, [.sendState(3), .installStateReset(4)])
                XCTAssertTrue(
                    agent.hasPendingStateResetForTesting,
                    "初始 sendState 不得把刚安装的 reset 取消掉"
                )
            }
        }
    }

    func testPermissionEnqueuesStateBeforeQuery() {
        runTest { [self] in
            try await assertPermissionEnqueuesStateBeforeQuery(occupyQueue: false)
        }
    }

    /// queue busy 时 enqueue 返回 nil，仍必须记下 `enqueuedState`（入队 ≠ head promotion）。
    func testPermissionEnqueuesStateWhenQueueBusy() {
        runTest { [self] in
            try await assertPermissionEnqueuesStateBeforeQuery(occupyQueue: true)
        }
    }

    func testStaleDelayedResetDoesNotOverrideNewerCommand() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            await MainActor.run {
                agent.handleJsonCommandForTesting(cmd: "state_with_reset", obj: [
                    "value": 3, "resetValue": 4, "delayMs": 80,
                ])
            }
            try await Task.sleep(nanoseconds: 20_000_000)
            await MainActor.run {
                agent.handleJsonCommandForTesting(cmd: "state_with_reset", obj: [
                    "value": 7, "resetValue": 8, "delayMs": 60_000,
                ])
                XCTAssertTrue(agent.hasPendingStateResetForTesting)
            }
            try await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                let sent = log.snapshot.compactMap { event -> UInt8? in
                    if case .sendState(let value) = event { return value }
                    return nil
                }
                XCTAssertEqual(sent, [3, 7], "过时 reset(4) 不得在新命令之后发送")
                XCTAssertTrue(agent.hasPendingStateResetForTesting, "迟到的旧 reset 不得取消新 reset")
                XCTAssertTrue(log.snapshot.contains(.installStateReset(8)))
            }
        }
    }

    func testProductionWindowPairsBeginEndOnSuccess() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            let value = try await agent.withConfigurationTransportWindowForTesting { 7 }
            XCTAssertEqual(value, 7)
            XCTAssertEqual(log.windowEvents, [.transportWindowBegin, .transportWindowEnd])
            let active = await MainActor.run { agent.isConfigurationTransportWindowActiveForTesting }
            XCTAssertFalse(active)
        }
    }

    func testProductionWindowPairsBeginEndOnThrow() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            struct Boom: Error {}
            do {
                _ = try await agent.withConfigurationTransportWindowForTesting { () -> Int in
                    throw Boom()
                }
                XCTFail("应抛出 Boom")
            } catch is Boom {
                // expected
            } catch {
                XCTFail("应抛出 Boom，实际 \(error)")
            }
            XCTAssertEqual(log.windowEvents, [.transportWindowBegin, .transportWindowEnd])
            let active = await MainActor.run { agent.isConfigurationTransportWindowActiveForTesting }
            XCTAssertFalse(active)
        }
    }

    func testProductionWindowPairsBeginEndOnCancel() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            let entered = Once()
            let task = Task {
                try await agent.withConfigurationTransportWindowForTesting {
                    await entered.signal()
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            try await entered.wait()
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("取消后不应成功返回")
            } catch is CancellationError {
                // expected
            } catch {
                XCTFail("取消应抛 CancellationError，实际 \(error)")
            }
            XCTAssertEqual(log.windowEvents, [.transportWindowBegin, .transportWindowEnd])
            let active = await MainActor.run { agent.isConfigurationTransportWindowActiveForTesting }
            XCTAssertFalse(active)
        }
    }

    /// apply 走 `configurationCoordinator.kick` → `runConfigurationTransaction`，必须用同一套 begin/end。
    func testApplyTransactionPairsWindowBeginEnd() {
        runTest { [self] in
            try await assertApplyWindowPairing(
                stepExecutor: { _ in .success },
                expectedTerminal: .completed
            )
        }
    }

    func testApplyFailurePairsWindowBeginEnd() {
        runTest { [self] in
            try await assertApplyWindowPairing(
                stepExecutor: { _ in .permanentFailure },
                expectedTerminal: .failedWithoutWrites
            )
        }
    }

    func testApplyCancellationPairsWindowBeginEnd() {
        runTest { [self] in
            let agent = makeAgent()
            let log = attachTrace(agent)
            let deviceID = try AhaKeyRuntimeDeviceID("TEST-DEVICE")
            let package = try makePackage(deviceID: deviceID)
            let storeDirectory = agent.executionTestHooks!.storeDirectory!
            let entered = Once()
            try await prepareApply(agent, stepExecutor: { _ in
                await entered.signal()
                let store = try! AhaKeyRuntimePersistentStore(
                    rootDirectory: storeDirectory,
                    acceptanceValidator: AhaKeyConfigurationPlanner.AcceptanceValidator()
                )
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline {
                    if let record = try? await store.transaction(package.operationID),
                       record.state == .cancellationRequested {
                        return .retryableFailure
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                return .success
            })
            let accepted = try await agent.handleRuntimeXPCRequest(.apply(package))
            guard case .operationAccepted = accepted else {
                return XCTFail("apply 必须受理，实际 \(accepted)")
            }
            await waitUntil {
                log.windowEvents.contains(.transportWindowBegin)
            }
            try await entered.wait()
            let cancellation = try await agent.handleRuntimeXPCRequest(
                .requestCancellation(package.operationID)
            )
            XCTAssertEqual(cancellation, .cancellation(.requested))
            await waitForWindowClosed(log)
            XCTAssertEqual(log.windowEvents, [.transportWindowBegin, .transportWindowEnd])
            let active = await MainActor.run { agent.isConfigurationTransportWindowActiveForTesting }
            XCTAssertFalse(active)
            let record = try await waitForTerminalRecord(
                storeDirectory: storeDirectory,
                operationID: package.operationID
            )
            XCTAssertEqual(
                record?.state,
                .failedWithoutWrites,
                "无写入取消必须结算到 failedWithoutWrites，不能停在 cancellationRequested"
            )
        }
    }

    private func assertPermissionEnqueuesStateBeforeQuery(occupyQueue: Bool) async throws {
        let agent = makeAgent()
        let log = attachTrace(agent)
        var hooks = agent.executionTestHooks
        hooks?.skipStateCommandBLEWriteGates = true
        agent.executionTestHooks = hooks
        await MainActor.run {
            agent.primeTransportForCommandEnqueueForTesting(occupyQueue: occupyQueue)
            agent.handleJsonCommandForTesting(cmd: "permission", obj: ["value": 1])
            let ordered = log.snapshot.filter {
                switch $0 {
                case .enqueuedState, .querySwitchState: return true
                default: return false
                }
            }
            XCTAssertEqual(
                ordered,
                [.enqueuedState(1), .querySwitchState],
                occupyQueue
                    ? "queue busy 时 0x90 仍已入队，权威证据不得依赖 head promotion"
                    : "权威证据是真实 enqueue 入队，不是 sendState 函数入口"
            )
        }
    }

    private func assertApplyWindowPairing(
        stepExecutor: @escaping @Sendable (AhaKeyRuntimeStepIdentifier) async -> AhaKeyConfigurationStepResult,
        expectedTerminal: AhaKeyRuntimeOperationState
    ) async throws {
        let agent = makeAgent()
        let log = attachTrace(agent)
        try await prepareApply(agent, stepExecutor: stepExecutor)
        let package = try makePackage(deviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        let response = try await agent.handleRuntimeXPCRequest(.apply(package))
        guard case .operationAccepted = response else {
            return XCTFail("apply 必须受理，实际 \(response)")
        }
        await waitForWindowClosed(log)
        XCTAssertEqual(log.windowEvents, [.transportWindowBegin, .transportWindowEnd])
        let active = await MainActor.run { agent.isConfigurationTransportWindowActiveForTesting }
        XCTAssertFalse(active)
        let record = try await waitForTerminalRecord(
            storeDirectory: agent.executionTestHooks!.storeDirectory!,
            operationID: package.operationID
        )
        XCTAssertEqual(record?.state, expectedTerminal)
    }

    private func prepareApply(
        _ agent: AhaKeyAgent,
        stepExecutor: @escaping @Sendable (AhaKeyRuntimeStepIdentifier) async -> AhaKeyConfigurationStepResult
    ) async throws {
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 8, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
        hooks?.stepExecutor = stepExecutor
        hooks?.release = .picturesUnrestrictedForTests
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(AhaKeyRuntimeDeviceSnapshot(
            id: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            displayName: "Test AhaKey",
            protocolState: .currentReady,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: true
        ))
    }

    private func makePackage(deviceID: AhaKeyRuntimeDeviceID) throws -> AhaKeyConfigurationPackage {
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
        return try AhaKeyConfigurationPackage(
            targetDeviceID: deviceID,
            baseRevision: .init(0),
            desiredConfiguration: assembled.configuration.canonicalData(),
            resources: []
        )
    }

    private func waitForWindowClosed(_ log: TraceLog) async {
        await waitUntil { log.windowEvents == [.transportWindowBegin, .transportWindowEnd] }
    }

    private func waitUntil(
        _ predicate: () -> Bool,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("waitUntil timed out", file: file, line: line)
    }

    private func waitForTerminalRecord(
        storeDirectory: URL,
        operationID: AhaKeyRuntimeOperationID,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AhaKeyRuntimePersistedTransaction? {
        let store = try AhaKeyRuntimePersistentStore(
            rootDirectory: storeDirectory,
            acceptanceValidator: AhaKeyConfigurationPlanner.AcceptanceValidator()
        )
        let deadline = Date().addingTimeInterval(timeout)
        var last: AhaKeyRuntimePersistedTransaction?
        while Date() < deadline {
            last = try await store.transaction(operationID)
            if let last, last.state.isTerminal { return last }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("terminal WAL record not reached", file: file, line: line)
        return last
    }
}

private struct OnceWaitTimeout: Error {}

private actor Once {
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var fired = false

    func signal() {
        fired = true
        for task in timeouts.values { task.cancel() }
        timeouts.removeAll()
        let pending = waiters
        waiters.removeAll()
        for (_, waiter) in pending { waiter.resume() }
    }

    func wait(timeout: TimeInterval = 10) async throws {
        if fired { return }
        let id = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            waiters[id] = continuation
            timeouts[id] = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.failIfPending(id)
            }
        }
        timeouts[id]?.cancel()
        timeouts[id] = nil
    }

    private func failIfPending(_ id: UUID) {
        timeouts[id] = nil
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.resume(throwing: OnceWaitTimeout())
    }
}
