import CLibXPC
import Foundation

/// 生产 Studio / smoke 共用的持久 libxpc client。
///
/// 与 `AhaKeyRuntimeXPCLibXPCServer` 对齐：每个 dictionary 只用 `payload` 承载一条
/// JSON wire 消息（上限 8 MiB）；单连接最多一个 in-flight，额外请求有界排队。
/// 超时、取消或 XPC error 会使当前代际失效：旧代际排队的业务请求必须失败，
/// 不得在新 connection 上、handshakeAccepted 之前发出；非幂等 apply 不得跨代际重放。
public final class AhaKeyRuntimeXPCLibXPCClient: @unchecked Sendable {
    public static let defaultMaxPayloadBytes = 8 * 1_024 * 1_024
    public static let defaultMaxQueued = 32

    enum TestBarrier: Equatable {
        case beforeEnqueueWaiter
        case afterEnqueueWaiter
        case afterDequeueBeforeResume
        case beforeRegisterInFlight
    }

    private enum Target {
        case machService(String)
        case endpoint(xpc_endpoint_t)
    }

    private struct DroppedState {
        var inFlight: InFlight?
        var waiters: [GateWaiter]
        var connection: xpc_connection_t?
    }

    private let target: Target
    private let requestTimeout: TimeInterval
    private let maxPayloadBytes: Int
    private let queue = DispatchQueue(label: "ai.ahakey.runtime.xpc.client", qos: .utility)
    private let lock = NSLock()
    private let gate: BoundedSerialGate

    private var connection: xpc_connection_t?
    /// 当前连接代际。从 1 起；invalidate 时递增。新 connection 沿用该代际直到再次失效。
    private var generation = 1
    private var handshakeAccepted = false
    private var inFlight: InFlight?

    var testBarrierHandler: ((TestBarrier, @escaping () -> Void) -> Void)?

    public init(
        machServiceName: String,
        requestTimeout: TimeInterval = 10,
        maxPayloadBytes: Int = AhaKeyRuntimeXPCLibXPCClient.defaultMaxPayloadBytes,
        maxQueued: Int = AhaKeyRuntimeXPCLibXPCClient.defaultMaxQueued
    ) {
        precondition(!machServiceName.isEmpty)
        precondition(requestTimeout > 0)
        precondition(maxPayloadBytes > 0)
        precondition(maxQueued > 0)
        self.target = .machService(machServiceName)
        self.requestTimeout = requestTimeout
        self.maxPayloadBytes = maxPayloadBytes
        self.gate = BoundedSerialGate(maxQueued: maxQueued)
    }

    public init(
        endpoint: xpc_endpoint_t,
        requestTimeout: TimeInterval = 10,
        maxPayloadBytes: Int = AhaKeyRuntimeXPCLibXPCClient.defaultMaxPayloadBytes,
        maxQueued: Int = AhaKeyRuntimeXPCLibXPCClient.defaultMaxQueued
    ) {
        precondition(requestTimeout > 0)
        precondition(maxPayloadBytes > 0)
        precondition(maxQueued > 0)
        self.target = .endpoint(endpoint)
        self.requestTimeout = requestTimeout
        self.maxPayloadBytes = maxPayloadBytes
        self.gate = BoundedSerialGate(maxQueued: maxQueued)
    }

    deinit {
        lock.lock()
        let dropped = dropConnectionLocked()
        lock.unlock()
        resumeDropped(dropped, inFlightResult: .failure(AhaKeyRuntimeXPCTransportError.connectionInvalid))
    }

    public func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        let token = ExchangeToken()
        let cancelCurrent = { [weak self] in
            token.markCancelled()
            self?.handleCancel(token)
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await self.performExchange(request, token: token, cancelCurrent: cancelCurrent)
        } onCancel: {
            cancelCurrent()
        }
    }

    public func invalidate() {
        lock.lock()
        let dropped = dropConnectionLocked()
        lock.unlock()
        resumeDropped(dropped, inFlightResult: .failure(AhaKeyRuntimeXPCTransportError.connectionInvalid))
    }

    /// 解析 server 回复（单测覆盖 missing / oversize / error dictionary / XPC error）。
    static func parsePeerEvent(_ event: xpc_object_t, maxPayloadBytes: Int) throws -> Data {
        let eventType = xpc_get_type(event)
        if eventType == XPC_TYPE_ERROR {
            throw AhaKeyRuntimeXPCTransportError.connectionInvalid
        }
        guard eventType == XPC_TYPE_DICTIONARY else {
            throw AhaKeyRuntimeXPCTransportError.invalidResponse
        }
        if let reason = xpc_dictionary_get_string(event, "error") {
            throw AhaKeyRuntimeXPCTransportError.peerError(String(cString: reason))
        }
        var payloadLength = 0
        guard let pointer = xpc_dictionary_get_data(event, "payload", &payloadLength), payloadLength > 0 else {
            throw AhaKeyRuntimeXPCTransportError.missingPayload
        }
        guard payloadLength <= maxPayloadBytes else {
            throw AhaKeyRuntimeXPCTransportError.payloadTooLarge
        }
        return Data(bytes: pointer, count: payloadLength)
    }

    private func performExchange(
        _ request: AhaKeyRuntimeXPCRequest,
        token: ExchangeToken,
        cancelCurrent: @escaping () -> Void
    ) async throws -> AhaKeyRuntimeXPCResponse {
        lock.lock()
        if token.isCancelled || Task.isCancelled {
            lock.unlock()
            throw CancellationError()
        }
        let capturedGeneration = generation
        lock.unlock()

        let encoder = JSONEncoder()
        let payload = try encoder.encode(request)
        guard payload.count <= maxPayloadBytes else {
            throw AhaKeyRuntimeXPCTransportError.requestTooLarge
        }

        let isHandshake: Bool
        if case .handshake = request {
            isHandshake = true
        } else {
            isHandshake = false
        }

        return try await gate.withPermit(token: token, barrier: { [weak self] barrier, barrierToken in
            self?.testBarrierHandler?(barrier) {
                barrierToken.markCancelled()
                self?.handleCancel(barrierToken)
            }
        }) {
            self.testBarrierHandler?(.beforeRegisterInFlight, cancelCurrent)
            let responseData = try await self.sendOnWire(
                payload,
                token: token,
                capturedGeneration: capturedGeneration,
                isHandshake: isHandshake
            )
            let decoder = JSONDecoder()
            let response = try decoder.decode(AhaKeyRuntimeXPCResponse.self, from: responseData)
            if isHandshake {
                self.lock.lock()
                if self.generation == capturedGeneration {
                    self.handshakeAccepted = true
                }
                self.lock.unlock()
            }
            return response
        }
    }

    private func sendOnWire(
        _ payload: Data,
        token: ExchangeToken,
        capturedGeneration: Int,
        isHandshake: Bool
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.lock.lock()
            if token.isCancelled || Task.isCancelled {
                self.lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            if self.generation != capturedGeneration {
                self.lock.unlock()
                continuation.resume(throwing: AhaKeyRuntimeXPCTransportError.connectionInvalid)
                return
            }
            if !isHandshake && !self.handshakeAccepted {
                self.lock.unlock()
                continuation.resume(throwing: AhaKeyRuntimeXPCTransportError.handshakeRequired)
                return
            }
            let connection: xpc_connection_t
            do {
                connection = try self.ensureConnectionLocked()
            } catch {
                self.lock.unlock()
                continuation.resume(throwing: error)
                return
            }
            if token.isCancelled || Task.isCancelled || self.generation != capturedGeneration {
                self.lock.unlock()
                continuation.resume(
                    throwing: (token.isCancelled || Task.isCancelled)
                        ? CancellationError()
                        : AhaKeyRuntimeXPCTransportError.connectionInvalid
                )
                return
            }
            let generation = self.generation
            let timeoutWork = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lock.lock()
                guard self.inFlight?.generation == generation, self.inFlight?.token.id == token.id else {
                    self.lock.unlock()
                    return
                }
                let dropped = self.dropConnectionLocked()
                self.lock.unlock()
                self.resumeDropped(
                    dropped,
                    inFlightResult: .failure(AhaKeyRuntimeXPCTransportError.requestTimedOut)
                )
            }
            self.inFlight = InFlight(
                generation: generation,
                token: token,
                continuation: continuation,
                timeoutWork: timeoutWork
            )
            if token.isCancelled || Task.isCancelled {
                self.inFlight = nil
                timeoutWork.cancel()
                self.lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            let message = xpc_dictionary_create(nil, nil, 0)
            payload.withUnsafeBytes { buffer in
                if let base = buffer.baseAddress, buffer.count > 0 {
                    xpc_dictionary_set_data(message, "payload", base, buffer.count)
                }
            }
            xpc_connection_send_message(connection, message)
            self.lock.unlock()
            self.queue.asyncAfter(deadline: .now() + self.requestTimeout, execute: timeoutWork)
        }
    }

    private func ensureConnectionLocked() throws -> xpc_connection_t {
        if let connection {
            return connection
        }
        handshakeAccepted = false
        let capturedGeneration = generation
        let connection: xpc_connection_t
        switch target {
        case .machService(let name):
            connection = name.withCString { cName in
                xpc_connection_create_mach_service(cName, queue, 0)
            }
        case .endpoint(let endpoint):
            connection = xpc_connection_create_from_endpoint(endpoint)
        }
        xpc_connection_set_event_handler(connection) { [weak self] event in
            self?.handlePeerEvent(event, generation: capturedGeneration)
        }
        self.connection = connection
        xpc_connection_resume(connection)
        return connection
    }

    private func handlePeerEvent(_ event: xpc_object_t, generation: Int) {
        lock.lock()
        guard self.generation == generation else {
            lock.unlock()
            return
        }
        do {
            let data = try Self.parsePeerEvent(event, maxPayloadBytes: maxPayloadBytes)
            guard let inFlight else {
                lock.unlock()
                return
            }
            self.inFlight = nil
            inFlight.timeoutWork.cancel()
            lock.unlock()
            inFlight.continuation.resume(returning: data)
        } catch {
            if xpc_get_type(event) == XPC_TYPE_ERROR {
                let dropped = dropConnectionLocked()
                lock.unlock()
                resumeDropped(dropped, inFlightResult: .failure(error))
            } else {
                guard let inFlight else {
                    lock.unlock()
                    return
                }
                self.inFlight = nil
                inFlight.timeoutWork.cancel()
                lock.unlock()
                inFlight.continuation.resume(throwing: error)
            }
        }
    }

    private func handleCancel(_ token: ExchangeToken) {
        lock.lock()
        if inFlight?.token.id == token.id {
            let dropped = dropConnectionLocked()
            lock.unlock()
            resumeDropped(dropped, inFlightResult: .failure(CancellationError()))
            return
        }
        lock.unlock()
        if let waiter = gate.removeWaiter(id: token.id) {
            waiter.resume(throwing: CancellationError())
        }
    }

    private func dropConnectionLocked() -> DroppedState {
        generation += 1
        handshakeAccepted = false
        let inFlight = self.inFlight
        self.inFlight = nil
        inFlight?.timeoutWork.cancel()
        let waiters = gate.drainWaiters()
        let connection = self.connection
        self.connection = nil
        return DroppedState(inFlight: inFlight, waiters: waiters, connection: connection)
    }

    private func resumeDropped(_ dropped: DroppedState, inFlightResult: Result<Data, Error>) {
        if let connection = dropped.connection {
            xpc_connection_cancel(connection)
        }
        if let inFlight = dropped.inFlight {
            inFlight.continuation.resume(with: inFlightResult)
        }
        for waiter in dropped.waiters {
            waiter.resume(throwing: AhaKeyRuntimeXPCTransportError.connectionInvalid)
        }
    }
}

private final class ExchangeToken: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var cancelled = false

    func markCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private struct InFlight {
    let generation: Int
    let token: ExchangeToken
    let continuation: CheckedContinuation<Data, Error>
    let timeoutWork: DispatchWorkItem
}

private struct GateWaiter {
    let id: UUID
    let token: ExchangeToken
    let continuation: CheckedContinuation<Void, Error>

    func resume(throwing error: Error) {
        continuation.resume(throwing: error)
    }

    func resume() {
        continuation.resume()
    }
}

/// 单 permit + 有界等待队列：超过 `maxQueued` 的并发调用立刻失败，避免无界排队打爆 server。
private final class BoundedSerialGate: @unchecked Sendable {
    private let maxQueued: Int
    private let lock = NSLock()
    private var busy = false
    private var waiters: [GateWaiter] = []

    init(maxQueued: Int) {
        self.maxQueued = maxQueued
    }

    func withPermit<T>(
        token: ExchangeToken,
        barrier: @escaping (AhaKeyRuntimeXPCLibXPCClient.TestBarrier, ExchangeToken) -> Void,
        _ body: () async throws -> T
    ) async throws -> T {
        try await acquire(token: token, barrier: barrier)
        do {
            let value = try await body()
            release(barrier: barrier)
            return value
        } catch {
            release(barrier: barrier)
            throw error
        }
    }

    func removeWaiter(id: UUID) -> GateWaiter? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
        return waiters.remove(at: index)
    }

    func drainWaiters() -> [GateWaiter] {
        lock.lock()
        let stranded = waiters
        waiters.removeAll()
        lock.unlock()
        return stranded
    }

    private func acquire(
        token: ExchangeToken,
        barrier: @escaping (AhaKeyRuntimeXPCLibXPCClient.TestBarrier, ExchangeToken) -> Void
    ) async throws {
        barrier(.beforeEnqueueWaiter, token)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if token.isCancelled || Task.isCancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            if !busy {
                busy = true
                lock.unlock()
                continuation.resume()
                return
            }
            if waiters.count >= maxQueued {
                lock.unlock()
                continuation.resume(throwing: AhaKeyRuntimeXPCTransportError.queueSaturated)
                return
            }
            waiters.append(GateWaiter(id: token.id, token: token, continuation: continuation))
            lock.unlock()
            barrier(.afterEnqueueWaiter, token)
        }
    }

    private func release(barrier: @escaping (AhaKeyRuntimeXPCLibXPCClient.TestBarrier, ExchangeToken) -> Void) {
        while true {
            lock.lock()
            guard !waiters.isEmpty else {
                busy = false
                lock.unlock()
                return
            }
            let next = waiters.removeFirst()
            lock.unlock()
            barrier(.afterDequeueBeforeResume, next.token)
            if next.token.isCancelled {
                next.resume(throwing: CancellationError())
                continue
            }
            next.resume()
            return
        }
    }
}
