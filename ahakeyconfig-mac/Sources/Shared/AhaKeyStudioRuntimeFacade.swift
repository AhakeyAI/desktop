import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

// MARK: - WBS 5.7 切片 1：Studio Runtime client/facade
//
// Studio 侧唯一 Runtime 事实源入口：handshake → snapshot 首屏 → events cursor
// 跟随（断档 snapshotRequired → 重取 snapshot）→ 离线/重连状态机。
// 事实源永远在 Runtime；本 facade 不复制设备状态，只保存「最近一次快照 + 事件游标」
// 作为 UI 派生输入。传输层可注入（生产 = XPC，测试 = 内存假实现）。

/// Studio facade 的请求/响应传输抽象。生产实现走 `AhaKeyRuntimeXPCLibXPCClient`。
public protocol AhaKeyStudioRuntimeTransport: Sendable {
    func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse
}

/// 生产 XPC 传输：libxpc dictionary `payload` JSON（与 Agent server / 5.2 smoke 同一 wire）。
public struct AhaKeyStudioRuntimeXPCTransport: AhaKeyStudioRuntimeTransport {
    private let client: AhaKeyRuntimeXPCLibXPCClient

    public init(machServiceName: String = "lab.jawa.ahakeyconfig.runtime", timeout: TimeInterval = 10) {
        self.client = AhaKeyRuntimeXPCLibXPCClient(machServiceName: machServiceName, requestTimeout: timeout)
    }

    public init(client: AhaKeyRuntimeXPCLibXPCClient) {
        self.client = client
    }

    public func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        try await client.exchange(request)
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
    /// 最近一次 apply 受理的 operationID（供 UI 关联 snapshot.operations 进度）。
    public var lastApplyOperationID: AhaKeyRuntimeOperationID?

    public init(
        connection: AhaKeyStudioRuntimeConnectionState = .offline,
        snapshot: AhaKeyRuntimeSnapshot? = nil,
        eventCursor: AhaKeyRuntimeEventSequence? = nil,
        lastError: String? = nil,
        lastApplyOperationID: AhaKeyRuntimeOperationID? = nil
    ) {
        self.connection = connection
        self.snapshot = snapshot
        self.eventCursor = eventCursor
        self.lastError = lastError
        self.lastApplyOperationID = lastApplyOperationID
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
    /// 空事件批后的空闲间隔（秒；服务端 long-poll 已兜底，此处防紧循环）。测试注入 0。
    private let idlePollInterval: TimeInterval
    /// 资源加载器：读本地 GIF + 计算摘要/帧数/尺寸；测试注入假实现。
    private let resourceLoader: any AhaKeyStudioResourceLoader

    private var state = AhaKeyStudioRuntimeViewState()
    private var continuations: [UUID: AsyncStream<AhaKeyStudioRuntimeViewState>.Continuation] = [:]
    private var followTask: Task<Void, Never>?

    /// 测试 seam：每次状态发布时在 update 内同步回调（actor 上）。
    /// 用于确定性断言瞬态（如 resyncing/offline），不依赖 AsyncStream 订阅时序。
    private var publishHookForTesting: (@Sendable (AhaKeyStudioRuntimeViewState) -> Void)?

    /// 测试 seam 注入（跨 actor 写入经方法完成）。
    func setPublishHookForTesting(_ hook: (@Sendable (AhaKeyStudioRuntimeViewState) -> Void)?) {
        publishHookForTesting = hook
    }

    public init(
        transport: any AhaKeyStudioRuntimeTransport,
        clientBuildID: String,
        reconnectBackoffBase: TimeInterval = 1.0,
        idlePollInterval: TimeInterval = 0.5,
        resourceLoader: any AhaKeyStudioResourceLoader = AhaKeyStudioGIFResourceLoader()
    ) {
        self.transport = transport
        self.clientBuildID = clientBuildID
        self.reconnectBackoffBase = reconnectBackoffBase
        self.idlePollInterval = idlePollInterval
        self.resourceLoader = resourceLoader
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

    // MARK: - 操作请求（直接通过 transport，不经过事件循环）

    /// 预上传资源到 Runtime Store（XPC `ingestResources`）。
    public func ingestResources(_ items: [AhaKeyXPCResourceIngestionItem]) async throws {
        let response = try await transport.exchange(.ingestResources(items))
        guard case .resourcesIngested = response else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
    }

    /// 提交配置包并返回 operation ID。调用方应先 `ingestResources` 再 `apply`。
    public func apply(_ package: AhaKeyConfigurationPackage) async throws -> AhaKeyRuntimeOperationID {
        let response = try await transport.exchange(.apply(package))
        guard case .operationAccepted(let operationID) = response else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
        return operationID
    }

    /// 请求取消指定 operation。
    public func requestCancellation(of operationID: AhaKeyRuntimeOperationID) async throws -> AhaKeyRuntimeCancellationDisposition {
        let response = try await transport.exchange(.requestCancellation(operationID))
        guard case .cancellation(let disposition) = response else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
        return disposition
    }

    /// 更新 Runtime policy。
    public func updatePolicy(_ policy: AhaKeyRuntimePolicy) async throws {
        let response = try await transport.exchange(.updatePolicy(policy))
        guard case .policyUpdated = response else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
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
    /// 纪律（WBS-5.7 R1）：
    /// - 非空事件批：先校验单调，再重取权威 snapshot，snapshot 与 cursor 同一次 update 原子发布
    ///   （禁止只推进 cursor 不更新 snapshot）。
    /// - 空批：服务端 long-poll 已兜底；此处再加可注入 idle 间隔，绝不紧循环。
    private func followEvents() async throws {
        while !Task.isCancelled {
            let cursor = state.eventCursor
            let response = try await transport.exchange(.events(after: cursor))
            switch response {
            case .eventReplay(.events(let events)):
                if events.isEmpty {
                    if idlePollInterval > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(idlePollInterval * 1_000_000_000))
                    } else {
                        await Task.yield()
                    }
                    continue
                }
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
                // 非空事件后重取权威 snapshot（设备/operation/policy 等 payload 归并以服务端快照为准），
                // snapshot 与事件游标在同一次 update 中原子发布。
                let snapshotResponse = try await transport.exchange(.snapshot)
                guard case .snapshot(let snapshot) = snapshotResponse else {
                    throw AhaKeyRuntimeXPCTransportError.invalidResponse
                }
                let followedCursor = cursorValue ?? snapshot.latestEventSequence
                update {
                    $0.connection = .online
                    $0.snapshot = snapshot
                    $0.eventCursor = max(followedCursor, snapshot.latestEventSequence)
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
        publishHookForTesting?(state)
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}

// MARK: - WBS 5.7 切片 2：apply 入口（ingestResources → apply）与取消

/// facade apply 的资源加载结果：GIF 源图字节 + 内容摘要 + 申报复核所需的帧数/尺寸。
/// 冻结契约（AcceptanceValidator）：CAS 内容是源 GIF，mediaType "gif"，
/// sha256/byteCount 对源数据；RGB565 编码是 Runtime/Agent 侧职责，客户端不预编码。
public struct AhaKeyStudioLoadedResource: Equatable, Sendable {
    public let data: Data
    public let sha256: AhaKeySHA256Digest
    public let frameCount: Int
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(
        data: Data,
        sha256: AhaKeySHA256Digest,
        frameCount: Int,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.data = data
        self.sha256 = sha256
        self.frameCount = frameCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// 资源加载抽象（可注入测试替身）。
public protocol AhaKeyStudioResourceLoader: Sendable {
    func load(from url: URL) throws -> AhaKeyStudioLoadedResource
}

/// 生产加载器：读 GIF 源字节，SHA-256 摘要，CGImageSource 复核帧数与首帧尺寸。
public struct AhaKeyStudioGIFResourceLoader: AhaKeyStudioResourceLoader {
    public enum LoadError: Error, Equatable {
        case unreadable
        case notAnImage
    }

    public init() {}

    public func load(from url: URL) throws -> AhaKeyStudioLoadedResource {
        guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw LoadError.notAnImage
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.notAnImage
        }
        var hasher = SHA256()
        hasher.update(data: data)
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return try AhaKeyStudioLoadedResource(
            data: data,
            sha256: AhaKeySHA256Digest(hex),
            frameCount: frameCount,
            pixelWidth: first.width,
            pixelHeight: first.height
        )
    }
}

/// apply 路径错误：资源缺失 / 元数据不符 / ingest 被拒 / apply 被拒 / 取消被拒，各自可区分。
public enum AhaKeyStudioApplyError: Error, Equatable {
    /// 本地资源读不出或不是可解析图片。
    case resourceLoadFailed(identifier: String, path: String, reason: String)
    /// 申报元数据（帧数/宽高）与实际文件不符。
    case resourceMetadataMismatch(identifier: String)
    /// Runtime 拒绝 ingest（附 failure code）。
    case ingestRejected(AhaKeyRuntimeEventCode)
    /// Runtime 拒绝 apply（附 failure code）。
    case applyRejected(AhaKeyRuntimeEventCode)
    /// Runtime 拒绝取消请求（附 failure code）。
    case cancellationRejected(AhaKeyRuntimeEventCode)
    /// Runtime 返回了与请求不匹配的响应。
    case unexpectedResponse
}

extension AhaKeyStudioRuntimeFacade {
    /// Studio 提交入口：组装 → 读资源（锁外）→ ingestResources → apply。
    /// 返回 Runtime 受理的 operationID；进度经 snapshot.operations / operationChanged 事件跟随。
    public func apply(
        modes: [AhaKeyStudioModeInput],
        targetDeviceID: AhaKeyRuntimeDeviceID,
        baseRevision: AhaKeyConfigurationRevision
    ) async throws -> AhaKeyRuntimeOperationID {
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: modes)
        // 文件读取与摘要在 actor 锁外做（nonisolated），不阻塞状态发布。
        let prepared = try await prepareResources(assembled.resources)
        let gifMediaType = try AhaKeyMediaType("gif")
        let packageResources = prepared.map {
            AhaKeyConfigurationResource(
                logicalIdentifier: $0.input.logicalIdentifier,
                sha256: $0.loaded.sha256,
                byteCount: UInt64($0.loaded.data.count),
                mediaType: gifMediaType
            )
        }
        let package = try AhaKeyConfigurationPackage(
            targetDeviceID: targetDeviceID,
            baseRevision: baseRevision,
            desiredConfiguration: assembled.configuration.canonicalData(),
            resources: packageResources
        )

        if !prepared.isEmpty {
            let items = prepared.map {
                AhaKeyXPCResourceIngestionItem(
                    logicalIdentifier: $0.input.logicalIdentifier,
                    sha256: $0.loaded.sha256,
                    byteCount: UInt64($0.loaded.data.count),
                    data: $0.loaded.data
                )
            }
            let ingestResponse = try await transport.exchange(.ingestResources(items))
            switch ingestResponse {
            case .resourcesIngested:
                break
            case .failure(let code):
                throw AhaKeyStudioApplyError.ingestRejected(code)
            default:
                throw AhaKeyStudioApplyError.unexpectedResponse
            }
        }

        let applyResponse = try await transport.exchange(.apply(package))
        switch applyResponse {
        case .operationAccepted(let operationID):
            update { $0.lastApplyOperationID = operationID }
            return operationID
        case .failure(let code):
            throw AhaKeyStudioApplyError.applyRejected(code)
        default:
            throw AhaKeyStudioApplyError.unexpectedResponse
        }
    }

    /// 取消已受理的 operation：透传 .requestCancellation。
    public func requestCancellation(
        _ operationID: AhaKeyRuntimeOperationID
    ) async throws -> AhaKeyRuntimeCancellationDisposition {
        let response = try await transport.exchange(.requestCancellation(operationID))
        switch response {
        case .cancellation(let disposition):
            return disposition
        case .failure(let code):
            throw AhaKeyStudioApplyError.cancellationRejected(code)
        default:
            throw AhaKeyStudioApplyError.unexpectedResponse
        }
    }

    /// 锁外资源准备：读文件 + 复核申报元数据（帧数/宽高与实际一致，否则 fail-fast）。
    private nonisolated func prepareResources(
        _ inputs: [AhaKeyStudioResourceInput]
    ) async throws -> [(input: AhaKeyStudioResourceInput, loaded: AhaKeyStudioLoadedResource)] {
        var prepared: [(AhaKeyStudioResourceInput, AhaKeyStudioLoadedResource)] = []
        prepared.reserveCapacity(inputs.count)
        for input in inputs {
            let loaded: AhaKeyStudioLoadedResource
            do {
                loaded = try await resourceLoader.load(from: input.fileURL)
            } catch {
                throw AhaKeyStudioApplyError.resourceLoadFailed(
                    identifier: input.logicalIdentifier.rawValue,
                    path: input.fileURL.path,
                    reason: String(describing: error)
                )
            }
            guard loaded.frameCount == input.declaredFrameCount,
                  loaded.pixelWidth == input.pixelWidth,
                  loaded.pixelHeight == input.pixelHeight else {
                throw AhaKeyStudioApplyError.resourceMetadataMismatch(
                    identifier: input.logicalIdentifier.rawValue
                )
            }
            prepared.append((input, loaded))
        }
        return prepared
    }
}
