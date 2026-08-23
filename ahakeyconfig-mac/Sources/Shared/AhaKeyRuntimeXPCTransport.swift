import Foundation

@objc public protocol AhaKeyRuntimeXPCServiceProtocol {
    func exchange(_ request: Data, reply: @escaping (Data?, NSError?) -> Void)
}

public enum AhaKeyRuntimeXPCTransportError: Error, Sendable {
    case requestTooLarge
    case responseTooLarge
    case invalidResponse
    case requestTimedOut
}

public actor AhaKeyRuntimeXPCSessionEndpoint {
    public typealias Handler = @Sendable (AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse

    private let maximumMessageBytes: Int
    private let serverHandshake: AhaKeyRuntimeXPCServerHandshake
    private let handler: Handler
    private var session = AhaKeyRuntimeXPCSession()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        maximumMessageBytes: Int = 8 * 1_024 * 1_024,
        serverHandshake: AhaKeyRuntimeXPCServerHandshake,
        handler: @escaping Handler
    ) {
        precondition(maximumMessageBytes > 0)
        self.maximumMessageBytes = maximumMessageBytes
        self.serverHandshake = serverHandshake
        self.handler = handler
    }

    public func exchange(_ requestData: Data) async throws -> Data {
        guard requestData.count <= maximumMessageBytes else {
            throw AhaKeyRuntimeXPCTransportError.requestTooLarge
        }
        let request = try decoder.decode(AhaKeyRuntimeXPCRequest.self, from: requestData)
        _ = try session.accept(request)
        let response: AhaKeyRuntimeXPCResponse
        if case .handshake = request {
            response = .handshakeAccepted(serverHandshake)
        } else {
            response = try await handler(request)
        }
        let encoded = try encoder.encode(response)
        guard encoded.count <= maximumMessageBytes else {
            throw AhaKeyRuntimeXPCTransportError.responseTooLarge
        }
        return encoded
    }
}

public final class AhaKeyRuntimeXPCServiceBridge: NSObject, AhaKeyRuntimeXPCServiceProtocol {
    private let endpoint: AhaKeyRuntimeXPCSessionEndpoint

    public init(endpoint: AhaKeyRuntimeXPCSessionEndpoint) {
        self.endpoint = endpoint
    }

    public func exchange(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {
        Task {
            do {
                reply(try await endpoint.exchange(request), nil)
            } catch {
                reply(nil, error as NSError)
            }
        }
    }
}

public final class AhaKeyRuntimeXPCConnectionTransport: @unchecked Sendable {
    private let connection: NSXPCConnection

    public convenience init(machServiceName: String) {
        self.init(connection: NSXPCConnection(machServiceName: machServiceName))
    }

    init(connection: NSXPCConnection) {
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: AhaKeyRuntimeXPCServiceProtocol.self)
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    public func exchange(_ request: Data, timeout: TimeInterval = 10) async throws -> Data {
        precondition(timeout > 0)
        let replyGate = AhaKeyRuntimeXPCReplyGate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                replyGate.install(continuation)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    guard replyGate.resolve(.failure(AhaKeyRuntimeXPCTransportError.requestTimedOut)) else {
                        return
                    }
                    self.connection.invalidate()
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    _ = replyGate.resolve(.failure(error))
                }
                guard let service = proxy as? AhaKeyRuntimeXPCServiceProtocol else {
                    _ = replyGate.resolve(.failure(AhaKeyRuntimeXPCTransportError.invalidResponse))
                    return
                }
                service.exchange(request) { data, error in
                    if let error {
                        _ = replyGate.resolve(.failure(error))
                    } else if let data {
                        _ = replyGate.resolve(.success(data))
                    } else {
                        _ = replyGate.resolve(.failure(AhaKeyRuntimeXPCTransportError.invalidResponse))
                    }
                }
            }
        } onCancel: {
            guard replyGate.resolve(.failure(CancellationError())) else { return }
            connection.invalidate()
        }
    }
}

private final class AhaKeyRuntimeXPCReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var pendingResult: Result<Data, Error>?
    private var completed = false

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    @discardableResult
    func resolve(_ result: Result<Data, Error>) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return true
        }
        guard pendingResult == nil else {
            lock.unlock()
            return false
        }
        pendingResult = result
        lock.unlock()
        return true
    }
}
