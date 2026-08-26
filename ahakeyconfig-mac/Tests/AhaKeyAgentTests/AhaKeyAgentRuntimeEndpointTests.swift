import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

/// WBS-5.7 R1：真实生产端点集成测试（非 FakeTransport）。
///
/// 层级说明：WBS-5.2 的 MachService 双进程层（launchd 临时登记，见
/// scripts/runtime-xpc-signed-smoke.sh 与 RuntimeXPCServer SmokeServer/SmokeClient）
/// 在测试沙盒中不可行；本测试替代层级 = 真实 `AhaKeyRuntimeXPCSessionEndpoint`
/// （会话门/握手纪律与生产一致）+ 真实 JSON 编解码 + 真实 `AhaKeyAgent` handler 路径
/// （`handleRuntimeXPCRequest` 即 startXPCServer 挂载的同一实现），仅省略
/// NSXPCConnection 传输本身（该层由 RuntimeXPCLibXPCServerTests 与 5.2 smoke 覆盖）。
///
/// 免 BLE 驱动经 `AhaKeyAgentExecutionTestHooks`（生产恒 nil）：模拟设备投影、
/// ready/capabilities 门控、步骤执行器、Store 目录重定向到临时目录。
final class AhaKeyAgentRuntimeEndpointTests: XCTestCase {

    /// 进程内端到端客户端：每次构造一个独立 endpoint（= 一条独立 XPC 会话）。
    private final class EndpointClient: @unchecked Sendable {
        private let endpoint: AhaKeyRuntimeXPCSessionEndpoint
        private let encoder = JSONEncoder()
        private let decoder = JSONDecoder()
        private(set) var requestCount = 0

        init(agent: AhaKeyAgent) {
            endpoint = AhaKeyRuntimeXPCSessionEndpoint(
                serverHandshake: agent.runtimeServerHandshake
            ) { request in
                try await agent.handleRuntimeXPCRequest(request)
            }
        }

        func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
            requestCount += 1
            let requestData = try encoder.encode(request)
            let responseData = try await endpoint.exchange(requestData)
            return try decoder.decode(AhaKeyRuntimeXPCResponse.self, from: responseData)
        }

        @discardableResult
        func handshake() async throws -> AhaKeyRuntimeXPCServerHandshake {
            let response = try await exchange(.handshake(.init(
                interfaceVersion: .current, clientBuildID: "endpoint-test"
            )))
            guard case .handshakeAccepted(let handshake) = response else {
                throw AhaKeyRuntimeXPCTransportError.invalidResponse
            }
            return handshake
        }

        func snapshot() async throws -> AhaKeyRuntimeSnapshot {
            let response = try await exchange(.snapshot)
            guard case .snapshot(let snapshot) = response else {
                throw AhaKeyRuntimeXPCTransportError.invalidResponse
            }
            return snapshot
        }

        func events(after cursor: AhaKeyRuntimeEventSequence?) async throws -> AhaKeyRuntimeEventReplayResult {
            let response = try await exchange(.events(after: cursor))
            guard case .eventReplay(let result) = response else {
                throw AhaKeyRuntimeXPCTransportError.invalidResponse
            }
            return result
        }
    }

    /// 步骤执行闸门：关闭时阻塞执行（模拟在途事务），release 后放行。
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
            for waiter in pending { waiter.resume() }
        }
    }

    private var testRoot: URL!
    private var agents: [AhaKeyAgent] = []

    override func setUp() {
        super.setUp()
        testRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-endpoint-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for agent in agents { agent.shutdown() }
        agents.removeAll()
        if let testRoot { try? FileManager.default.removeItem(at: testRoot) }
        super.tearDown()
    }

    private func makeAgent(replayCapacity: Int = 256, longPoll: TimeInterval = 0.3) -> AhaKeyAgent {
        let agent = AhaKeyAgent(
            socketPath: testRoot.appendingPathComponent("agent-\(UUID().uuidString.prefix(6)).sock").path,
            hookSocketURL: testRoot.appendingPathComponent("hook-\(UUID().uuidString.prefix(6)).sock"),
            eventReplayCapacity: replayCapacity
        )
        agent.runtimeEventsLongPollInterval = longPoll
        agent.executionTestHooks = AhaKeyAgentExecutionTestHooks(storeDirectory: testRoot)
        agents.append(agent)
        return agent
    }

    private func testCapabilities() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag,
            maxPacketSize: 200, userSlotLimit: 8, factorySlotBase: 10,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private func simulatedDevice(
        id: String = "TEST-DEVICE", name: String = "Test AhaKey", connected: Bool = true
    ) -> AhaKeyRuntimeDeviceSnapshot {
        AhaKeyRuntimeDeviceSnapshot(
            id: try! AhaKeyRuntimeDeviceID(id),
            displayName: name,
            protocolState: connected ? .currentReady : .disconnected,
            preferredTransport: .bluetooth,
            usbAttached: false,
            bluetoothConnected: connected
        )
    }

    /// 无资源引用的最小合法配置包（planner 可过；步骤执行由 hooks.stepExecutor 接管）。
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

    /// 事件跟随直到目标 operation 进入终态（或超时返回 nil）。cursor 跨调用递增。
    private func awaitTerminalState(
        _ client: EndpointClient,
        operationID: AhaKeyRuntimeOperationID,
        timeout: TimeInterval = 15
    ) async -> AhaKeyRuntimeOperationState? {
        let deadline = Date().addingTimeInterval(timeout)
        var cursor = AhaKeyRuntimeEventSequence(0)
        while Date() < deadline {
            guard let result = try? await client.events(after: cursor) else { return nil }
            switch result {
            case .snapshotRequired(let latest):
                cursor = latest
            case .events(let events):
                for event in events {
                    cursor = max(cursor, event.sequence)
                    if case .operationChanged(let summary) = event.payload,
                       summary.id == operationID, summary.state.isTerminal {
                        return summary.state
                    }
                }
            }
        }
        return nil
    }

    // MARK: - handshake / snapshot / empty replay

    func testHandshakeAdvertisesExactlyHandledCapabilities() async throws {
        let agent = makeAgent()
        let client = EndpointClient(agent: agent)
        let handshake = try await client.handshake()
        XCTAssertEqual(
            handshake.capabilities,
            [.configuration, .snapshot, .eventReplay, .diagnostics],
            "capabilities 必须与 handler 实际分支完全一致"
        )
        // 逐一验证广告的每一项都有真实 handler（非 unsupported-request）。
        guard case .snapshot = try await client.exchange(.snapshot) else {
            return XCTFail(".snapshot 必须由生产 handler 处理")
        }
        guard case .eventReplay = try await client.exchange(.events(after: .init(0))) else {
            return XCTFail(".events 必须由生产 handler 处理")
        }
        guard case .diagnosticEvents = try await client.exchange(.diagnostics(after: nil)) else {
            return XCTFail(".diagnostics 必须由生产 handler 处理")
        }
        // 未广告的能力必须仍是 unsupported-request。
        let unsupported = try await client.exchange(.startFirmwareUpgrade(.init(
            operationID: .init(),
            targetDeviceID: try AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            firmwareResource: try AhaKeyConfigurationResource(
                logicalIdentifier: "fw", sha256: String(repeating: "a", count: 64),
                byteCount: 1, mediaType: "bin"
            )
        )))
        guard case .failure(let code) = unsupported else {
            return XCTFail("未广告能力不得被处理")
        }
        XCTAssertEqual(code.rawValue, "unsupported-request")
    }

    func testSnapshotReturnsAuthoritativeProjection() async throws {
        let agent = makeAgent()
        let client = EndpointClient(agent: agent)
        try await client.handshake()

        let initial = try await client.snapshot()
        XCTAssertEqual(initial.lifecycleState, .running)
        XCTAssertEqual(initial.policy, AhaKeyAgent.compatibleDefaultPolicy)
        XCTAssertEqual(initial.latestEventSequence, .init(0))
        XCTAssertTrue(initial.devices.isEmpty)
        XCTAssertNil(initial.activeDeviceID)

        // 设备连接 → 投影出现设备，序号单调递增。
        await agent.simulateDeviceForTesting(simulatedDevice())
        let withDevice = try await client.snapshot()
        XCTAssertEqual(withDevice.devices.count, 1)
        XCTAssertEqual(withDevice.activeDeviceID, try AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        XCTAssertEqual(withDevice.devices.first?.protocolState, .currentReady)
        XCTAssertEqual(withDevice.latestEventSequence, .init(1))
    }

    func testEmptyReplayLongPollsAndReturnsEmptyBatch() async throws {
        let agent = makeAgent(longPoll: 0.3)
        let client = EndpointClient(agent: agent)
        try await client.handshake()
        let snapshot = try await client.snapshot()

        // 空批必须挂起 ≈ long-poll 时长后返回空（证明服务端不忙轮询、客户端空闲请求率受控）。
        var elapsed: [TimeInterval] = []
        for _ in 0 ..< 3 {
            let start = Date()
            let result = try await client.events(after: snapshot.latestEventSequence)
            elapsed.append(Date().timeIntervalSince(start))
            guard case .events(let events) = result, events.isEmpty else {
                return XCTFail("空回放必须返回空批")
            }
        }
        for (index, duration) in elapsed.enumerated() {
            XCTAssertGreaterThanOrEqual(duration, 0.25, "第 \(index) 次空回放应挂起至 long-poll 超时")
            XCTAssertLessThan(duration, 2.0, "第 \(index) 次空回放不得无限挂起")
        }
        // 请求率断言：3 次请求耗时 ≥ 3×0.25s ⇒ 空闲请求率 ≤ 4/s（生产 2s long-poll ⇒ ≤0.5/s）。
        let total = elapsed.reduce(0, +)
        XCTAssertLessThanOrEqual(Double(elapsed.count) / total, 4.0)
    }

    func testNewEventWakesLongPollImmediately() async throws {
        let agent = makeAgent(longPoll: 5.0)
        let client = EndpointClient(agent: agent)
        try await client.handshake()
        _ = try await client.snapshot()

        let start = Date()
        async let replay = client.events(after: .init(0))
        try await Task.sleep(nanoseconds: 200_000_000)
        await agent.simulateDeviceForTesting(simulatedDevice())
        let result = try await replay
        let duration = Date().timeIntervalSince(start)
        XCTAssertLessThan(duration, 2.0, "新事件必须立即唤醒 long-poll，不得等满超时")
        guard case .events(let events) = result, events.count == 1 else {
            return XCTFail("应收到 deviceChanged 事件")
        }
        guard case .deviceChanged(let device) = events.first?.payload else {
            return XCTFail("首事件应为 deviceChanged")
        }
        XCTAssertEqual(device.id, try AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        XCTAssertEqual(events.first?.sequence, .init(1))
    }

    // MARK: - gap → snapshotRequired

    func testReplayBufferOverflowYieldsSnapshotRequired() async throws {
        let agent = makeAgent(replayCapacity: 2)
        let client = EndpointClient(agent: agent)
        try await client.handshake()

        // 4 个不同设备投影 → sequence 1...4，capacity 2 只留 3、4。
        for index in 0 ..< 4 {
            await agent.simulateDeviceForTesting(simulatedDevice(name: "AhaKey-\(index)"))
        }
        let result = try await client.events(after: .init(1))
        guard case .snapshotRequired(let latest) = result else {
            return XCTFail("游标断档必须返回 snapshotRequired，实际 \(result)")
        }
        XCTAssertEqual(latest, .init(4))
        // 未断档的游标正常回放。
        guard case .events(let tail) = try await client.events(after: .init(3)) else {
            return XCTFail("未断档游标应正常回放")
        }
        XCTAssertEqual(tail.map(\.sequence), [.init(4)])
    }

    // MARK: - apply：durable accept 立即回 ID + 异步执行

    func testApplyDurableAcceptsImmediatelyAndExecutesAsynchronously() async throws {
        let agent = makeAgent()
        let gate = StepGate()
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = testCapabilities()
        hooks?.stepExecutor = { _ in
            await gate.wait()
            return .success
        }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())

        let client = EndpointClient(agent: agent)
        try await client.handshake()
        let package = try makePackage(deviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"))

        // 执行器被闸门阻塞期间，apply 必须立即返回（durable accept 不等事务终态）。
        let start = Date()
        let response = try await client.exchange(.apply(package))
        let duration = Date().timeIntervalSince(start)
        guard case .operationAccepted(let operationID) = response else {
            return XCTFail("durable accept 必须返回 operationAccepted，实际 \(response)")
        }
        XCTAssertEqual(operationID, package.operationID)
        XCTAssertLessThan(duration, 1.0, "apply 不得等事务执行完才返回（闸门仍关闭）")

        // accepted 立即进入投影/事件。
        let snapshot = try await client.snapshot()
        XCTAssertTrue(snapshot.operations.contains {
            $0.id == operationID && ($0.state == .accepted || $0.state == .running)
        }, "accepted 摘要必须立即可从 snapshot 观察")

        // 放行执行：终态经事件可观察，snapshot 反映 completed + revision 推进。
        await gate.release()
        let terminal = await awaitTerminalState(client, operationID: operationID)
        XCTAssertEqual(terminal, .completed, "执行终态必须经 operationChanged 事件发布")
        let final = try await client.snapshot()
        XCTAssertTrue(final.operations.contains { $0.id == operationID && $0.state == .completed })
        XCTAssertEqual(final.configurationRevision, .init(1), "完成后 baseline revision 必须 base+1")
    }

    func testCancellationDuringExecutionTakesEffect() async throws {
        let agent = makeAgent()
        let deviceID = try AhaKeyRuntimeDeviceID("TEST-DEVICE")
        let package = try makePackage(deviceID: deviceID)
        let operationID = package.operationID
        let storeDirectory = testRoot!
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = testCapabilities()
        // 步骤执行器：等到 WAL 出现 cancellationRequested 再失败收尾（模拟在途长步骤）。
        hooks?.stepExecutor = { _ in
            let store = try! AhaKeyRuntimePersistentStore(
                rootDirectory: storeDirectory,
                acceptanceValidator: AhaKeyConfigurationPlanner.AcceptanceValidator()
            )
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let record = try? await store.transaction(operationID),
                   record.state == .cancellationRequested {
                    return .retryableFailure
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return .success
        }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())

        let client = EndpointClient(agent: agent)
        try await client.handshake()
        guard case .operationAccepted = try await client.exchange(.apply(package)) else {
            return XCTFail("apply 必须受理")
        }

        // 执行中取消：真实落 WAL，返回 .requested。
        let cancellation = try await client.exchange(.requestCancellation(operationID))
        XCTAssertEqual(cancellation, .cancellation(.requested))

        // 步间安全点结算：终态事件可观察（无已确认步骤 → failedWithoutWrites）。
        let terminal = await awaitTerminalState(client, operationID: operationID)
        XCTAssertNotNil(terminal, "取消后事务必须结算到终态并经事件发布")
        XCTAssertTrue(terminal?.isTerminal ?? false)

        // 终态后再取消 → alreadyFinished；未知 operation → notFound。均不伪装。
        let again = try await client.exchange(.requestCancellation(operationID))
        XCTAssertEqual(again, .cancellation(.alreadyFinished))
        let unknown = try await client.exchange(.requestCancellation(AhaKeyRuntimeOperationID()))
        XCTAssertEqual(unknown, .cancellation(.notFound))
    }

    func testFailedAcceptanceReturnsFailureNotAccepted() async throws {
        let agent = makeAgent()
        let client = EndpointClient(agent: agent)
        try await client.handshake()

        // 引用未入 CAS 的资源：受理必须失败（missing-resource），绝不伪装 accepted。
        var package = try makePackage(deviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        package = try AhaKeyConfigurationPackage(
            operationID: package.operationID,
            targetDeviceID: package.targetDeviceID,
            baseRevision: package.baseRevision,
            desiredConfiguration: package.desiredConfiguration,
            resources: [
                try AhaKeyConfigurationResource(
                    logicalIdentifier: "missing-gif",
                    sha256: String(repeating: "b", count: 64),
                    byteCount: 10,
                    mediaType: "gif"
                ),
            ]
        )
        let response = try await client.exchange(.apply(package))
        guard case .failure(let code) = response else {
            return XCTFail("受理失败必须 .failure，实际 \(response)")
        }
        XCTAssertTrue(code.rawValue.hasPrefix("missing-resource:"), "实际 code=\(code.rawValue)")
    }

    // MARK: - 客户端断连不影响已受理执行

    func testClientDisconnectDoesNotAffectAcceptedExecution() async throws {
        let agent = makeAgent()
        let gate = StepGate()
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = testCapabilities()
        hooks?.stepExecutor = { _ in
            await gate.wait()
            return .success
        }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())

        // client1：handshake + apply 后「断开」（释放 endpoint，进程内等价于 XPC 连接销毁）。
        var client1: EndpointClient? = EndpointClient(agent: agent)
        try await client1!.handshake()
        let package = try makePackage(deviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        guard case .operationAccepted(let operationID) = try await client1!.exchange(.apply(package)) else {
            return XCTFail("apply 必须受理")
        }
        client1 = nil

        // 断开后放行执行；全新 client2（新会话）仍能观察到事务推进至终态。
        await gate.release()
        let client2 = EndpointClient(agent: agent)
        try await client2.handshake()
        let terminal = await awaitTerminalState(client2, operationID: operationID)
        XCTAssertEqual(terminal, .completed, "Studio 断连不得影响 Agent 已受理事务的执行")
        let snapshot = try await client2.snapshot()
        XCTAssertTrue(snapshot.operations.contains { $0.id == operationID && $0.state == .completed })
    }

    // MARK: - R2-3：schema 广告单一来源

    func testHandshakeAndSnapshotAdvertiseSingleSchemaSource() async throws {
        let agent = makeAgent()
        let client = EndpointClient(agent: agent)
        let handshake = try await client.handshake()
        let snapshot = try await client.snapshot()
        XCTAssertEqual(
            handshake.supportedConfigurationSchemaVersions,
            snapshot.supportedConfigurationSchemaVersions,
            "handshake 与 snapshot 的 schema 广告必须同源一致"
        )
        XCTAssertEqual(
            handshake.supportedConfigurationSchemaVersions,
            [AhaKeyConfigurationPackage.currentSchemaVersion],
            "schema 广告必须以 AhaKeyConfigurationPackage.currentSchemaVersion 为单一来源"
        )
        // 实际提交包的 schemaVersion 必须被广告覆盖。
        let package = try makePackage(deviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        XCTAssertTrue(handshake.supportedConfigurationSchemaVersions.contains(package.schemaVersion))
    }

    // MARK: - R2-2：并发 apply 串行排空

    /// 执行并发探针：记录 stepExecutor 最大并行度（证明不存在两个并行 runner）。
    private actor ExecutionConcurrencyProbe {
        private(set) var inFlight = 0
        private(set) var maxConcurrent = 0

        func enter() {
            inFlight += 1
            maxConcurrent = max(maxConcurrent, inFlight)
        }

        func exit() {
            inFlight -= 1
        }
    }

    func testConcurrentAppliesFromTwoClientsSerializeAndDrain() async throws {
        let agent = makeAgent()
        let gate = StepGate()
        let probe = ExecutionConcurrencyProbe()
        var hooks = agent.executionTestHooks
        hooks?.isReady = true
        hooks?.capabilities = testCapabilities()
        hooks?.stepExecutor = { _ in
            await probe.enter()
            await gate.wait()
            await probe.exit()
            return .success
        }
        agent.executionTestHooks = hooks
        await agent.simulateDeviceForTesting(simulatedDevice())

        // 双客户端（两条独立 XPC 会话）同时提交。
        let client1 = EndpointClient(agent: agent)
        let client2 = EndpointClient(agent: agent)
        try await client1.handshake()
        try await client2.handshake()
        let deviceID = try AhaKeyRuntimeDeviceID("TEST-DEVICE")
        let package1 = try makePackage(deviceID: deviceID)
        let package2 = try makePackage(deviceID: deviceID)

        // 首个事务被闸门阻塞执行中；第二个 apply 必须仍然受理成功（durable accept 即返 ID）。
        async let response1 = client1.exchange(.apply(package1))
        async let response2 = client2.exchange(.apply(package2))
        let start = Date()
        let (r1, r2) = try await (response1, response2)
        let acceptDuration = Date().timeIntervalSince(start)
        guard case .operationAccepted(let op1) = r1, case .operationAccepted(let op2) = r2 else {
            return XCTFail("两个 apply 都必须 durable accept，实际 \(r1) / \(r2)")
        }
        XCTAssertLessThan(acceptDuration, 1.0, "受理不得被在途事务阻塞（busy 滞留已收口）")

        // 串行证据：闸门仍关闭时，op1 在飞（非终态），op2 必须仍为 accepted（不得并行进入 running）。
        let midSnapshot = try await client1.snapshot()
        let mid1 = midSnapshot.operations.first { $0.id == op1 }
        let mid2 = midSnapshot.operations.first { $0.id == op2 }
        XCTAssertNotNil(mid1)
        XCTAssertEqual(mid2?.state, .accepted, "串行协调器下第二个事务必须排队等待，不得并行执行")
        XCTAssertFalse(mid1?.state.isTerminal ?? true)

        // 放行后两者都必须到终态（worker 持续排空 WAL，无需重连）。
        await gate.release()
        let terminal1 = await awaitTerminalState(client1, operationID: op1)
        let terminal2 = await awaitTerminalState(client2, operationID: op2)
        XCTAssertEqual(terminal1, .completed)
        XCTAssertEqual(terminal2, .completed, "后受理事务必须在前者完成后自动执行到终态")
        let maxConcurrent = await probe.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1, "任一时刻只能有一个事务执行体在飞（不得两个 BLE runner 并行）")
    }

    // MARK: - R2-5：long-poll lost-wakeup 收口

    func testLongPollGapEventReturnedImmediatelyWithoutFullTimeout() async throws {
        let agent = makeAgent(longPoll: 5.0)
        let device = simulatedDevice()
        // 可控交错：在「空批快路径 → waiter 登记」夹缝中确定性地发布事件。
        var hooks = agent.executionTestHooks
        hooks?.eventsLongPollGapHook = { [weak agent] in
            agent?.setSimulatedDeviceOnMainForTesting(device)
        }
        agent.executionTestHooks = hooks

        let client = EndpointClient(agent: agent)
        try await client.handshake()

        let start = Date()
        let result = try await client.events(after: .init(0))
        let duration = Date().timeIntervalSince(start)
        // 夹缝事件必须被临界区二次复查命中：立即返回，不白等完整 5s 超时（≤2s 门禁）。
        XCTAssertLessThan(duration, 2.0, "夹缝事件不得白等完整 long-poll 超时")
        guard case .events(let events) = result, events.count == 1 else {
            return XCTFail("夹缝中发布的事件必须立即返回，实际 \(result)")
        }
        guard case .deviceChanged(let published) = events.first?.payload else {
            return XCTFail("事件应为 deviceChanged")
        }
        XCTAssertEqual(published.id, try AhaKeyRuntimeDeviceID("TEST-DEVICE"))
        XCTAssertEqual(events.first?.sequence, .init(1))
    }

    // MARK: - R2-1 旁证：相同投影零 UI 发布

    func testIdenticalDeviceProjectionPublishesNoDuplicateEvent() async throws {
        let agent = makeAgent()
        let client = EndpointClient(agent: agent)
        try await client.handshake()

        await agent.simulateDeviceForTesting(simulatedDevice())
        // 相同投影再次驱动：不得发布第二个 deviceChanged。
        await agent.simulateDeviceForTesting(simulatedDevice())

        guard case .events(let events) = try await client.events(after: .init(0)) else {
            return XCTFail("应返回事件批")
        }
        XCTAssertEqual(events.count, 1, "相同状态必须零 UI 发布（内容去重）")
    }
}
