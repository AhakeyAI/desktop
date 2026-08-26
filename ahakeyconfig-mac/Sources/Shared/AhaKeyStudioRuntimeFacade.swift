import Foundation

// MARK: - WBS 5.7 切片 1：Studio Runtime client/facade
//
// Studio 侧唯一 Runtime 事实源入口：handshake → snapshot 首屏 → events cursor
// 跟随（断档 snapshotRequired → 重取 snapshot）→ 离线/重连状态机。
// 事实源永远在 Runtime；本 facade 不复制设备状态，只保存「最近一次快照 + 事件游标」
// 作为 UI 派生输入。传输层可注入（生产 = XPC，测试 = 内存假实现）。

/// Studio facade 的请求/响应传输抽象。生产实现走 `AhaKeyRuntimeXPCConnectionTransport`。
public protocol AhaKeyStudioRuntimeTransport: Sendable {
    func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse
}

/// 生产 XPC 传输：JSON 编解码 + 既有连接 transport（wire v1.1 不变）。
public struct AhaKeyStudioRuntimeXPCTransport: AhaKeyStudioRuntimeTransport {
    private let connection: AhaKeyRuntimeXPCConnectionTransport
    private let timeout: TimeInterval

    public init(machServiceName: String = "lab.jawa.ahakeyconfig.runtime", timeout: TimeInterval = 10) {
        self.connection = AhaKeyRuntimeXPCConnectionTransport(machServiceName: machServiceName)
        self.timeout = timeout
    }

    public func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        let requestData = try JSONEncoder().encode(request)
        let responseData = try await connection.exchange(requestData, timeout: timeout)
        return try JSONDecoder().decode(AhaKeyRuntimeXPCResponse.self, from: responseData)
    }
}

/// facade 连接状态（UI 可直接观察）。
public enum AhaKeyStudioRuntimeConnectionState: Equatable, Sendable {
    /// 尚未连接或连接已断开（含 Runtime 离线）。
    case offline
    /// 正在握手/拉取首屏快照。
    case connecting
    /// 在线：已握手、已取首屏，事件游标跟随中。
    case online
    /// 在线但事件回放断档，正在重取权威快照。
    case resyncing
}

/// UI 视图状态：由 facade 发布，事实源始终是 Runtime。
public struct AhaKeyStudioRuntimeViewState: Equatable, Sendable {
    public var connection: AhaKeyStudioRuntimeConnectionState
    public var snapshot: AhaKeyRuntimeSnapshot?
    /// 已跟随到的事件游标（nil = 尚未跟随任何事件）。
    public var eventCursor: AhaKeyRuntimeEventSequence?
    /// 最近一次错误描述（用于 banner；成功跟随后会清除）。
    public var lastError: String?

    public init(
        connection: AhaKeyStudioRuntimeConnectionState = .offline,
        snapshot: AhaKeyRuntimeSnapshot? = nil,
        eventCursor: AhaKeyRuntimeEventSequence? = nil,
        lastError: String? = nil
    ) {
        self.connection = connection
        self.snapshot = snapshot
        self.eventCursor = eventCursor
        self.lastError = lastError
    }
}

/// facade 会话：start 后按「handshake → snapshot → events 循环」运行，
/// 传输错误进入 offline 并按退避重连；stop/cancel 结束。事件以 view-state 流发布。
public actor AhaKeyStudioRuntimeFacade {
    /// 事件跟随一轮的批量上限（防单次回放过长阻塞 UI 发布）。
    public static let eventBatchLimit = 128

    private let transport: any AhaKeyStudioRuntimeTransport
    private let clientBuildID: String
    /// 重连退避基数（秒）；测试可注入 0 加速。
    private let reconnectBackoffBase: TimeInterval

    private var state = AhaKeyStudioRuntimeViewState()
    private var continuations: [UUID: AsyncStream<AhaKeyStudioRuntimeViewState>.Continuation] = [:]
    private var followTask: Task<Void, Never>?

    public init(
        transport: any AhaKeyStudioRuntimeTransport,
        clientBuildID: String,
        reconnectBackoffBase: TimeInterval = 1.0
    ) {
        self.transport = transport
        self.clientBuildID = clientBuildID
        self.reconnectBackoffBase = reconnectBackoffBase
    }

    /// 当前视图状态（首屏前为 offline）。
    public func currentState() -> AhaKeyStudioRuntimeViewState { state }

    /// 订阅视图状态流；订阅即收到当前值。
    public func viewStates() -> AsyncStream<AhaKeyStudioRuntimeViewState> {
        let id = UUID()
        let current = state
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// 启动跟随循环（幂等：已在运行则直接返回）。
    public func start() {
        guard followTask == nil else { return }
        followTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// 停止跟随并发布 offline。Runtime 侧已受理的 operation 不受影响（5.7 切片 4 语义）。
    public func stop() {
        followTask?.cancel()
        followTask = nil
        update { $0.connection = .offline }
    }

    // MARK: - 主循环

    private func runLoop() async {
        var consecutiveFailures = 0
        while !Task.isCancelled {
            do {
                update { $0.connection = .connecting }
                // 1) handshake
                let handshakeResponse = try await transport.exchange(
                    .handshake(.init(interfaceVersion: .current, clientBuildID: clientBuildID))
                )
                guard case .handshakeAccepted = handshakeResponse else {
                    throw AhaKeyRuntimeXPCTransportError.invalidResponse
                }
                // 2) snapshot 首屏
                try await refreshSnapshot()
                consecutiveFailures = 0
                // 3) events cursor 跟随
                try await followEvents()
            } catch is CancellationError {
                return
            } catch {
                consecutiveFailures += 1
                let message = String(describing: error)
                update {
                    $0.connection = .offline
                    $0.lastError = message
                }
                // 退避重连：base × 2^(n-1)，封顶 30s；测试注入 0 时不睡眠。
                let backoff = min(reconnectBackoffBase * pow(2.0, Double(consecutiveFailures - 1)), 30)
                if backoff > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
    }

    /// 重取权威快照并复位游标到快照的 latestEventSequence。
    private func refreshSnapshot() async throws {
        let response = try await transport.exchange(.snapshot)
        guard case .snapshot(let snapshot) = response else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
        update {
            $0.connection = .online
            $0.snapshot = snapshot
            $0.eventCursor = snapshot.latestEventSequence
            $0.lastError = nil
        }
    }

    /// 事件跟随：按 cursor 拉取回放；断档（snapshotRequired）→ 重取快照后继续。
    private func followEvents() async throws {
        while !Task.isCancelled {
            let cursor = state.eventCursor
            let response = try await transport.exchange(.events(after: cursor))
            switch response {
            case .eventReplay(.events(let events)):
                guard !events.isEmpty else { continue }
                // 单调校验：Runtime 保证递增；不递增视为协议错误，重取快照。
                var cursorValue = cursor
                var monotonic = true
                for event in events {
                    if let cursorValue, event.sequence <= cursorValue { monotonic = false; break }
                    cursorValue = event.sequence
                }
                if !monotonic {
                    try await refreshSnapshot()
                    continue
                }
                update {
                    $0.connection = .online
                    $0.eventCursor = cursorValue
                    $0.lastError = nil
                }
            case .eventReplay(.snapshotRequired):
                // 断档：回放缓冲区已溢出，必须重取权威快照。
                update { $0.connection = .resyncing }
                try await refreshSnapshot()
            case .failure:
                // Runtime 拒绝（如权限/握手失效）：重取快照重建状态。
                try await refreshSnapshot()
            default:
                throw AhaKeyRuntimeXPCTransportError.invalidResponse
            }
        }
    }

    private func update(_ mutate: (inout AhaKeyStudioRuntimeViewState) -> Void) {
        mutate(&state)
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}
