import XCTest
@testable import AhaKeyConfigShared

/// WBS 5.7 切片 1：Studio Runtime facade 的连接状态机测试。
/// 覆盖：handshake→snapshot 首屏、event cursor 跟随、断档 snapshotRequired→重取快照、
/// 传输错误→offline→重连恢复、stop 语义与视图状态流。
final class AhaKeyStudioRuntimeFacadeTests: XCTestCase {

    /// 可编程假传输：按请求类型返回脚本化响应，支持注入错误与一次性断档。
    private final class FakeTransport: AhaKeyStudioRuntimeTransport, @unchecked Sendable {
        private let lock = NSLock()
        var snapshot: AhaKeyRuntimeSnapshot
        /// 每次 events 请求返回的下一批事件；脚本用完后返回空批。
        var eventBatches: [[AhaKeyRuntimeEvent]] = []
        /// 非 0 时对 events 请求返回断档（每次请求消耗 1）。
        var gapResponsesRemaining = 0
        /// 注入错误：非 nil 时下一次 exchange 抛错（自动消费）。
        var nextError: Error?
        private(set) var requestLog: [String] = []

        init(snapshot: AhaKeyRuntimeSnapshot) {
            self.snapshot = snapshot
        }

        func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
            lock.lock()
            defer { lock.unlock() }
            if let error = nextError {
                nextError = nil
                requestLog.append("error")
                throw error
            }
            switch request {
            case .handshake:
                requestLog.append("handshake")
                return .handshakeAccepted(.init(
                    runtimeVersion: .development,
                    interfaceVersion: .current,
                    supportedConfigurationSchemaVersions: [3],
                    capabilities: [.snapshot, .eventReplay, .configuration]
                ))
            case .snapshot:
                requestLog.append("snapshot")
                return .snapshot(snapshot)
            case .events(let after):
                requestLog.append("events(\(after?.rawValue.description ?? "nil"))")
                if gapResponsesRemaining > 0 {
                    gapResponsesRemaining -= 1
                    return .eventReplay(.snapshotRequired(latest: snapshot.latestEventSequence))
                }
                guard !eventBatches.isEmpty else {
                    return .eventReplay(.events([]))
                }
                return .eventReplay(.events(eventBatches.removeFirst()))
            default:
                return .failure(try! AhaKeyRuntimeEventCode("unsupported"))
            }
        }
    }

    /// 状态流记录器：后台消费 facade 发布的状态序列，供精确断言瞬态。
    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var states: [AhaKeyStudioRuntimeViewState] = []
        private var task: Task<Void, Never>?

        func start(_ facade: AhaKeyStudioRuntimeFacade) {
            task = Task {
                for await state in await facade.viewStates() {
                    lock.lock()
                    states.append(state)
                    lock.unlock()
                }
            }
        }

        func stop() { task?.cancel() }

        func contains(_ predicate: (AhaKeyStudioRuntimeViewState) -> Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return states.contains(where: predicate)
        }
    }

    private func makeSnapshot(sequence: UInt64) -> AhaKeyRuntimeSnapshot {
        AhaKeyRuntimeSnapshot(
            lifecycleState: .running,
            devices: [],
            activeDeviceID: nil,
            configurationRevision: .init(0),
            operations: [],
            policy: .init(),
            permissions: .init(states: [:]),
            keepAliveReasons: [],
            latestEventSequence: .init(sequence)
        )
    }

    private func makeEvent(_ sequence: UInt64) -> AhaKeyRuntimeEvent {
        AhaKeyRuntimeEvent(
            sequence: .init(sequence),
            context: .init(),
            payload: .lifecycleChanged(.running)
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ predicate: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    func testHandshakeThenSnapshotFirstScreen() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        await facade.start()
        let online = await waitUntil { await facade.currentState().connection == .online }
        XCTAssertTrue(online)
        let state = await facade.currentState()
        XCTAssertNotNil(state.snapshot)
        XCTAssertEqual(state.eventCursor, .init(0))
        XCTAssertNil(state.lastError)
        XCTAssertEqual(transport.requestLog.first, "handshake")
        XCTAssertEqual(transport.requestLog.dropFirst().first, "snapshot")
        await facade.stop()
    }

    func testEventCursorFollowsMonotonicBatches() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.eventBatches = [[makeEvent(1), makeEvent(2)], [makeEvent(3)]]
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        await facade.start()
        let followed = await waitUntil {
            await facade.currentState().eventCursor == AhaKeyRuntimeEventSequence(3)
        }
        XCTAssertTrue(followed)
        let finalState = await facade.currentState()
        XCTAssertEqual(finalState.connection, .online)
        await facade.stop()
    }

    func testGapTriggersSnapshotResync() async {
        // Runtime 已推进到 5；回放断档一次，随后恢复空批。
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 5))
        transport.gapResponsesRemaining = 1
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        let recorder = StateRecorder()
        recorder.start(facade)
        await facade.start()
        let resynced = await waitUntil {
            let state = await facade.currentState()
            return state.connection == .online && state.eventCursor == .init(5)
        }
        XCTAssertTrue(resynced, "断档后必须重取快照并把游标复位到 5")
        XCTAssertTrue(recorder.contains { $0.connection == .resyncing }, "必须发布过 resyncing 瞬态")
        // 首屏 snapshot + 断档重取 snapshot ≥ 2 次。
        let snapshotCount = transport.requestLog.filter { $0 == "snapshot" }.count
        XCTAssertGreaterThanOrEqual(snapshotCount, 2)
        await facade.stop()
        recorder.stop()
    }

    func testTransportErrorGoesOfflineThenReconnects() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        transport.nextError = AhaKeyRuntimeXPCTransportError.requestTimedOut
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        let recorder = StateRecorder()
        recorder.start(facade)
        await facade.start()
        let recovered = await waitUntil {
            await facade.currentState().connection == .online
                && recorder.contains { $0.connection == .offline && $0.lastError != nil }
        }
        XCTAssertTrue(recovered, "必须经历 offline(带错误) 后重连恢复 online")
        XCTAssertEqual(transport.requestLog.first, "error")
        await facade.stop()
        recorder.stop()
    }

    func testStopPublishesOfflineAndIsIdempotent() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        await facade.start()
        _ = await waitUntil { await facade.currentState().connection == .online }
        await facade.stop()
        var state = await facade.currentState()
        XCTAssertEqual(state.connection, .offline)
        // stop 幂等。
        await facade.stop()
        state = await facade.currentState()
        XCTAssertEqual(state.connection, .offline)
        // start 幂等：重复 start 不叠加循环。
        await facade.start()
        await facade.start()
        _ = await waitUntil { await facade.currentState().connection == .online }
        state = await facade.currentState()
        XCTAssertEqual(state.connection, .online)
        await facade.stop()
    }

    func testViewStateStreamYieldsCurrentThenUpdates() async {
        let transport = FakeTransport(snapshot: makeSnapshot(sequence: 0))
        let facade = AhaKeyStudioRuntimeFacade(
            transport: transport, clientBuildID: "test", reconnectBackoffBase: 0
        )
        let recorder = StateRecorder()
        recorder.start(facade)
        await facade.start()
        let online = await waitUntil { await facade.currentState().connection == .online }
        XCTAssertTrue(online)
        // 首条是订阅时的当前值（offline），随后出现 online。
        XCTAssertTrue(recorder.contains { $0.connection == .offline })
        XCTAssertTrue(recorder.contains { $0.connection == .online })
        await facade.stop()
        recorder.stop()
    }
}
