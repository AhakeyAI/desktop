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

    func testQueuedBusinessDoesNotReplayOnNewGenerationBeforeHandshake() async throws {
        let applyCount = Counter()
        let hang = HangGate()
        let package = try applyPackage()
        let server = try makeServer { request in
            switch request {
            case .snapshot:
                await hang.wait()
                return .snapshot(self.snapshot())
            case .apply:
                applyCount.increment()
                return .operationAccepted(package.operationID)
            default:
                return .policyUpdated
            }
        }
        defer { server.stop() }
        let client = try startedClient(server: server, timeout: 5)
        try await handshakeOn(client)

        let snapshotEntered = Expectation()
        hang.onEnter = { snapshotEntered.fulfill() }
        let snapshotTask = Task { try await client.exchange(.snapshot) }
        await snapshotEntered.wait()

        let applyQueued = Expectation()
        client.testBarrierHandler = { barrier, _ in
            if barrier == .afterEnqueueWaiter {
                applyQueued.fulfill()
            }
        }
        let applyTask = Task { try await client.exchange(.apply(package)) }
        await applyQueued.wait()
        client.testBarrierHandler = nil

        client.invalidate()
        hang.release()

        do {
            _ = try await applyTask.value
            XCTFail("old-generation queued apply must fail, not replay")
        } catch AhaKeyRuntimeXPCTransportError.connectionInvalid {
            // Expected.
        } catch is CancellationError {
            XCTFail("queued apply should fail as stale generation, not as cancel")
        }
        _ = try? await snapshotTask.value
        XCTAssertEqual(applyCount.value, 0, "queued apply must not reach the server after invalidate")

        try await handshakeOn(client)
        let screen = try await client.exchange(.snapshot)
        guard case .snapshot = screen else {
            return XCTFail("business after explicit handshake must succeed")
        }
        XCTAssertEqual(applyCount.value, 0)
    }

    func testCancelBeforeCallNeverSendsApply() async throws {
        try await runCancelMatrix(rounds: 100, window: .beforeCall)
    }

    func testCancelBeforeEnqueueNeverSendsApply() async throws {
        try await runCancelMatrix(rounds: 100, window: .beforeEnqueueWaiter)
    }

    func testCancelBetweenDequeueAndResumeNeverSendsApply() async throws {
        try await runCancelMatrix(rounds: 100, window: .afterDequeueBeforeResume)
    }

    func testCancelBeforeInFlightRegisterNeverSendsApply() async throws {
        try await runCancelMatrix(rounds: 100, window: .beforeRegisterInFlight)
    }

    func testConcurrentEncodeAndExchangeStress() async throws {
        let concurrent = ConcurrentCounter()
        let server = try makeServer(delayNanoseconds: 5_000_000, maxConcurrent: concurrent)
        defer { server.stop() }
        let client = try startedClient(server: server, maxQueued: 32)
        try await handshakeOn(client)
        try await withThrowingTaskGroup(of: AhaKeyRuntimeXPCResponse.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await client.exchange(.snapshot)
                }
            }
            var count = 0
            for try await response in group {
                guard case .snapshot = response else {
                    return XCTFail("stress exchange must stay snapshot")
                }
                count += 1
            }
            XCTAssertEqual(count, 24)
        }
        XCTAssertEqual(concurrent.maxValue, 1)
        XCTAssertFalse(concurrent.sawBusy)
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

    private func applyPackage() throws -> AhaKeyConfigurationPackage {
        try AhaKeyConfigurationPackage(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            baseRevision: .init(0),
            desiredConfiguration: Data("configuration".utf8),
            resources: []
        )
    }

    private enum CancelWindow: Equatable {
        case beforeCall
        case beforeEnqueueWaiter
        case afterDequeueBeforeResume
        case beforeRegisterInFlight
    }

    private func runCancelMatrix(rounds: Int, window: CancelWindow) async throws {
        let applyCount = Counter()
        let hang = HangGate()
        let package = try applyPackage()
        let server = try makeServer { request in
            switch request {
            case .snapshot:
                await hang.wait()
                return .snapshot(self.snapshot())
            case .apply:
                applyCount.increment()
                return .operationAccepted(package.operationID)
            default:
                return .policyUpdated
            }
        }
        defer { server.stop() }
        let client = try startedClient(server: server, timeout: 5)
        try await handshakeOn(client)

        for round in 0..<rounds {
            hang.reset()
            let applyTask: Task<AhaKeyRuntimeXPCResponse, Error>
            switch window {
            case .beforeCall:
                applyTask = Task { try await client.exchange(.apply(package)) }
                applyTask.cancel()
            case .beforeEnqueueWaiter:
                client.testBarrierHandler = { barrier, cancel in
                    if barrier == .beforeEnqueueWaiter {
                        cancel()
                    }
                }
                applyTask = Task { try await client.exchange(.apply(package)) }
            case .beforeRegisterInFlight:
                client.testBarrierHandler = { barrier, cancel in
                    if barrier == .beforeRegisterInFlight {
                        cancel()
                    }
                }
                applyTask = Task { try await client.exchange(.apply(package)) }
            case .afterDequeueBeforeResume:
                let snapshotEntered = Expectation()
                hang.onEnter = { snapshotEntered.fulfill() }
                let snapshotTask = Task { try await client.exchange(.snapshot) }
                await snapshotEntered.wait()

                let queued = Expectation()
                client.testBarrierHandler = { barrier, cancel in
                    switch barrier {
                    case .afterEnqueueWaiter:
                        queued.fulfill()
                    case .afterDequeueBeforeResume:
                        cancel()
                    default:
                        break
                    }
                }
                applyTask = Task { try await client.exchange(.apply(package)) }
                await queued.wait()
                hang.release()
                _ = try? await snapshotTask.value
            }

            do {
                _ = try await applyTask.value
                XCTFail("cancelled apply must not succeed in round \(round)")
            } catch is CancellationError {
                // Expected.
            } catch AhaKeyRuntimeXPCTransportError.connectionInvalid {
                // 若取消落到已登记的 in-flight，连接失效是允许的；关键是 server 收不到 apply。
            }
            client.testBarrierHandler = nil
            XCTAssertEqual(applyCount.value, 0, "server received apply in round \(round) window \(window)")
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0

    func increment() {
        lock.lock()
        n += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return n
    }
}

private final class Expectation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fulfilled = false

    func fulfill() {
        lock.lock()
        if fulfilled {
            lock.unlock()
            return
        }
        fulfilled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fulfilled {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }
}

private final class HangGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var onEnter: (() -> Void)?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            onEnter?()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        released = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func reset() {
        lock.lock()
        released = false
        continuation = nil
        onEnter = nil
        lock.unlock()
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
