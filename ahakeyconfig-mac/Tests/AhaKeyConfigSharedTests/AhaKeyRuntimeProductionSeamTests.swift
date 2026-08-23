import XCTest
import Darwin
@testable import AhaKeyConfigShared

final class AhaKeyRuntimeProductionSeamTests: XCTestCase {
    func testHookFrameCodecWaitsForCompleteFrameAndDecodesHandshake() throws {
        let request = AhaKeyRuntimeHookRequest.handshake(
            .init(
                protocolVersion: .current,
                client: .codex,
                hookBuildID: "codex-hook-1"
            )
        )
        let codec = AhaKeyRuntimeJSONFrameCodec(maximumPayloadBytes: 4_096)
        let frame = try codec.encode(request)
        var buffer = Data(frame.prefix(5))

        XCTAssertNil(try codec.decodeOne(AhaKeyRuntimeHookRequest.self, from: &buffer))

        buffer.append(frame.dropFirst(5))
        XCTAssertEqual(try codec.decodeOne(AhaKeyRuntimeHookRequest.self, from: &buffer), request)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testHookSessionRequiresHandshakeAndAcceptsOnlyCurrentOrPreviousVersion() throws {
        var session = AhaKeyRuntimeHookSession(rateLimit: 10, rateWindow: 1)
        let state = AhaKeyRuntimeHookRequest.aiState(
            .init(event: .permissionRequested, requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        )

        XCTAssertThrowsError(try session.accept(state, at: 0)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSessionError, .handshakeRequired)
        }
        XCTAssertThrowsError(
            try session.accept(
                .handshake(.init(protocolVersion: .init(major: 0, minor: 9), client: .kimi, hookBuildID: "old")),
                at: 0
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSessionError, .unsupportedVersion)
        }

        XCTAssertEqual(
            try session.accept(
                .handshake(.init(protocolVersion: .previous, client: .kimi, hookBuildID: "kimi-1")),
                at: 0
            ),
            .handshakeAccepted(.previous)
        )
        XCTAssertEqual(
            try session.accept(state, at: 0.1),
            .messageAccepted(.init(protocolVersion: .previous, client: .kimi, hookBuildID: "kimi-1"))
        )
    }

    func testXPCPeerPolicyRequiresCurrentUserExpectedTeamAndAllowedSigningIdentifier() {
        let policy = AhaKeyRuntimeXPCPeerPolicy(
            expectedUserID: 501,
            expectedTeamIdentifier: "AHAKEYTEAM",
            allowedSigningIdentifiers: ["ai.ahakey.studio", "ai.ahakey.runtime"]
        )
        let valid = AhaKeyRuntimeXPCPeerIdentity(
            userID: 501,
            teamIdentifier: "AHAKEYTEAM",
            signingIdentifier: "ai.ahakey.studio"
        )

        XCTAssertTrue(policy.allows(valid))
        XCTAssertFalse(policy.allows(.init(userID: 502, teamIdentifier: "AHAKEYTEAM", signingIdentifier: "ai.ahakey.studio")))
        XCTAssertFalse(policy.allows(.init(userID: 501, teamIdentifier: "OTHER", signingIdentifier: "ai.ahakey.studio")))
        XCTAssertFalse(policy.allows(.init(userID: 501, teamIdentifier: "AHAKEYTEAM", signingIdentifier: "ai.attacker")))
    }

    func testEventReplayReturnsRetainedEventsOrRequiresFreshSnapshotWhenCursorHasGap() throws {
        var replay = AhaKeyRuntimeEventReplayBuffer(capacity: 2)
        let first = AhaKeyRuntimeEvent(sequence: .init(1), payload: .lifecycleChanged(.starting))
        let second = AhaKeyRuntimeEvent(sequence: .init(2), payload: .lifecycleChanged(.running))
        let third = AhaKeyRuntimeEvent(sequence: .init(3), payload: .snapshotInvalidated)
        try replay.append(first)
        try replay.append(second)
        try replay.append(third)

        XCTAssertEqual(try replay.events(after: .init(1)), .events([second, third]))
        XCTAssertEqual(try replay.events(after: .init(0)), .snapshotRequired(latest: .init(3)))
        XCTAssertEqual(try replay.events(after: .init(3)), .events([]))

        let restarted = AhaKeyRuntimeEventReplayBuffer(capacity: 2, latestSequence: .init(9))
        XCTAssertEqual(try restarted.events(after: .init(8)), .snapshotRequired(latest: .init(9)))
    }

    func testXPCSessionNegotiatesInterfaceBeforePrivilegedRequests() throws {
        var session = AhaKeyRuntimeXPCSession()

        XCTAssertThrowsError(try session.accept(.snapshot)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeXPCSessionError, .handshakeRequired)
        }
        XCTAssertEqual(
            try session.accept(
                .handshake(.init(interfaceVersion: .init(major: 1, minor: 0), clientBuildID: "studio-1"))
            ),
            .handshakeAccepted(.init(major: 1, minor: 0))
        )
        XCTAssertEqual(try session.accept(.snapshot), .requestAccepted)
    }

    func testHookCodecRejectsOversizedDeclaredFrameBeforeAllocatingPayload() throws {
        let codec = AhaKeyRuntimeJSONFrameCodec(maximumPayloadBytes: 16)
        var buffer = Data([0, 0, 0, 17])

        XCTAssertThrowsError(try codec.decodeOne(AhaKeyRuntimeHookRequest.self, from: &buffer)) { error in
            XCTAssertEqual(
                error as? AhaKeyRuntimeProductionSeamError,
                .frameTooLarge(maximum: 16, received: 17)
            )
        }
    }

    func testHookSessionRateLimitsMessagesWithinWindow() throws {
        var session = AhaKeyRuntimeHookSession(rateLimit: 1, rateWindow: 1)
        _ = try session.accept(
            .handshake(.init(protocolVersion: .current, client: .codex, hookBuildID: "hook-1")),
            at: 10
        )
        _ = try session.accept(.leverQuery, at: 10.1)

        XCTAssertThrowsError(try session.accept(.leverQuery, at: 10.2)) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSessionError, .rateLimited)
        }
        XCTAssertEqual(
            try session.accept(.leverQuery, at: 11.1),
            .messageAccepted(.init(protocolVersion: .current, client: .codex, hookBuildID: "hook-1"))
        )
    }

    func testXPCEndpointRequiresWireHandshakeThenDispatchesRequest() async throws {
        let serverHandshake = AhaKeyRuntimeXPCServerHandshake(
            runtimeVersion: .development,
            interfaceVersion: .current,
            supportedConfigurationSchemaVersions: [1],
            capabilities: [.snapshot, .eventReplay, .configuration, .diagnostics, .firmwareUpgrade]
        )
        let endpoint = AhaKeyRuntimeXPCSessionEndpoint(serverHandshake: serverHandshake) { request in
            XCTAssertEqual(request, .snapshot)
            return .policyUpdated
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let handshake = AhaKeyRuntimeXPCRequest.handshake(
            .init(interfaceVersion: .current, clientBuildID: "studio-test")
        )
        let handshakeResponse = try await endpoint.exchange(encoder.encode(handshake))
        XCTAssertEqual(
            try decoder.decode(AhaKeyRuntimeXPCResponse.self, from: handshakeResponse),
            .handshakeAccepted(serverHandshake)
        )

        let response = try await endpoint.exchange(encoder.encode(AhaKeyRuntimeXPCRequest.snapshot))
        XCTAssertEqual(try decoder.decode(AhaKeyRuntimeXPCResponse.self, from: response), .policyUpdated)
    }

    func testHookSocketCreatesSameUser0600SocketAndRemovesItOnStop() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private", isDirectory: true)
            .appendingPathComponent("hook.sock")
        let server = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { _, _ in .acknowledged }

        try server.start()
        var status = stat()
        XCTAssertEqual(lstat(socketURL.path, &status), 0)
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK)
        XCTAssertEqual(status.st_mode & 0o777, 0o600)
        XCTAssertEqual(status.st_uid, getuid())

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketURL.path))
    }

    func testHookSocketClientNegotiatesThenQueriesLeverOverRestrictedSocket() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private/hook.sock")
        let server = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { context, request -> AhaKeyRuntimeHookResponse in
            guard context.client == .kimi else { return .acknowledged }
            if request == .leverQuery {
                return .leverPosition(AhaKeyRuntimeLeverPosition.up)
            }
            return .acknowledged
        }
        try server.start()
        defer { server.stop() }

        let client = AhaKeyRuntimeHookSocketClient(socketURL: socketURL)
        let response = try client.exchange(
            handshake: .init(protocolVersion: .current, client: .kimi, hookBuildID: "kimi-test"),
            request: .leverQuery,
            timeout: 2
        )

        XCTAssertEqual(response, .leverPosition(.up))
    }

    func testHookSocketRateLimitCannotBeBypassedByReconnect() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private/hook.sock")
        let server = AhaKeyRuntimeHookSocketServer(
            socketURL: socketURL,
            rateLimit: 3,
            rateWindow: 60
        ) { _, _ in .leverPosition(.up) }
        try server.start()
        defer { server.stop() }
        let client = AhaKeyRuntimeHookSocketClient(socketURL: socketURL)
        let handshake = AhaKeyRuntimeHookHandshake(
            protocolVersion: .current,
            client: .codex,
            hookBuildID: "rate-test"
        )

        XCTAssertEqual(
            try client.exchange(handshake: handshake, request: .leverQuery, timeout: 2),
            .leverPosition(.up)
        )
        XCTAssertThrowsError(
            try client.exchange(handshake: handshake, request: .leverQuery, timeout: 2)
        )
    }

    func testHookSocketRefusesToReplaceRegularFileAtSocketPath() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let socketURL = directory.appendingPathComponent("hook.sock")
        try Data("do-not-delete".utf8).write(to: socketURL)
        let server = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { _, _ in .acknowledged }

        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSocketError, .unsafeExistingPath)
        }
        XCTAssertEqual(try String(contentsOf: socketURL, encoding: .utf8), "do-not-delete")
    }

    func testSecondHookServerCannotUnlinkLiveRuntimeSocket() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("ahk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("private/hook.sock")
        let first = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { _, _ in .leverPosition(.down) }
        let second = AhaKeyRuntimeHookSocketServer(socketURL: socketURL) { _, _ in .leverPosition(.up) }
        try first.start()
        defer { first.stop() }

        XCTAssertThrowsError(try second.start()) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeHookSocketError, .lockUnavailable)
        }
        let response = try AhaKeyRuntimeHookSocketClient(socketURL: socketURL).exchange(
            handshake: .init(protocolVersion: .current, client: .codex, hookBuildID: "owner-test"),
            request: .leverQuery,
            timeout: 2
        )
        XCTAssertEqual(response, .leverPosition(.down))
    }

    func testXPCTransportTimesOutWhenPeerNeverReplies() async throws {
        let listener = NSXPCListener.anonymous()
        let delegate = SilentXPCListenerDelegate()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let transport = AhaKeyRuntimeXPCConnectionTransport(
            connection: NSXPCConnection(listenerEndpoint: listener.endpoint)
        )

        do {
            _ = try await transport.exchange(Data("request".utf8), timeout: 0.05)
            XCTFail("silent XPC peer must not suspend the caller forever")
        } catch AhaKeyRuntimeXPCTransportError.requestTimedOut {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private final class SilentXPCService: NSObject, AhaKeyRuntimeXPCServiceProtocol {
    func exchange(_ request: Data, reply: @escaping (Data?, NSError?) -> Void) {}
}

private final class SilentXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = SilentXPCService()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AhaKeyRuntimeXPCServiceProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}
