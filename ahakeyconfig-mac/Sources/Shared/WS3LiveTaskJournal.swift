import Foundation
import Darwin

/// Only hashed session identity and an actual hook event, never prompt/tool text.
public struct WS3LiveTaskEvent: Codable, Equatable, Sendable {
    public let reference: String
    public let client: WS3TaskClient
    public let event: String
    public let state: UInt8
    public let uptime: TimeInterval
    public init(metadata: WS3TaskMetadata, state: UInt8, uptime: TimeInterval) {
        reference = metadata.reference; client = metadata.client; event = metadata.event
        self.state = state; self.uptime = uptime
    }
    public func isValid(at now: TimeInterval) -> Bool {
        reference.utf8.count == 64 && reference.allSatisfy { $0.isASCII && $0.isHexDigit } &&
            !event.isEmpty && event.utf8.count <= 64 && event != "SubagentStop" && state <= 8 &&
            uptime.isFinite && now.isFinite && uptime <= now && now - uptime <= 5
    }
}

/// An explicitly activated App connection owns a nonce. Producers publish only
/// while that reader is alive. Nothing is replayed into a subsequent connection.
public enum WS3LiveTaskJournal {
    public struct Lease: Codable, Equatable, Sendable {
        public let nonce: UUID
        public let processID: Int32
        public let startedAt: TimeInterval
    }
    public struct Batch: Codable, Sendable {
        public let nonce: UUID
        public var sequence: UInt64
        public var events: [WS3LiveTaskEvent]
    }
    public static var productionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AhaKeyConfig/live-task-events")
    }
    public static func begin(directory: URL = productionDirectory, now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> Lease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lease = Lease(nonce: UUID(), processID: getpid(), startedAt: now)
        guard try locked(directory: directory, action: {
            let previous: Lease? = decode(directory.appendingPathComponent("reader.json"), maximum: 1024)
            try encode(Batch(nonce: lease.nonce, sequence: 0, events: []), to: directory.appendingPathComponent("events.json"))
            try encode(lease, to: leaseURL(lease, directory: directory))
            try encode(lease, to: directory.appendingPathComponent("reader.json"))
            if let previous { try? FileManager.default.removeItem(at: leaseURL(previous, directory: directory)) }
            return true
        }) == true else { throw CocoaError(.fileLocking) }
        return lease
    }
    public static func end(_ lease: Lease, directory: URL = productionDirectory) {
        // Revocation cannot be skipped when a producer holds the nonblocking
        // journal lock. The nonce-specific path cannot remove a newer lease.
        try? FileManager.default.removeItem(at: leaseURL(lease, directory: directory))
        _ = try? locked(directory: directory) {
            guard let active: Lease = decode(directory.appendingPathComponent("reader.json"), maximum: 1024), active == lease else { return false }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("reader.json"))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("events.json"))
            return true
        }
    }
    @discardableResult
    public static func publish(request: [String: Any], directory: URL = productionDirectory,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let command = request["cmd"] as? String, ["state", "state_with_reset", "permission"].contains(command),
              let task = request["task"] as? [String: String], let metadata = WS3TaskMetadata(dictionary: task),
              let state = request["value"] as? Int, (0...8).contains(state) else { return false }
        let event = WS3LiveTaskEvent(metadata: metadata, state: UInt8(state), uptime: now)
        guard event.isValid(at: now) else { return false }
        return (try? locked(directory: directory) {
            guard let lease: Lease = decode(directory.appendingPathComponent("reader.json"), maximum: 1024),
                  let live: Lease = decode(leaseURL(lease, directory: directory), maximum: 1024), live == lease,
                  lease.processID > 0, kill(lease.processID, 0) == 0, now >= lease.startedAt,
                  var batch: Batch = decode(directory.appendingPathComponent("events.json"), maximum: 65_536),
                  batch.nonce == lease.nonce, batch.events.count <= 64, batch.sequence < UInt64.max else { return false }
            batch.events.removeAll { !$0.isValid(at: now) }
            if batch.events.count == 64 { batch.events.removeFirst() }
            batch.events.append(event); batch.sequence += 1
            try encode(batch, to: directory.appendingPathComponent("events.json"))
            return true
        }) ?? false
    }
    public static func read(_ lease: Lease, directory: URL = productionDirectory) -> Batch? {
        (try? locked(directory: directory) {
            guard let active: Lease = decode(directory.appendingPathComponent("reader.json"), maximum: 1024), active == lease,
                  let live: Lease = decode(leaseURL(lease, directory: directory), maximum: 1024), live == lease,
                  let batch: Batch = decode(directory.appendingPathComponent("events.json"), maximum: 65_536),
                  batch.nonce == lease.nonce, batch.events.count <= 64 else { return nil }
            return batch
        }) ?? nil
    }
    private static func leaseURL(_ lease: Lease, directory: URL) -> URL {
        directory.appendingPathComponent("lease-\(lease.nonce.uuidString).json")
    }
    private static func locked<T>(directory: URL, action: () throws -> T) throws -> T? {
        let fd = open(directory.appendingPathComponent("journal.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    private static func decode<T: Decodable>(_ url: URL, maximum: Int) -> T? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximum,
              let data = try? Data(contentsOf: url), data.count <= maximum else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private static func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
