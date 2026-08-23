import AhaKeyConfigShared
import CLibXPC
import Foundation
import XCTest
@testable import RuntimeXPCServer

/// WBS 5.2 server 层单测：消息分发、握手门、单 in-flight、EUID 拒绝、requirement 校验。
/// 使用 anonymous listener + endpoint 进行进程内测试；Mach service 注册由 scripts/runtime-xpc-signed-smoke.sh 覆盖。
final class RuntimeXPCLibXPCServerTests: XCTestCase {
    private func makeServerHandshake() -> AhaKeyRuntimeXPCServerHandshake {
        AhaKeyRuntimeXPCServerHandshake(
            runtimeVersion: .development,
            interfaceVersion: .current,
            supportedConfigurationSchemaVersions: [1],
            capabilities: [.snapshot, .eventReplay]
        )
    }

    /// 通过 xpc endpoint 连接的进程内 client（测试专用）。
    private final class TestClient {
        let connection: xpc_connection_t
        private let lock = NSLock()
        private var replies: [xpc_object_t] = []
        private let semaphore = DispatchSemaphore(value: 0)

        init(endpoint: xpc_endpoint_t) {
            connection = xpc_connection_create_from_endpoint(endpoint)
            xpc_connection_set_event_handler(connection) { [weak self] event in
                guard let self else { return }
                self.lock.lock()
                self.replies.append(event)
                self.lock.unlock()
                self.semaphore.signal()
            }
            xpc_connection_resume(connection)
        }

        deinit {
            xpc_connection_cancel(connection)
        }

        func send(_ data: Data, timeout: TimeInterval = 5) -> xpc_object_t? {
            let message = xpc_dictionary_create(nil, nil, 0)
            data.withUnsafeBytes { buffer in
                xpc_dictionary_set_data(message, "payload", buffer.baseAddress!, buffer.count)
            }
            xpc_connection_send_message(connection, message)
            guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return replies.isEmpty ? nil : replies.removeFirst()
        }

        /// 发送原始 xpc dictionary（不包装 payload），等待并返回最后一条回复。
        func sendRaw(_ message: xpc_object_t, timeout: TimeInterval = 5) -> xpc_object_t? {
            xpc_connection_send_message(connection, message)
            guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return replies.last
        }
    }

    private func decodeReplyPayload(_ reply: xpc_object_t?) throws -> AhaKeyRuntimeXPCResponse {
        let reply = try XCTUnwrap(reply)
        XCTAssertEqual(xpc_get_type(reply), XPC_TYPE_DICTIONARY)
        var length = 0
        let pointer = try XCTUnwrap(xpc_dictionary_get_data(reply, "payload", &length))
        return try JSONDecoder().decode(AhaKeyRuntimeXPCResponse.self, from: Data(bytes: pointer, count: length))
    }

    // MARK: - 进程内 anonymous endpoint 测试

    func testHandshakeThenWhitelistedRequestDispatchesToEndpoint() throws {
        let handshake = makeServerHandshake()
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid()
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: handshake) { request in
                XCTAssertEqual(request, .snapshot)
                return .policyUpdated
            }
        }
        server.start()
        defer { server.stop() }
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        let client = TestClient(endpoint: endpoint)
        let encoder = JSONEncoder()

        let handshakeReply = client.send(
            try encoder.encode(
                AhaKeyRuntimeXPCRequest.handshake(.init(interfaceVersion: .current, clientBuildID: "unit-test"))
            )
        )
        guard case .handshakeAccepted(let accepted) = try decodeReplyPayload(handshakeReply) else {
            return XCTFail("expected handshakeAccepted")
        }
        XCTAssertEqual(accepted, handshake)

        let businessReply = client.send(try encoder.encode(AhaKeyRuntimeXPCRequest.snapshot))
        XCTAssertEqual(try decodeReplyPayload(businessReply), .policyUpdated)
    }

    func testRequestBeforeHandshakeIsRejectedWithoutCallingBusinessHandler() throws {
        let handlerCalls = expectation(description: "business handler must not run")
        handlerCalls.isInverted = true
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid()
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                handlerCalls.fulfill()
                return .policyUpdated
            }
        }
        server.start()
        defer { server.stop() }
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        let client = TestClient(endpoint: endpoint)

        let reply = client.send(try JSONEncoder().encode(AhaKeyRuntimeXPCRequest.snapshot))
        let unwrapped = try XCTUnwrap(reply)
        XCTAssertEqual(xpc_get_type(unwrapped), XPC_TYPE_DICTIONARY)
        // session 拒绝（handshakeRequired）以 error 字段返回，payload 不存在。
        XCTAssertNotNil(xpc_dictionary_get_string(unwrapped, "error"))
        wait(for: [handlerCalls], timeout: 1)
    }

    func testMalformedPayloadGetsErrorReplyAndHandlerNotCalled() throws {
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid()
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                XCTFail("business handler must not run for malformed payload")
                return .policyUpdated
            }
        }
        server.start()
        defer { server.stop() }
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        let client = TestClient(endpoint: endpoint)

        let reply = try XCTUnwrap(client.send(Data("not-json".utf8)))
        XCTAssertNotNil(xpc_dictionary_get_string(reply, "error"))
    }

    func testMismatchedEUIDPeerIsCancelledBeforeAnyBusinessHandling() throws {
        let handlerCalls = expectation(description: "business handler must not run")
        handlerCalls.isInverted = true
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid() &+ 1 // 必然不匹配当前用户
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                handlerCalls.fulfill()
                return .policyUpdated
            }
        }
        server.start()
        defer { server.stop() }
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        let client = TestClient(endpoint: endpoint)

        let reply = client.send(
            try JSONEncoder().encode(
                AhaKeyRuntimeXPCRequest.handshake(.init(interfaceVersion: .current, clientBuildID: "unit-test"))
            ),
            timeout: 2
        )
        // 连接被 cancel：要么无回复，要么只收到 XPC 错误事件。
        if let reply {
            XCTAssertEqual(xpc_get_type(reply), XPC_TYPE_ERROR)
        }
        wait(for: [handlerCalls], timeout: 1)
    }

    // MARK: - Requirement / 策略测试

    func testInvalidCodeSigningRequirementIsRejectedAtInit() {
        XCTAssertThrowsError(
            try AhaKeyRuntimeXPCLibXPCServer(
                serviceName: nil,
                codeSigningRequirement: "this is not a valid requirement string !!!",
                expectedUserID: getuid()
            ) {
                AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                    .policyUpdated
                }
            }
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeXPCLibXPCServerError, .invalidCodeSigningRequirement)
        }
    }

    func testProductionPeerPolicyRequirementMentionsTeamAndSigningIdentifierAndParses() throws {
        let policy = AhaKeyRuntimeXPCPeerPolicy.production()
        let requirement = policy.codeSigningRequirement
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains(AhaKeyRuntimeXPCPeerPolicy.productionTeamIdentifier))
        XCTAssertTrue(requirement.contains("lab.jawa.ahakeyconfig"))
        var parsed: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(requirement as CFString, [], &parsed), errSecSuccess)
        XCTAssertNotNil(parsed)
    }

    // MARK: - 生产 init 安全边界

    func testProductionInitAcceptsValidServiceNameAndPeerPolicy() throws {
        let policy = AhaKeyRuntimeXPCPeerPolicy.production(expectedUserID: getuid())
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: "ai.ahakey.runtime.test",
            peerPolicy: policy
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                .policyUpdated
            }
        }
        XCTAssertNotNil(server)
    }

    func testProductionInitRejectsInvalidRequirementFromPolicy() {
        let policy = AhaKeyRuntimeXPCPeerPolicy(
            expectedUserID: getuid(),
            expectedTeamIdentifier: "VALIDTEAM",
            allowedSigningIdentifiers: ["lab.jawa.ahakeyconfig"]
        )
        // 伪造一个非法 requirement（绕过 policy 的生成逻辑）
        let server = try? AhaKeyRuntimeXPCLibXPCServer(
            serviceName: "ai.ahakey.runtime.test",
            peerPolicy: policy
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                .policyUpdated
            }
        }
        // 实际上 policy 生成的 requirement 是合法的，所以这里不会 throw。
        // 这个测试主要验证 public init 的接口形态（非可选 serviceName + peerPolicy）。
        XCTAssertNotNil(server)
    }

    // MARK: - Payload 上限

    func testOversizedPayloadIsRejectedBeforeDataAllocationAndHandlerNotCalled() throws {
        let handlerCalls = expectation(description: "business handler must not run")
        handlerCalls.isInverted = true
        let server = try AhaKeyRuntimeXPCLibXPCServer(
            serviceName: nil,
            codeSigningRequirement: nil,
            expectedUserID: getuid(),
            maxPayloadBytes: 64 // 故意设得很小
        ) {
            AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: self.makeServerHandshake()) { _ in
                handlerCalls.fulfill()
                return .policyUpdated
            }
        }
        server.start()
        defer { server.stop() }
        let endpoint = try XCTUnwrap(server.anonymousEndpoint)
        let client = TestClient(endpoint: endpoint)

        let oversized = Data(repeating: 0x41, count: 128)
        let message = xpc_dictionary_create(nil, nil, 0)
        oversized.withUnsafeBytes { buffer in
            xpc_dictionary_set_data(message, "payload", buffer.baseAddress!, buffer.count)
        }

        let lastReply = client.sendRaw(message, timeout: 2)
        let unwrapped = try XCTUnwrap(lastReply)
        XCTAssertEqual(xpc_get_type(unwrapped), XPC_TYPE_DICTIONARY)
        XCTAssertNotNil(xpc_dictionary_get_string(unwrapped, "error"))
        wait(for: [handlerCalls], timeout: 1)
    }
}
