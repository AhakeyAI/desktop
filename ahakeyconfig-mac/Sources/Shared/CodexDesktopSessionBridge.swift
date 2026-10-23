import Foundation
import Darwin

/// Desktop coordination IPC, not an independently launched app-server. A caller
/// must obtain consent and verified lever authority before submitting a change.
/// This experimental transport deliberately has no resume/start/config fallback.
public final class CodexDesktopSessionBridge {
    public enum BridgeError: Error, Equatable {
        case unavailable, untrustedEndpoint, invalidTarget, invalidFrame, timedOut
        case rejected, ownerChanged, notApplied, invalidSettings
    }
    public struct Owner: Equatable, Codable, Sendable {
        public let threadID: String
        public let clientID: String
        public init(threadID: String, clientID: String) {
            self.threadID = threadID; self.clientID = clientID
        }
    }
    public enum PermissionMode: Equatable, Sendable {
        case fullAccess
        /// Use a profile read from the owning runtime, not an invented profile.
        case requestedApproval(profileID: String)
    }
    /// A minimal permission baseline; never persists the conversation snapshot.
    public struct Settings: Equatable, Codable, Sendable {
        public let encoded: Data
        public init(encoded: Data) throws {
            guard let value = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
                  value.count == 2, Set(value.keys).isSubset(of: ["approvalPolicy", "permissions", "sandboxPolicy"]),
                  let approval = value["approvalPolicy"],
                  (["never", "on-request", "untrusted"].contains(approval as? String ?? "") || approval is [String: Any]) else {
                throw BridgeError.invalidSettings
            }
            let profile = value["permissions"] as? String
            let sandbox = value["sandboxPolicy"] as? [String: Any]
            guard (profile != nil) != (sandbox != nil),
                  profile.map({ !$0.isEmpty && $0.utf8.count <= 256 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) ?? true,
                  sandbox.map({ ["dangerFullAccess", "workspaceWrite", "readOnly", "externalSandbox"].contains($0["type"] as? String ?? "") }) ?? true else {
                throw BridgeError.invalidSettings
            }
            self.encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        }
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            try self.init(encoded: container.decode(Data.self))
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer(); try container.encode(encoded)
        }
        public static var fullAccess: Settings {
            // These fixed native settings have no fallible user input.
            try! Settings(encoded: Data("{\"approvalPolicy\":\"never\",\"permissions\":\":danger-full-access\"}".utf8))
        }
        public func requestingApproval() throws -> Settings {
            var value = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            if let profile = value["permissions"] as? String {
                guard [":danger-full-access", ":workspace", ":read-only"].contains(profile) else { throw BridgeError.invalidSettings }
                if profile == ":danger-full-access" { value["permissions"] = ":workspace" }
            } else if let sandbox = value["sandboxPolicy"] as? [String: Any] {
                switch sandbox["type"] as? String {
                case "workspaceWrite", "readOnly": break // Retain the exact custom restricted range.
                case "dangerFullAccess": value.removeValue(forKey: "sandboxPolicy"); value["permissions"] = ":workspace"
                default: throw BridgeError.invalidSettings
                }
            }
            value["approvalPolicy"] = "on-request"
            return try Settings(encoded: JSONSerialization.data(withJSONObject: value))
        }
    }
    private let exchange: (String, [String: Any], Int, String?) throws -> [String: Any]
    private let readSnapshot: (Owner) throws -> Settings

    /// One connection per operation. Use off the main actor; each operation has
    /// a bounded deadline and only accepts the exact owner acknowledgement.
    public init(socketURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/ipc/ipc.sock")) {
        exchange = { method, parameters, version, owner in
            let channel = try CodexDesktopIPCChannel(url: socketURL)
            try channel.initialize()
            return try channel.request(method, parameters, version: version, target: owner)
        }
        readSnapshot = { owner in
            try autoreleasepool {
                let channel = try CodexDesktopIPCChannel(url: socketURL)
                try channel.initialize()
                return try channel.readSettings(owner: owner)
            }
        }
    }

    init(exchange: @escaping (String, [String: Any], Int, String?) throws -> [String: Any],
         readSnapshot: @escaping (Owner) throws -> Settings = { _ in throw BridgeError.unavailable }) {
        self.exchange = exchange; self.readSnapshot = readSnapshot
    }

    public func readSettings(owner: Owner) throws -> Settings {
        guard try discoverOwner(threadID: owner.threadID) == owner else { throw BridgeError.ownerChanged }
        // The desktop's getter first awaits pending thread settings updates.
        // A snapshot without this barrier can precede a write whose reply was
        // lost, making recovery incorrectly conclude that nothing was applied.
        let barrier = try exchange("thread-follower-read-model-settings", ["conversationId": owner.threadID], 1, owner.clientID)
        guard barrier["resultType"] as? String == "success",
              barrier["method"] as? String == "thread-follower-read-model-settings",
              barrier["handledByClientId"] as? String == owner.clientID else { throw BridgeError.notApplied }
        return try readSnapshot(owner)
    }

    public func discoverOwner(threadID: String) throws -> Owner {
        guard UUID(uuidString: threadID) != nil else { throw BridgeError.invalidTarget }
        let reply = try exchange("thread-owner-discovery", ["hostId": "local", "conversationId": threadID], 1, nil)
        guard reply["resultType"] as? String == "success",
              reply["method"] as? String == "thread-owner-discovery",
              let client = reply["handledByClientId"] as? String, UUID(uuidString: client) != nil else {
            throw BridgeError.unavailable
        }
        return Owner(threadID: threadID, clientID: client)
    }

    /// The acknowledgement means the original desktop accepted the settings for
    /// subsequent turns. It does not change a running turn or prove BLE state.
    public func updateNextTurn(owner: Owner, mode: PermissionMode) throws {
        guard UUID(uuidString: owner.threadID) != nil, UUID(uuidString: owner.clientID) != nil else {
            throw BridgeError.invalidTarget
        }
        let settings: [String: Any]
        switch mode {
        case .fullAccess:
            settings = ["approvalPolicy": "never", "permissions": ":danger-full-access"]
        case .requestedApproval(let profile):
            guard !profile.isEmpty, profile != ":danger-full-access", profile.utf8.count <= 256,
                  !profile.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw BridgeError.invalidTarget
            }
            settings = ["approvalPolicy": "on-request", "permissions": profile]
        }
        try updateNextTurn(owner: owner, settings: Settings(encoded: JSONSerialization.data(withJSONObject: settings)))
    }

    /// Also supports restoring an exact restricted sandbox baseline, including
    /// custom writable roots, rather than substituting the default workspace.
    public func updateNextTurn(owner: Owner, settings: Settings) throws {
        guard UUID(uuidString: owner.threadID) != nil, UUID(uuidString: owner.clientID) != nil else { throw BridgeError.invalidTarget }
        // Re-resolve instead of resuming a copy in another server after restart.
        guard try discoverOwner(threadID: owner.threadID) == owner else { throw BridgeError.ownerChanged }
        let value = try JSONSerialization.jsonObject(with: settings.encoded)
        let reply = try exchange("thread-follower-update-thread-settings",
            ["conversationId": owner.threadID, "threadSettings": value], 2, owner.clientID)
        guard reply["resultType"] as? String == "success",
              reply["method"] as? String == "thread-follower-update-thread-settings" else { throw BridgeError.rejected }
        guard reply["handledByClientId"] as? String == owner.clientID else { throw BridgeError.ownerChanged }
        guard (reply["result"] as? [String: Any])?["applied"] as? Bool == true else { throw BridgeError.notApplied }
    }
}

/// Bounded little-endian JSON framing used by the desktop's same-user router.
/// No capability tokens or authentication files are read. A one-shot state
/// subscription discards all conversation data except permission metadata.
private final class CodexDesktopIPCChannel {
    typealias Failure = CodexDesktopSessionBridge.BridgeError
    private var fd: Int32 = -1
    private let deadline = ProcessInfo.processInfo.systemUptime + 6
    private var clientID = "initializing-client"
    private static let frameLimit = 1_048_576

    init(url: URL) throws {
        let path = url.path
        var parent = stat(), endpoint = stat(), address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path),
              lstat(url.deletingLastPathComponent().path, &parent) == 0,
              lstat(path, &endpoint) == 0 else { throw Failure.unavailable }
        guard parent.st_mode & S_IFMT == S_IFDIR, endpoint.st_mode & S_IFMT == S_IFSOCK,
              parent.st_uid == getuid(), endpoint.st_uid == getuid(),
              parent.st_mode & 0o077 == 0, endpoint.st_mode & 0o077 == 0 else { throw Failure.untrustedEndpoint }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw Failure.unavailable }
        fd = socketFD
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        address.sun_family = sa_family_t(AF_UNIX)
        _ = path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) {
                strcpy(UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self), source)
            }
        }
        // Nonblocking connect avoids hanging on a saturated local listener.
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 { close(fd); fd = -1; throw Failure.unavailable }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
            close(fd); fd = -1; throw Failure.untrustedEndpoint
        }
    }
    deinit { if fd >= 0 { close(fd) } }

    func initialize() throws {
        let reply = try request("initialize", ["clientType": "ahakey-studio"], version: 0)
        guard reply["resultType"] as? String == "success", reply["method"] as? String == "initialize",
              let id = (reply["result"] as? [String: Any])?["clientId"] as? String,
              UUID(uuidString: id) != nil else { throw Failure.rejected }
        clientID = id
    }

    func request(_ method: String, _ params: [String: Any], version: Int, target: String? = nil) throws -> [String: Any] {
        let id = UUID().uuidString
        var body: [String: Any] = ["type": "request", "requestId": id, "sourceClientId": clientID,
            "version": version, "method": method, "params": params, "timeoutMs": 3000]
        if let target { body["targetClientId"] = target }
        try send(body)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let reply = try receive()
            if reply["type"] as? String == "response", reply["requestId"] as? String == id { return reply }
        }
        throw Failure.timedOut
    }

    func readSettings(owner: CodexDesktopSessionBridge.Owner) throws -> CodexDesktopSessionBridge.Settings {
        func follow(_ enabled: Bool) throws {
            try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
                "sourceClientId": clientID, "targetClientIds": [owner.clientID],
                "params": ["hostId": "local", "conversationId": owner.threadID, "following": enabled]])
        }
        try follow(true)
        defer { try? follow(false) } // Socket close also removes the follower.
        while ProcessInfo.processInfo.systemUptime < deadline {
            // The original desktop currently offers a full snapshot rather than
            // a permission-only read. Never poll this path or retain its body.
            let reply = try receive(maximum: 64 * 1024 * 1024)
            guard reply["type"] as? String == "broadcast",
                  reply["method"] as? String == "thread-stream-state-changed",
                  reply["version"] as? Int == 11,
                  reply["sourceClientId"] as? String == owner.clientID,
                  let params = reply["params"] as? [String: Any],
                  params["hostId"] as? String == "local", params["conversationId"] as? String == owner.threadID,
                  let change = params["change"] as? [String: Any], change["type"] as? String == "snapshot",
                  let state = change["conversationState"] as? [String: Any], state["id"] as? String == owner.threadID,
                  let settings = state["latestThreadSettings"] as? [String: Any], let approval = settings["approvalPolicy"] else { continue }
            var value: [String: Any] = ["approvalPolicy": approval]
            if let profile = (settings["activePermissionProfile"] as? [String: Any])?["id"] as? String {
                value["permissions"] = profile
            } else if let profile = settings["permissions"] as? String {
                value["permissions"] = profile
            } else if let sandbox = settings["sandboxPolicy"] as? [String: Any] {
                value["sandboxPolicy"] = sandbox
            }
            return try CodexDesktopSessionBridge.Settings(encoded: JSONSerialization.data(withJSONObject: value))
        }
        throw Failure.timedOut
    }

    private func receive(maximum: Int = frameLimit) throws -> [String: Any] {
        let header = try readExactly(4)
        let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        guard size > 0, size <= maximum else { throw Failure.invalidFrame }
        guard let reply = try JSONSerialization.jsonObject(with: readExactly(Int(size))) as? [String: Any] else { throw Failure.invalidFrame }
        // This bridge never advertises itself as a session owner or accepts
        // inbound commands. Answer discovery even while waiting for a snapshot.
        if reply["type"] as? String == "client-discovery-request", let requestID = reply["requestId"] as? String {
            try send(["type": "client-discovery-response", "requestId": requestID, "response": ["canHandle": false]])
        }
        return reply
    }

    private func wait(_ events: Int16) throws {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw Failure.timedOut }
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let count = poll(&descriptor, 1, Int32(min(6000, ceil(remaining * 1000))))
        guard count > 0 else { throw Failure.timedOut }
        guard descriptor.revents & events != 0 else { throw Failure.unavailable }
    }
    private func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= Self.frameLimit else { throw Failure.invalidFrame }
        let n = UInt32(data.count)
        var framed = Data((0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) })
        framed.append(data)
        var offset = 0
        while offset < framed.count {
            try wait(Int16(POLLOUT))
            let count = framed.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), framed.count - offset) }
            if count < 0, errno == EAGAIN || errno == EINTR { continue }
            guard count > 0 else { throw Failure.unavailable }; offset += count
        }
    }
    private func readExactly(_ size: Int) throws -> Data {
        var data = Data(count: size), offset = 0
        while offset < size {
            try wait(Int16(POLLIN))
            let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), size - offset) }
            if count < 0, errno == EAGAIN || errno == EINTR { continue }
            guard count > 0 else { throw Failure.unavailable }; offset += count
        }
        return data
    }
}
