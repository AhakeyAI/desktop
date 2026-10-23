import Foundation
import XCTest
import Darwin
@testable import AhaKeyConfigShared

final class CodexDesktopSessionBridgeTests: XCTestCase {
    private let thread = "01a11a8c-27dc-7670-9389-e912f24b2d65"
    private let client = "71efe1c2-e444-41ea-934d-9185e2c310aa"

    func testAutoChangesBothPermissionRangeAndApprovalOnOriginalOwnerForNextTurn() throws {
        var calls: [String] = []
        let bridge = CodexDesktopSessionBridge { method, params, version, target in
            calls.append(method)
            if method == "thread-owner-discovery" {
                XCTAssertEqual(version, 1); XCTAssertNil(target)
                XCTAssertEqual(params["hostId"] as? String, "local")
            } else {
                XCTAssertEqual(method, "thread-follower-update-thread-settings")
                XCTAssertEqual(version, 2); XCTAssertEqual(target, self.client)
                XCTAssertEqual(params["conversationId"] as? String, self.thread)
                XCTAssertNil(params["activeTurnId"], "Never use a running-turn override")
                let settings = try XCTUnwrap(params["threadSettings"] as? [String: String])
                XCTAssertEqual(settings, ["approvalPolicy": "never", "permissions": ":danger-full-access"])
                XCTAssertNil(params["sandboxPolicy"], "Named profile and sandbox must not be combined")
            }
            return self.reply(method)
        }
        let owner = try bridge.discoverOwner(threadID: thread)
        try bridge.updateNextTurn(owner: owner, mode: .fullAccess)
        XCTAssertEqual(calls, ["thread-owner-discovery", "thread-owner-discovery", "thread-follower-update-thread-settings"])
    }

    func testManualUsesConfirmedRestrictedProfileWithoutRewritingDefaultConfig() throws {
        let bridge = CodexDesktopSessionBridge { method, params, _, _ in
            if method != "thread-owner-discovery" {
                XCTAssertEqual(params["threadSettings"] as? [String: String],
                    ["approvalPolicy": "on-request", "permissions": "confirmed-custom-workspace"])
            }
            return self.reply(method)
        }
        try bridge.updateNextTurn(owner: .init(threadID: thread, clientID: client),
            mode: .requestedApproval(profileID: "confirmed-custom-workspace"))
    }

    func testOwnerRestartDoesNotResumeOrWriteAnUnrelatedCopy() {
        var methods: [String] = []
        let bridge = CodexDesktopSessionBridge { method, _, _, _ in
            methods.append(method)
            var reply = self.reply(method); reply["handledByClientId"] = UUID().uuidString
            return reply
        }
        XCTAssertThrowsError(try bridge.updateNextTurn(owner: .init(threadID: thread, clientID: client), mode: .fullAccess)) {
            XCTAssertEqual($0 as? CodexDesktopSessionBridge.BridgeError, .ownerChanged)
        }
        XCTAssertEqual(methods, ["thread-owner-discovery"])
    }

    func testNegativeMissingAndWrongOwnerAcknowledgementsAreNotSuccess() {
        for scenario in ["rejected", "missing-applied", "false-applied", "different-owner"] {
            let bridge = CodexDesktopSessionBridge { method, _, _, _ in
                var reply = self.reply(method)
                if method != "thread-owner-discovery" {
                    switch scenario {
                    case "rejected": reply["resultType"] = "error"
                    case "missing-applied": reply["result"] = [:] as [String: Bool]
                    case "false-applied": reply["result"] = ["applied": false]
                    default: reply["handledByClientId"] = UUID().uuidString
                    }
                }
                return reply
            }
            XCTAssertThrowsError(try bridge.updateNextTurn(owner: .init(threadID: thread, clientID: client), mode: .fullAccess), scenario)
        }
    }

    func testInvalidTargetsAndUnrestrictedManualProfileNeverSubmitAChange() {
        var changes = 0
        let bridge = CodexDesktopSessionBridge { method, _, _, _ in
            if method != "thread-owner-discovery" { changes += 1 }
            return self.reply(method)
        }
        XCTAssertThrowsError(try bridge.discoverOwner(threadID: "a displayed hash is not a thread UUID"))
        for profile in ["", ":danger-full-access", "bad\nprofile"] {
            XCTAssertThrowsError(try bridge.updateNextTurn(owner: .init(threadID: thread, clientID: client), mode: .requestedApproval(profileID: profile)))
        }
        XCTAssertEqual(changes, 0)
    }

    func testRestrictedBaselineRoundTripPreservesCustomRootsAndNetwork() throws {
        let value: [String: Any] = ["approvalPolicy": "on-request", "sandboxPolicy": [
            "type": "workspaceWrite", "writableRoots": ["/tmp/project", "/tmp/assets"],
            "networkAccess": false, "excludeTmpdirEnvVar": true, "excludeSlashTmp": true]]
        let settings = try CodexDesktopSessionBridge.Settings(encoded: JSONSerialization.data(withJSONObject: value))
        let restored = try JSONDecoder().decode(CodexDesktopSessionBridge.Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings, restored)
        let bridge = CodexDesktopSessionBridge { method, params, _, _ in
            if method != "thread-owner-discovery" {
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: params["threadSettings"]!, options: [.sortedKeys]), settings.encoded)
            }
            return self.reply(method)
        }
        try bridge.updateNextTurn(owner: .init(threadID: thread, clientID: client), settings: restored)
    }

    func testPermissionBaselineRejectsUnrelatedFieldsAndAmbiguousPermissionRange() throws {
        let invalid: [[String: Any]] = [
            ["approvalPolicy": "never"],
            ["approvalPolicy": "never", "permissions": ":workspace", "model": "unrelated"],
            ["approvalPolicy": "never", "permissions": ":workspace", "sandboxPolicy": ["type": "readOnly"]],
            ["approvalPolicy": "never", "permissions": NSNull(), "sandboxPolicy": ["type": "readOnly"]],
            ["approvalPolicy": "never", "sandboxPolicy": ["type": "unknown"]]
        ]
        for value in invalid {
            let data = try JSONSerialization.data(withJSONObject: value)
            XCTAssertThrowsError(try CodexDesktopSessionBridge.Settings(encoded: data))
        }
    }

    func testPermissionReadMustUseTheStillCurrentOwner() throws {
        let settings = try CodexDesktopSessionBridge.Settings(encoded: Data("{\"approvalPolicy\":\"on-request\",\"permissions\":\":workspace\"}".utf8))
        var reads = 0
        let bridge = CodexDesktopSessionBridge(exchange: { method, _, _, _ in self.reply(method) }, readSnapshot: { owner in
            reads += 1; XCTAssertEqual(owner.clientID, self.client); return settings
        })
        XCTAssertEqual(try bridge.readSettings(owner: .init(threadID: thread, clientID: client)), settings)
        XCTAssertThrowsError(try bridge.readSettings(owner: .init(threadID: thread, clientID: UUID().uuidString)))
        XCTAssertEqual(reads, 1)
    }

    func testReadbackRequiresOriginalOwnersPendingSettingsBarrier() throws {
        var calls: [String] = []
        let settings = try CodexDesktopSessionBridge.Settings(encoded: Data("{\"approvalPolicy\":\"on-request\",\"permissions\":\":workspace\"}".utf8))
        let bridge = CodexDesktopSessionBridge(exchange: { method, _, version, target in
            calls.append(method)
            if method == "thread-follower-read-model-settings" {
                XCTAssertEqual(version, 1); XCTAssertEqual(target, self.client)
            }
            return self.reply(method)
        }, readSnapshot: { _ in calls.append("snapshot"); return settings })
        _ = try bridge.readSettings(owner: .init(threadID: thread, clientID: client))
        XCTAssertEqual(calls, ["thread-owner-discovery", "thread-follower-read-model-settings", "snapshot"])
        let failed = CodexDesktopSessionBridge(exchange: { method, _, _, _ in
            if method == "thread-follower-read-model-settings" { return ["resultType": "error"] }
            return self.reply(method)
        }, readSnapshot: { _ in XCTFail("An unconfirmed pending-write queue cannot be called restored"); return settings })
        XCTAssertThrowsError(try failed.readSettings(owner: .init(threadID: thread, clientID: client)))
    }

    func testRealSocketRejectsPublicOrSymlinkEndpointBeforeConnecting() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = root.appendingPathComponent("ipc.sock")
        try FileManager.default.createSymbolicLink(at: endpoint, withDestinationURL: URL(fileURLWithPath: "/tmp/nonexistent"))
        XCTAssertThrowsError(try CodexDesktopSessionBridge(socketURL: endpoint).discoverOwner(threadID: thread)) {
            XCTAssertEqual($0 as? CodexDesktopSessionBridge.BridgeError, .untrustedEndpoint)
        }
    }

    func testRealSocketInitializesAsStudioAndReadsFramedOwnerReply() throws {
        // Keep the Unix address short enough for sockaddr_un on macOS.
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("ahakey-ipc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = root.appendingPathComponent("ipc.sock")
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(server, 0)
        defer { close(server) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = endpoint.path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) {
                strcpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), source)
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0); XCTAssertEqual(chmod(endpoint.path, 0o600), 0); XCTAssertEqual(listen(server, 1), 0)
        let finished = expectation(description: "Bounded local desktop fixture")
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            var listener = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
            guard poll(&listener, 1, 4000) > 0 else { return XCTFail("Client did not connect") }
            let peer = accept(server, nil, nil)
            guard peer >= 0 else { return XCTFail("accept failed") }
            defer { close(peer) }
            var timeout = timeval(tv_sec: 4, tv_usec: 0)
            setsockopt(peer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            do {
                for method in ["initialize", "thread-owner-discovery"] {
                    let header = try self.fixtureRead(peer, size: 4)
                    let size = header.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
                    guard (1...4096).contains(size) else { throw NSError(domain: "fixture-frame", code: 1) }
                    let request = try XCTUnwrap(JSONSerialization.jsonObject(with: self.fixtureRead(peer, size: size)) as? [String: Any])
                    XCTAssertEqual(request["method"] as? String, method)
                    if method == "initialize" {
                        XCTAssertEqual((request["params"] as? [String: String])?["clientType"], "ahakey-studio")
                    }
                    var reply = self.reply(method)
                    reply["type"] = "response"; reply["requestId"] = request["requestId"]
                    if method == "initialize" { reply["result"] = ["clientId": self.client] }
                    let bytes = try JSONSerialization.data(withJSONObject: reply)
                    var framed = Data((0..<4).map { UInt8(truncatingIfNeeded: UInt32(bytes.count) >> ($0 * 8)) })
                    framed.append(bytes)
                    // Deliberately send partial headers and payloads.
                    for byte in framed {
                        var byte = byte
                        guard Darwin.write(peer, &byte, 1) == 1 else { throw NSError(domain: "fixture-write", code: 1) }
                    }
                }
            } catch { XCTFail("Desktop IPC fixture: \(error)") }
        }
        let owner = try CodexDesktopSessionBridge(socketURL: endpoint).discoverOwner(threadID: thread)
        XCTAssertEqual(owner, .init(threadID: thread, clientID: client))
        wait(for: [finished], timeout: 6)
    }

    private func fixtureRead(_ fd: Int32, size: Int) throws -> Data {
        var result = Data(count: size), offset = 0
        while offset < size {
            let count = result.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), size - offset) }
            guard count > 0 else { throw NSError(domain: "fixture-read", code: 1) }
            offset += count
        }
        return result
    }

    private func reply(_ method: String) -> [String: Any] {
        ["resultType": "success", "method": method, "handledByClientId": client,
         "result": method == "thread-owner-discovery" ? ["supportsUntrustedAppInput": true] : ["applied": true]]
    }
}
