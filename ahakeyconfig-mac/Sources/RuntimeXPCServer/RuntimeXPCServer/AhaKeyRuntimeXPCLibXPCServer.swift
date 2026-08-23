import AhaKeyConfigShared
import CLibXPC
import Foundation
import Security

public enum AhaKeyRuntimeXPCLibXPCServerError: Error, Equatable, Sendable {
    case invalidCodeSigningRequirement
}

/// WBS 5.2 生产 server：macOS 12+ 使用 C libxpc。
///
/// 安全边界：
/// - 每条 accepted connection 在 resume 前绑定 peer code signing requirement（可选注入，
///   生产路径必须非 nil，由 `AhaKeyRuntimeXPCPeerPolicy.codeSigningRequirement` 提供）；
/// - 在 resume 前用 `xpc_connection_get_euid` 校验同 UID，不匹配立即 cancel；
/// - 签名不匹配的 peer 由 libxpc 直接拒绝消息投递，业务 endpoint 调用计数保持 0；
/// - 业务处理完全复用 `AhaKeyRuntimeXPCSessionEndpoint`（握手/能力/单回复/超时语义），
///   每条连接一个独立 endpoint（独立 session 状态），不复制授权逻辑；
/// - XPC 是消息导向传输，每个 dictionary 的 `payload` 字段承载一条完整 JSON wire 消息，
///   因此不再叠加字节流长度前缀 framing。
public final class AhaKeyRuntimeXPCLibXPCServer: @unchecked Sendable {
    public typealias EndpointFactory = @Sendable () -> AhaKeyRuntimeXPCSessionEndpoint

    private enum ListenerKind {
        case machService(String)
        case anonymous
    }

    private let listenerKind: ListenerKind
    private let codeSigningRequirement: String?
    private let expectedUserID: uid_t
    private let endpointFactory: EndpointFactory
    private let queue = DispatchQueue(label: "ai.ahakey.runtime.xpc.listener", qos: .utility)

    private let stateLock = NSLock()
    private var listener: xpc_connection_t?
    private var peers: [ObjectIdentifier: xpc_connection_t] = [:]
    private var stopped = false

    /// - Parameters:
    ///   - serviceName: 非 nil 时注册为当前用户域 Mach service；nil 时为 anonymous listener。
    ///   - codeSigningRequirement: 绑定到 peer 的 cs requirement 字符串；仅允许单测注入 nil
    ///     （仅校验 EUID），生产路径必须通过 peer policy 提供。
    ///   - expectedUserID: 期望的 peer EUID（生产为当前用户）。
    ///   - endpointFactory: 每条 accepted connection 一个独立 endpoint。
    public init(
        serviceName: String?,
        codeSigningRequirement: String?,
        expectedUserID: uid_t,
        endpointFactory: @escaping EndpointFactory
    ) throws {
        if let codeSigningRequirement {
            var requirement: SecRequirement?
            guard SecRequirementCreateWithString(codeSigningRequirement as CFString, [], &requirement)
                == errSecSuccess, requirement != nil
            else {
                throw AhaKeyRuntimeXPCLibXPCServerError.invalidCodeSigningRequirement
            }
        }
        if let serviceName {
            precondition(!serviceName.isEmpty && serviceName.utf8.count <= 128)
            self.listenerKind = .machService(serviceName)
        } else {
            self.listenerKind = .anonymous
        }
        self.codeSigningRequirement = codeSigningRequirement
        self.expectedUserID = expectedUserID
        self.endpointFactory = endpointFactory
    }

    deinit {
        stop()
    }

    public func start() {
        stateLock.lock()
        let alreadyStarted = listener != nil || stopped
        stateLock.unlock()
        guard !alreadyStarted else { return }

        let listenerConnection: xpc_connection_t
        switch listenerKind {
        case .machService(let name):
            listenerConnection = name.withCString { cName in
                ahk_xpc_create_mach_service_listener(cName, queue)
            }
        case .anonymous:
            listenerConnection = ahk_xpc_create_anonymous_listener(queue)
        }
        xpc_connection_set_event_handler(listenerConnection) { [weak self] event in
            self?.handleListenerEvent(event)
        }
        stateLock.lock()
        listener = listenerConnection
        stateLock.unlock()
        xpc_connection_resume(listenerConnection)
    }

    /// 仅 anonymous listener 可用：导出 endpoint 供同 UID 进程内/跨进程 client 连接。
    public var anonymousEndpoint: xpc_endpoint_t? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let listener else { return nil }
        return xpc_endpoint_create(listener)
    }

    public func stop() {
        stateLock.lock()
        stopped = true
        let currentListener = listener
        listener = nil
        let currentPeers = peers
        peers.removeAll()
        stateLock.unlock()
        if let currentListener {
            xpc_connection_cancel(currentListener)
        }
        for peer in currentPeers.values {
            xpc_connection_cancel(peer)
        }
    }

    // MARK: - Listener

    private func handleListenerEvent(_ event: xpc_object_t) {
        let eventType = xpc_get_type(event)
        if eventType == XPC_TYPE_ERROR {
            // listener 级错误（如 service 名冲突）：不崩溃、不泄漏详情，等待 stop()。
            return
        }
        guard eventType == XPC_TYPE_CONNECTION else { return }
        accept(peer: event)
    }

    private func accept(peer: xpc_connection_t) {
        // 1) 先绑定签名校验（必须在 resume 之前）；绑定失败立即 cancel。
        if let codeSigningRequirement {
            let status = codeSigningRequirement.withCString { cRequirement in
                ahk_xpc_bind_peer_code_signing_requirement(peer, cRequirement)
            }
            guard status == 0 else {
                xpc_connection_cancel(peer)
                return
            }
        }
        // 2) 同 UID 校验，失败直接 cancel，不进入任何业务处理。
        guard xpc_connection_get_euid(peer) == expectedUserID else {
            xpc_connection_cancel(peer)
            return
        }
        let context = PeerContext(endpoint: endpointFactory())
        xpc_connection_set_event_handler(peer) { [weak self] event in
            self?.handlePeerEvent(event, peer: peer, context: context)
        }
        stateLock.lock()
        let isStopped = stopped
        if !isStopped {
            peers[ObjectIdentifier(peer)] = peer
        }
        stateLock.unlock()
        guard !isStopped else {
            xpc_connection_cancel(peer)
            return
        }
        xpc_connection_resume(peer)
    }

    // MARK: - Peer

    private func handlePeerEvent(_ event: xpc_object_t, peer: xpc_connection_t, context: PeerContext) {
        let eventType = xpc_get_type(event)
        if eventType == XPC_TYPE_ERROR {
            // 包含签名不匹配导致的投递失败：只释放连接，绝不调用业务 endpoint。
            untrack(peer: peer)
            xpc_connection_cancel(peer)
            return
        }
        guard eventType == XPC_TYPE_DICTIONARY else { return }
        var payloadLength = 0
        guard let payloadPointer = xpc_dictionary_get_data(event, "payload", &payloadLength),
              payloadLength > 0
        else {
            replyError(peer: peer, reason: "missing-payload")
            return
        }
        let requestData = Data(bytes: payloadPointer, count: payloadLength)
        // 单连接单 in-flight：拥挤时明确拒绝，不建立无界队列；也因此回复无需关联 ID。
        guard context.tryBeginExchange() else {
            replyError(peer: peer, reason: "busy")
            return
        }
        let endpoint = context.endpoint
        Task {
            defer { context.endExchange() }
            do {
                let responseData = try await endpoint.exchange(requestData)
                // peer 连接是双向的：回复用全新 dictionary 直接发回（client 未使用
                // send_with_reply 语义时 xpc_dictionary_create_reply 返回 NULL）。
                let reply = xpc_dictionary_create(nil, nil, 0)
                responseData.withUnsafeBytes { buffer in
                    if let baseAddress = buffer.baseAddress, buffer.count > 0 {
                        xpc_dictionary_set_data(reply, "payload", baseAddress, buffer.count)
                    }
                }
                xpc_connection_send_message(peer, reply)
            } catch {
                replyError(peer: peer, reason: String(describing: Swift.type(of: error)))
            }
        }
    }

    private func replyError(peer: xpc_connection_t, reason: String) {
        let reply = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(reply, "error", reason)
        xpc_connection_send_message(peer, reply)
    }

    private func untrack(peer: xpc_connection_t) {
        stateLock.lock()
        peers.removeValue(forKey: ObjectIdentifier(peer))
        stateLock.unlock()
    }
}

private final class PeerContext: @unchecked Sendable {
    let endpoint: AhaKeyRuntimeXPCSessionEndpoint
    private let lock = NSLock()
    private var inFlight = false

    init(endpoint: AhaKeyRuntimeXPCSessionEndpoint) {
        self.endpoint = endpoint
    }

    func tryBeginExchange() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !inFlight else { return false }
        inFlight = true
        return true
    }

    func endExchange() {
        lock.lock()
        inFlight = false
        lock.unlock()
    }
}
