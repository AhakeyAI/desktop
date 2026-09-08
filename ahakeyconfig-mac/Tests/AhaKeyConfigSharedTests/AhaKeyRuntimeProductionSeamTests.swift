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

    func testAdmissionTokenAndIngestRequestRejectUnknownKeysMissingFieldsAndWrongShape() throws {
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(1),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        try assertCorruptRuntimeFact(token, extraKey: "unexpected")
        try assertMissingFieldIsCorrupt(token, dropping: "sessionGeneration")
        XCTAssertThrowsError(
            try JSONDecoder().decode(AhaKeyRuntimeResourceAdmissionToken.self, from: Data("[]".utf8))
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }

        let request = AhaKeyXPCResourceIngestionRequest(items: [], admission: token)
        try assertCorruptRuntimeFact(request, extraKey: "unexpected")
        try assertMissingFieldIsCorrupt(request, dropping: "admission")
        var requestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any]
        )
        requestObject["admission"] = "not-a-token"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyXPCResourceIngestionRequest.self,
                from: try JSONSerialization.data(withJSONObject: requestObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
    }

    func testAdmissionFenceLinearizesReservationAgainstLiveMutation() throws {
        let fence = AhaKeyRuntimeAdmissionFence()
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        let next = AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: token.targetDeviceID,
            sessionGeneration: .init(1),
            transportGeneration: token.transportGeneration,
            sealedOLEDFact: token.sealedOLEDFact
        )
        XCTAssertTrue(publishLive(fence, token))
        let reservation = try XCTUnwrap(fence.reserve(token))
        XCTAssertTrue(publishLive(fence, next))
        XCTAssertThrowsError(try fence.withReservedWrite(reservation) { "wrote" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }

        let live = try XCTUnwrap(fence.reserve(next))
        var wrote = false
        try fence.withReservedWrite(live) { wrote = true }
        XCTAssertTrue(wrote)
        XCTAssertThrowsError(try fence.withReservedWrite(live) { wrote = false }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertTrue(wrote)
        XCTAssertNil(fence.reserve(token))

        XCTAssertTrue(publishLive(fence, next))
        let once = try XCTUnwrap(fence.reserve(next))
        struct ProbeError: Error {}
        XCTAssertThrowsError(try fence.withReservedWrite(once) { throw ProbeError() })
        XCTAssertThrowsError(try fence.withReservedWrite(once) { "replay" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }

        XCTAssertTrue(publishLive(fence, next))
        let stale = try XCTUnwrap(fence.reserve(next))
        fence.beginIdentityMutation()
        XCTAssertThrowsError(try fence.withReservedWrite(stale) { "mutated" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertNil(fence.reserve(next))
    }

    func testAdmissionPublicationTicketCASIgnoresStaleEpoch() throws {
        let fence = AhaKeyRuntimeAdmissionFence()
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        let first = fence.beginIdentityMutation()
        XCTAssertTrue(fence.publish(token, ticket: first))
        XCTAssertEqual(fence.liveTokenForTesting(), token)

        let revoked = fence.beginIdentityMutation()
        XCTAssertNil(fence.liveTokenForTesting())
        XCTAssertFalse(fence.publish(token, ticket: first))
        XCTAssertNil(fence.liveTokenForTesting())
        XCTAssertNil(fence.reserve(token))

        XCTAssertTrue(fence.publish(token, ticket: revoked))
        XCTAssertEqual(fence.liveTokenForTesting(), token)
        XCTAssertFalse(fence.publish(token, ticket: revoked), "同一 ticket 不得在 epoch 前进后再次写入")
        XCTAssertEqual(fence.liveTokenForTesting(), token)

        let next = AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: token.targetDeviceID,
            sessionGeneration: .init(1),
            transportGeneration: token.transportGeneration,
            sealedOLEDFact: token.sealedOLEDFact
        )
        let superseded = fence.beginIdentityMutation()
        let replacement = fence.beginIdentityMutation()
        XCTAssertFalse(fence.publish(token, ticket: superseded))
        XCTAssertTrue(fence.publish(next, ticket: replacement))
        XCTAssertFalse(fence.publish(token, ticket: superseded))
        XCTAssertEqual(fence.liveTokenForTesting(), next)
    }

    func testAdjacentMutationTicketsCannotBorrowEpoch() throws {
        let fence = AhaKeyRuntimeAdmissionFence()
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        let first = fence.beginIdentityMutation()
        let second = fence.beginIdentityMutation()
        XCTAssertFalse(fence.publish(token, ticket: first), "旧 mutation ticket 不得借用后续 revoke epoch")
        XCTAssertNil(fence.liveTokenForTesting())
        XCTAssertTrue(fence.publish(token, ticket: second))
        XCTAssertEqual(fence.liveTokenForTesting(), token)
        XCTAssertFalse(fence.publish(token, ticket: first))
        XCTAssertEqual(fence.liveTokenForTesting(), token)
    }

    func testProductSourcesHaveNoTicketlessAdmissionPublish() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let fenceURL = sources.appendingPathComponent("Shared/AhaKeyRuntimeAdmissionFence.swift")
        let fenceText = try String(contentsOf: fenceURL, encoding: .utf8)
        XCTAssertFalse(
            fenceText.contains("func publish(_ token: AhaKeyRuntimeResourceAdmissionToken?)"),
            "ticketless publish 不得留在 fence 公共 API"
        )
        XCTAssertTrue(
            fenceText.contains("ticket: AhaKeyRuntimeAdmissionPublicationTicket"),
            "fence 必须只保留 ticketed CAS publish"
        )

        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            for arguments in admissionPublishArgumentLists(in: text) where !arguments.contains("ticket:") {
                hits.append(relative)
            }
        }
        XCTAssertEqual(hits, [], "产品源码不得 ticketless live admission publish：\(hits.joined(separator: ","))")
    }

    func testAdmissionReservationDiscardIsIdempotentAndBoundsOutstanding() throws {
        let fence = AhaKeyRuntimeAdmissionFence()
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(0),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        XCTAssertTrue(publishLive(fence, token))

        var abandoned: [AhaKeyRuntimeAdmissionReservation] = []
        for _ in 0..<32 {
            abandoned.append(try XCTUnwrap(fence.reserve(token)))
        }
        XCTAssertEqual(fence.outstandingCountForTesting(), 32)
        for reservation in abandoned {
            fence.discard(reservation)
            fence.discard(reservation)
        }
        XCTAssertEqual(fence.outstandingCountForTesting(), 0)
        XCTAssertThrowsError(try fence.withReservedWrite(abandoned[0]) { "discarded" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertEqual(fence.outstandingCountForTesting(), 0)

        let once = try XCTUnwrap(fence.reserve(token))
        var wrote = false
        try fence.withReservedWrite(once) { wrote = true }
        XCTAssertTrue(wrote)
        fence.discard(once)
        XCTAssertThrowsError(try fence.withReservedWrite(once) { wrote = false }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertTrue(wrote)
        XCTAssertEqual(fence.outstandingCountForTesting(), 0)

        struct ProbeError: Error {}
        let throwing = try XCTUnwrap(fence.reserve(token))
        XCTAssertThrowsError(try fence.withReservedWrite(throwing) { throw ProbeError() })
        fence.discard(throwing)
        XCTAssertThrowsError(try fence.withReservedWrite(throwing) { "replay" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertEqual(fence.outstandingCountForTesting(), 0)

        var leaked: [AhaKeyRuntimeAdmissionReservation] = []
        for _ in 0..<8 {
            leaked.append(try XCTUnwrap(fence.reserve(token)))
        }
        XCTAssertEqual(fence.outstandingCountForTesting(), 8)
        fence.beginIdentityMutation()
        XCTAssertEqual(fence.outstandingCountForTesting(), 0)
        XCTAssertThrowsError(try fence.withReservedWrite(leaked[0]) { "mutated" }) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeAdmissionWriteError, .staleReservation)
        }
        XCTAssertNil(fence.reserve(token))
    }

    func testAdmissionTokenAndIngestRequestRejectNestedUnknownKeysMissingFieldsAndWrongShape() throws {
        let token = try AhaKeyRuntimeResourceAdmissionToken(
            targetDeviceID: AhaKeyRuntimeDeviceID("TEST-DEVICE"),
            sessionGeneration: .init(1),
            transportGeneration: .init(0),
            sealedOLEDFact: .init(family: .legacyStandard)
        )
        let encodedToken = try JSONEncoder().encode(token)
        var tokenObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedToken) as? [String: Any])
        var fact = try XCTUnwrap(tokenObject["sealedOLEDFact"] as? [String: Any])
        fact["unexpected"] = true
        tokenObject["sealedOLEDFact"] = fact
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeResourceAdmissionToken.self,
                from: try JSONSerialization.data(withJSONObject: tokenObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
        fact.removeValue(forKey: "unexpected")
        fact.removeValue(forKey: "sessionUploadAdvertised")
        tokenObject["sealedOLEDFact"] = fact
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeResourceAdmissionToken.self,
                from: try JSONSerialization.data(withJSONObject: tokenObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
        tokenObject["sealedOLEDFact"] = "legacyStandard"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyRuntimeResourceAdmissionToken.self,
                from: try JSONSerialization.data(withJSONObject: tokenObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }

        let item = AhaKeyXPCResourceIngestionItem(
            logicalIdentifier: try AhaKeyResourceIdentifier("task.done"),
            sha256: try AhaKeySHA256Digest("03c9f206d1c2afd64261a5bbab141a549997e249896aeddeaf67bbc72127f6be"),
            byteCount: 0,
            data: Data()
        )
        let request = AhaKeyXPCResourceIngestionRequest(items: [item], admission: token)
        let encodedRequest = try JSONEncoder().encode(request)
        var requestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any])
        var items = try XCTUnwrap(requestObject["items"] as? [[String: Any]])
        items[0]["unexpected"] = true
        requestObject["items"] = items
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyXPCResourceIngestionRequest.self,
                from: try JSONSerialization.data(withJSONObject: requestObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
        items[0].removeValue(forKey: "unexpected")
        items[0].removeValue(forKey: "byteCount")
        requestObject["items"] = items
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyXPCResourceIngestionRequest.self,
                from: try JSONSerialization.data(withJSONObject: requestObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
        requestObject["items"] = ["not-an-item"]
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AhaKeyXPCResourceIngestionRequest.self,
                from: try JSONSerialization.data(withJSONObject: requestObject)
            )
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
    }

    private func assertCorruptRuntimeFact<T: Codable>(_ value: T, extraKey: String) throws {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[extraKey] = true
        XCTAssertThrowsError(
            try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: object))
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
        }
    }

    @discardableResult
    private func publishLive(
        _ fence: AhaKeyRuntimeAdmissionFence,
        _ token: AhaKeyRuntimeResourceAdmissionToken
    ) -> Bool {
        let ticket = fence.beginIdentityMutation()
        return fence.publish(token, ticket: ticket)
    }

    private func admissionPublishArgumentLists(in text: String) -> [String] {
        let needle = "resourceAdmissionFence.publish("
        var calls: [String] = []
        var searchStart = text.startIndex
        while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            let argsStart = range.upperBound
            var depth = 1
            var index = argsStart
            var end = argsStart
            while index < text.endIndex {
                let character = text[index]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        end = index
                        break
                    }
                }
                index = text.index(after: index)
            }
            if depth == 0 {
                calls.append(String(text[argsStart..<end]))
                searchStart = end
            } else {
                break
            }
        }
        return calls
    }

    private func assertMissingFieldIsCorrupt<T: Codable>(_ value: T, dropping key: String) throws {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: key)
        XCTAssertThrowsError(
            try JSONDecoder().decode(T.self, from: try JSONSerialization.data(withJSONObject: object))
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimeContractError, .corruptRuntimeFact)
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
