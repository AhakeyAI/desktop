import Foundation
import Darwin

/// Consent and a write-ahead permission journal shared by App and Agent. Old
/// default-config consent is intentionally not imported. This is storage, not
/// proof that a lever grant is valid or a native operation has completed.
public struct CodexDesktopLeverState {
    public enum StateError: Error { case unavailable, invalid, notConsented, ownerChanged, capacity }
    public struct Lease: Codable, Equatable, Sendable {
        public let owner: CodexDesktopSessionBridge.Owner
        public let baseline: CodexDesktopSessionBridge.Settings
        public let intended: CodexDesktopSessionBridge.Settings
        public let operationID: UUID
        public var acknowledged: Bool
    }
    public struct Snapshot: Codable, Equatable, Sendable {
        public let version: Int
        public var managementEnabled: Bool
        public var leases: [Lease]
    }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("codex-desktop-lever-v1.json") }
    public init(directory: URL = ApprovalAutomationControl.productionDirectory) { self.directory = directory }

    public func snapshot() throws -> Snapshot { try transaction { $0 } }

    /// Revoking consent retains every journal entry until native recovery is
    /// verified; losing a reply is not evidence that a grant never reached Codex.
    public func setManagementEnabled(_ enabled: Bool) throws {
        try transaction { state in state.managementEnabled = enabled; try save(state) }
    }

    /// Persist *before* sending native permissions. Repeated switches retain the
    /// original baseline; a new owner cannot silently inherit an old lease.
    public func prepare(owner: CodexDesktopSessionBridge.Owner,
                        baseline: CodexDesktopSessionBridge.Settings,
                        intended: CodexDesktopSessionBridge.Settings) throws -> Lease {
        try transaction { state in
            guard state.managementEnabled else { throw StateError.notConsented }
            guard UUID(uuidString: owner.threadID) != nil, UUID(uuidString: owner.clientID) != nil else { throw StateError.invalid }
            let index = state.leases.firstIndex { $0.owner.threadID == owner.threadID }
            if let index, state.leases[index].owner != owner { throw StateError.ownerChanged }
            guard index != nil || state.leases.count < 32 else { throw StateError.capacity }
            let lease = Lease(owner: owner, baseline: index.map { state.leases[$0].baseline } ?? baseline,
                intended: intended, operationID: UUID(), acknowledged: false)
            if let index { state.leases[index] = lease } else { state.leases.append(lease) }
            try save(state)
            return lease
        }
    }

    @discardableResult
    public func acknowledge(_ lease: Lease) throws -> Bool {
        try transaction { state in
            guard let index = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.owner == lease.owner }) else { return false }
            state.leases[index].acknowledged = true
            try save(state); return true
        }
    }

    /// The coordinator must independently read back the native baseline first.
    /// An old completion can never clear a newer pending permission operation.
    @discardableResult
    public func removeAfterVerifiedRestore(_ lease: Lease) throws -> Bool {
        try transaction { state in
            guard let index = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.owner == lease.owner }) else { return false }
            state.leases.remove(at: index); try save(state); return true
        }
    }

    private func transaction<T>(_ operation: (inout Snapshot) throws -> T) throws -> T {
        let result: Result<T, Error>? = ApprovalAutomationControl.locked(directory: directory) {
            Result {
                var info = stat()
                guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw StateError.invalid }
                var state = try load()
                return try operation(&state)
            }
        }
        guard let result else { throw StateError.unavailable }
        return try result.get()
    }

    private func load() throws -> Snapshot {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            guard errno == ENOENT else { throw StateError.invalid }
            return Snapshot(version: 1, managementEnabled: false, leases: [])
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size > 0, info.st_size <= 262_144,
              let data = try handle.read(upToCount: 262_145), data.count <= 262_144 else { throw StateError.invalid }
        let state = try JSONDecoder().decode(Snapshot.self, from: data)
        guard state.version == 1, state.leases.count <= 32,
              Set(state.leases.map { $0.owner.threadID }).count == state.leases.count,
              state.leases.allSatisfy({ UUID(uuidString: $0.owner.threadID) != nil && UUID(uuidString: $0.owner.clientID) != nil }) else { throw StateError.invalid }
        return state
    }
    private func save(_ state: Snapshot) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= 262_144 else { throw StateError.capacity }
        try data.write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw StateError.unavailable }
    }
}
