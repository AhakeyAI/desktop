import CLibXPC
import XCTest
@testable import AhaKeyConfigShared
@testable import RuntimeXPCServer

final class AhaKeyRuntimeXPCLibXPCClientTests: XCTestCase {
    private func handshake() -> AhaKeyRuntimeXPCServerHandshake {
        AhaKeyRuntimeXPCServerHandshake(
            runtimeVersion: .development,
            interfaceVersion: .current,
            supportedConfigurationSchemaVersions: [1],
            capabilities: [.snapshot, .eventReplay]
        )
    }

    private func snapshot(_ sequence: UInt64 = 1) -> AhaKeyRuntimeSnapshot {
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

    private func makeServer(
        delayNanoseconds: UInt64 = 0,
        maxConcurrent: ConcurrentCounter? = nil,
        handler: (@Sendable (AhaKeyRuntimeXPCRequest) async throws -> AhaKeyRuntimeXPCResponse)? = nil
    ) throws -> AhaKeyRuntimeXPCLibXPCServer {
        let handshake = handshake()
        let snapshot = snapshot()
        return try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid()
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: handshake) { request in
                maxConcurrent?.enter()
                defer { maxConcurrent?.leave() }
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                if let handler {
                    return try await handler(request)
                }
                if case .snapshot = request {
                    return .snapshot(snapshot)
                }
                return .policyUpdated
            }
        }
    }

    private func startedClient(
        server: AhaKeyRuntimeXPCLibXPCServer,
        timeout: TimeInterval = 2,
        maxQueued: Int = 32
    ) throws -> AhaKeyRuntimeXPCLibXPCClient {
        server.start()
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        return AhaKeyRuntimeXPCLibXPCClient(endpoint: endpoint, requestTimeout: timeout, maxQueued: maxQueued)
    }

    func testStudioProductionTransportHandshakeThenSnapshotAgainstLibXPC() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = try startedClient(server: server)
        let transport = AhaKeyStudioRuntimeXPCTransport(client: client)
        let accepted = try await transport.exchange(
            .handshake(.init(interfaceVersion: .current, clientBuildID: "studio-libxpc-test"))
        )
        guard case .handshakeAccepted = accepted else {
            return XCTFail("handshake must be accepted over libxpc payload JSON")
        }
        let screen = try await transport.exchange(.snapshot)
        guard case .snapshot(let snapshot) = screen else {
            return XCTFail("snapshot must decode from libxpc payload")
        }
        XCTAssertEqual(snapshot.latestEventSequence, .init(1))
    }

    func testConcurrentExchangesSerializeWithoutServerBusy() async throws {
        let concurrent = ConcurrentCounter()
        let server = try makeServer(delayNanoseconds: 80_000_000, maxConcurrent: concurrent)
        defer { server.stop() }
        let client = try startedClient(server: server)
        try await handshakeOn(client)
        async let first = client.exchange(.snapshot)
        async let second = client.exchange(.snapshot)
        let results = try await [first, second]
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(concurrent.maxValue, 1, "client must keep a single in-flight so server never returns busy")
        XCTAssertFalse(concurrent.sawBusy)
    }

    func testQueueSaturationFailsInsteadOfUnboundedWait() async throws {
        let server = try makeServer(delayNanoseconds: 200_000_000)
        defer { server.stop() }
        let client = try startedClient(server: server, maxQueued: 1)
        try await handshakeOn(client)
        let taskA = Task { try await client.exchange(.snapshot) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let taskB = Task { try await client.exchange(.snapshot) }
        try await Task.sleep(nanoseconds: 20_000_000)
        do {
            _ = try await client.exchange(.snapshot)
            XCTFail("third concurrent request should saturate the bounded queue")
        } catch AhaKeyRuntimeXPCTransportError.queueSaturated {
            // Expected.
        }
        _ = try await taskA.value
        _ = try await taskB.value
    }

    func testRequestTimeoutInvalidatesConnection() async throws {
        let server = try makeServer(delayNanoseconds: 2_000_000_000)
        defer { server.stop() }
        let client = try startedClient(server: server, timeout: 0.15)
        try await handshakeOn(client)
        do {
            _ = try await client.exchange(.snapshot)
            XCTFail("slow server must time out")
        } catch AhaKeyRuntimeXPCTransportError.requestTimedOut {
            // Expected.
        }
    }

    func testCancellationInvalidatesInFlightRequest() async throws {
        let server = try makeServer(delayNanoseconds: 2_000_000_000)
        defer { server.stop() }
        let client = try startedClient(server: server, timeout: 5)
        try await handshakeOn(client)
        let task = Task { try await client.exchange(.snapshot) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled in-flight exchange must fail")
        } catch is CancellationError {
            // Expected.
        } catch AhaKeyRuntimeXPCTransportError.connectionInvalid {
            // 取消路径会 invalidate connection，允许映射为失效。
        }
    }

    func testParsePeerErrorMissingAndOversizePayload() throws {
        let errorDict = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(errorDict, "error", "busy")
        XCTAssertThrowsError(try AhaKeyRuntimeXPCLibXPCClient.parsePeerEvent(errorDict, maxPayloadBytes: 8)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeXPCTransportError, .peerError("busy"))
        }

        let missing = xpc_dictionary_create(nil, nil, 0)
        XCTAssertThrowsError(try AhaKeyRuntimeXPCLibXPCClient.parsePeerEvent(missing, maxPayloadBytes: 8)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeXPCTransportError, .missingPayload)
        }

        let oversized = xpc_dictionary_create(nil, nil, 0)
        let blob = Data(repeating: 1, count: 16)
        blob.withUnsafeBytes { buffer in
            xpc_dictionary_set_data(oversized, "payload", buffer.baseAddress!, buffer.count)
        }
        XCTAssertThrowsError(try AhaKeyRuntimeXPCLibXPCClient.parsePeerEvent(oversized, maxPayloadBytes: 8)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeXPCTransportError, .payloadTooLarge)
        }
    }

    func testClientRejectsOversizedOutboundRequest() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let client = AhaKeyRuntimeXPCLibXPCClient(
            endpoint: try XCTUnwrap({
                server.start()
                return server.anonymousEndpoint
            }()),
            maxPayloadBytes: 8
        )
        do {
            _ = try await client.exchange(
                .handshake(.init(interfaceVersion: .current, clientBuildID: String(repeating: "x", count: 64)))
            )
            XCTFail("outbound payload above 8 bytes must fail closed")
        } catch AhaKeyRuntimeXPCTransportError.requestTooLarge {
            // Expected.
        }
    }

    private func handshakeOn(_ client: AhaKeyRuntimeXPCLibXPCClient) async throws {
        let response = try await client.exchange(
            .handshake(.init(interfaceVersion: .current, clientBuildID: "libxpc-client-test"))
        )
        guard case .handshakeAccepted = response else {
            return XCTFail("handshake")
        }
    }
}

private final class ConcurrentCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var maxValue = 0
    private(set) var sawBusy = false

    func enter() {
        lock.lock()
        current += 1
        maxValue = max(maxValue, current)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        current -= 1
        lock.unlock()
    }
}
