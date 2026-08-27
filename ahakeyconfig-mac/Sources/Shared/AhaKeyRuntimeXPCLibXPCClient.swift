import CLibXPC
import Foundation

/// 生产 Studio / smoke 共用的持久 libxpc client。
///
/// 与 `AhaKeyRuntimeXPCLibXPCServer` 对齐：每个 dictionary 只用 `payload` 承载一条
/// JSON wire 消息（上限 8 MiB）；单连接最多一个 in-flight，额外请求有界排队。
/// 超时、取消或 XPC 失效后不得复用该 connection，后续 exchange 会新建连接并由
/// facade 重新 handshake。
public final class AhaKeyRuntimeXPCLibXPCClient: @unchecked Sendable {
    public static let defaultMaxPayloadBytes = 8 * 1_024 * 1_024
    public static let defaultMaxQueued = 32

    private enum Target {
        case machService(String)
        case endpoint(xpc_endpoint_t)
    }

    private let target: Target
    private let requestTimeout: TimeInterval
    private let maxPayloadBytes: Int
    private let queue = DispatchQueue(label: "ai.ahakey.runtime.xpc.client", qos: .utility)
    private let lock = NSLock()
    private let gate: BoundedSerialGate
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var connection: xpc_connection_t?
    private var generation = 0
    private var inFlight: InFlight?

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
        invalidateLockedConnection()
    }

    public func exchange(_ request: AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse {
        let payload = try encoder.encode(request)
        guard payload.count <= maxPayloadBytes else {
            throw AhaKeyRuntimeXPCTransportError.requestTooLarge
        }
        return try await gate.withPermit {
            let responseData = try await self.sendOnWire(payload)
            return try self.decoder.decode(AhaKeyRuntimeXPCResponse.self, from: responseData)
        }
    }

    public func invalidate() {
        lock.lock()
        invalidateLockedConnection(resume: .failure(AhaKeyRuntimeXPCTransportError.connectionInvalid))
        lock.unlock()
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

    private func sendOnWire(_ payload: Data) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                self.lock.lock()
                let connection: xpc_connection_t
                do {
                    connection = try self.ensureConnectionLocked()
                } catch {
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                let generation = self.generation
                let timeoutWork = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    guard self.inFlight?.generation == generation else {
                        self.lock.unlock()
                        return
                    }
                    self.invalidateLockedConnection(resume: .failure(AhaKeyRuntimeXPCTransportError.requestTimedOut))
                    self.lock.unlock()
                }
                self.inFlight = InFlight(generation: generation, continuation: continuation, timeoutWork: timeoutWork)
                self.lock.unlock()
                self.queue.asyncAfter(deadline: .now() + self.requestTimeout, execute: timeoutWork)
                let message = xpc_dictionary_create(nil, nil, 0)
                payload.withUnsafeBytes { buffer in
                    if let base = buffer.baseAddress, buffer.count > 0 {
                        xpc_dictionary_set_data(message, "payload", base, buffer.count)
                    }
                }
                xpc_connection_send_message(connection, message)
            }
        } onCancel: {
            self.lock.lock()
            self.invalidateLockedConnection(resume: .failure(CancellationError()))
            self.lock.unlock()
        }
    }

    private func ensureConnectionLocked() throws -> xpc_connection_t {
        if let connection {
            return connection
        }
        generation += 1
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
            completeLocked(.success(data))
        } catch {
            if xpc_get_type(event) == XPC_TYPE_ERROR {
                invalidateLockedConnection(resume: .failure(error))
            } else {
                completeLocked(.failure(error))
            }
        }
        lock.unlock()
    }

    private func completeLocked(_ result: Result<Data, Error>) {
        guard let inFlight else { return }
        self.inFlight = nil
        inFlight.timeoutWork.cancel()
        inFlight.continuation.resume(with: result)
    }

    private func invalidateLockedConnection(resume result: Result<Data, Error>? = nil) {
        generation += 1
        if let inFlight {
            self.inFlight = nil
            inFlight.timeoutWork.cancel()
            if let result {
                inFlight.continuation.resume(with: result)
            } else {
                inFlight.continuation.resume(throwing: AhaKeyRuntimeXPCTransportError.connectionInvalid)
            }
        } else if result != nil {
            // 无 in-flight：丢弃 resume，避免对已完成请求二次 resume。
        }
        if let connection {
            self.connection = nil
            xpc_connection_cancel(connection)
        }
    }
}

private struct InFlight {
    let generation: Int
    let continuation: CheckedContinuation<Data, Error>
    let timeoutWork: DispatchWorkItem
}

/// 单 permit + 有界等待队列：超过 `maxQueued` 的并发调用立刻失败，避免无界排队打爆 server。
private final class BoundedSerialGate: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let maxQueued: Int
    private let lock = NSLock()
    private var busy = false
    private var waiters: [Waiter] = []

    init(maxQueued: Int) {
        self.maxQueued = maxQueued
    }

    func withPermit<T>(_ body: () async throws -> T) async throws -> T {
        try await acquire()
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
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
                waiters.append(Waiter(id: waiterID, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == waiterID }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
                return
            }
            lock.unlock()
        }
    }

    private func release() {
        lock.lock()
        if waiters.isEmpty {
            busy = false
            lock.unlock()
            return
        }
        let next = waiters.removeFirst()
        lock.unlock()
        next.continuation.resume()
    }
}
