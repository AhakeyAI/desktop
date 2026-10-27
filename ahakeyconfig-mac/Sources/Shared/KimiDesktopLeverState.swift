import Foundation
import Darwin

/// Minimal same-user consent and write-ahead recovery facts. No transcripts,
/// service credentials or generic Kimi defaults are stored in this journal.
public struct KimiDesktopLeverState: Sendable {
    public enum Failure: Error { case invalid, unavailable, unauthorized, capacity, staleOperation }
    public struct Target: Codable, Hashable, Sendable {
        public let home: String
        public let sessionID: String
        public init(home: String, sessionID: String) throws {
            guard Self.valid(home: home, id: sessionID) else { throw Failure.invalid }
            self.home = home; self.sessionID = sessionID
        }
        fileprivate static func valid(home: String, id: String) -> Bool {
            home.hasPrefix("/") && home.utf8.count <= 4096 && !home.contains("\0") &&
                URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path == home &&
                KimiDesktopPermissionBridge.validSessionID(id)
        }
    }
    public struct Grant: Codable, Equatable, Sendable {
        public let target: Target
        public let title: String
        public let preferredServerID: String?
    }
    public struct Lease: Codable, Equatable, Sendable {
        public let target: Target
        public let baseline: KimiDesktopPermissionBridge.Mode
        public let intended: KimiDesktopPermissionBridge.Mode
        public let operationID: UUID
        public let acknowledged: Bool
        public let possibleOwnedModes: [KimiDesktopPermissionBridge.Mode]
        public let preferredServerID: String?
    }
    public struct Override: Codable, Equatable, Sendable {
        public let target: Target
        public let heldWhileDesired: KimiDesktopPermissionBridge.Mode
    }
    public struct Snapshot: Codable, Equatable, Sendable {
        public let version: Int
        public var grants: [Grant]
        public var leases: [Lease]
        public var overrides: [Override]
    }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("kimi-desktop-lever-v1.json") }
    public init(directory: URL = ApprovalAutomationControl.productionDirectory) { self.directory = directory }
    public func snapshot() throws -> Snapshot { try transaction { $0 } }
    public func hasPendingRecovery() throws -> Bool {
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw Failure.invalid }
            return false
        }
        return try !snapshot().leases.isEmpty
    }
    public func authorize(_ target: Target, title: String, preferredServerID: String? = nil) throws {
        guard Target.valid(home: target.home, id: target.sessionID), title.utf8.count <= 2048,
              Self.validServerID(preferredServerID) else { throw Failure.invalid }
        try transaction { state in
            guard state.grants.contains(where: { $0.target == target }) || state.grants.count < 32 else { throw Failure.capacity }
            state.grants.removeAll { $0.target == target }
            state.overrides.removeAll { $0.target == target }
            state.grants.append(Grant(target: target, title: title, preferredServerID: preferredServerID))
            try save(state)
        }
    }
    /// Revocation never deletes a pending recovery record.
    public func revoke(_ target: Target) throws {
        try transaction { state in
            state.grants.removeAll { $0.target == target }; state.overrides.removeAll { $0.target == target }; try save(state)
        }
    }
    public func prepare(_ target: Target, baseline: KimiDesktopPermissionBridge.Mode,
                        intended: KimiDesktopPermissionBridge.Mode) throws -> Lease {
        try transaction { state in
            guard let grant = state.grants.first(where: { $0.target == target }) else { throw Failure.unauthorized }
            let index = state.leases.firstIndex { $0.target == target }
            guard index != nil || state.leases.count < 32 else { throw Failure.capacity }
            var possible = index.map { state.leases[$0].possibleOwnedModes } ?? []
            if !possible.contains(intended) { possible.append(intended) }
            let lease = Lease(target: target, baseline: index.map { state.leases[$0].baseline } ?? baseline,
                intended: intended, operationID: UUID(), acknowledged: false, possibleOwnedModes: possible, preferredServerID: grant.preferredServerID)
            if let index { state.leases[index] = lease } else { state.leases.append(lease) }
            try save(state); return lease
        }
    }
    @discardableResult
    public func acknowledge(_ lease: Lease) throws -> Bool {
        try transaction { state in
            guard let i = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.target == lease.target }) else { return false }
            let current = state.leases[i]
            state.leases[i] = Lease(target: current.target, baseline: current.baseline, intended: current.intended,
                operationID: current.operationID, acknowledged: true, possibleOwnedModes: [current.intended], preferredServerID: current.preferredServerID)
            try save(state); return true
        }
    }
    /// Call only after independent native readback of the original baseline.
    @discardableResult
    public func removeAfterVerifiedRestore(_ lease: Lease) throws -> Bool {
        try transaction { state in
            guard let i = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.target == lease.target }) else { return false }
            state.leases.remove(at: i); try save(state); return true
        }
    }
    @discardableResult
    public func removeAfterExternalChange(_ lease: Lease, observed: KimiDesktopPermissionBridge.Mode, holdWhileDesired: KimiDesktopPermissionBridge.Mode? = nil) throws -> Bool {
        if lease.acknowledged { guard observed != lease.intended else { return false } }
        else { guard observed != lease.baseline && !lease.possibleOwnedModes.contains(observed) else { return false } }
        return try transaction { state in
            guard let i = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.target == lease.target }) else { return false }
            state.leases.remove(at: i)
            if let mode = holdWhileDesired, state.grants.contains(where: { $0.target == lease.target }) {
                state.overrides.removeAll { $0.target == lease.target }
                state.overrides.append(Override(target: lease.target, heldWhileDesired: mode))
            }
            try save(state); return true
        }
    }
    public func clearOverride(_ target: Target) throws {
        try transaction { state in state.overrides.removeAll { $0.target == target }; try save(state) }
    }
    private func transaction<T>(_ body: (inout Snapshot) throws -> T) throws -> T {
        let result: Result<T, Error>? = ApprovalAutomationControl.locked(directory: directory) {
            Result {
                var info = stat()
                guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw Failure.invalid }
                var state = try load()
                return try body(&state)
            }
        }
        guard let result else { throw Failure.unavailable }
        return try result.get()
    }
    private func load() throws -> Snapshot {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            guard errno == ENOENT else { throw Failure.invalid }
            return Snapshot(version: 1, grants: [], leases: [], overrides: [])
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size > 0, info.st_size <= 262_144,
              let bytes = try handle.read(upToCount: 262_145), bytes.count <= 262_144 else { throw Failure.invalid }
        let state = try JSONDecoder().decode(Snapshot.self, from: bytes)
        guard state.version == 1, state.grants.count <= 32, state.leases.count <= 32, state.overrides.count <= 32,
              Set(state.overrides.map(\.target)).count == state.overrides.count,
              state.overrides.allSatisfy({ override in Target.valid(home: override.target.home, id: override.target.sessionID) &&
                  state.grants.contains(where: { $0.target == override.target }) }),
              Set(state.grants.map(\.target)).count == state.grants.count,
              Set(state.leases.map(\.target)).count == state.leases.count,
              state.grants.allSatisfy({ Target.valid(home: $0.target.home, id: $0.target.sessionID) && $0.title.utf8.count <= 2048 && Self.validServerID($0.preferredServerID) }),
              state.leases.allSatisfy({ Target.valid(home: $0.target.home, id: $0.target.sessionID) &&
                  Self.validServerID($0.preferredServerID) && !$0.possibleOwnedModes.isEmpty && $0.possibleOwnedModes.count <= 3 &&
                  Set($0.possibleOwnedModes).count == $0.possibleOwnedModes.count && $0.possibleOwnedModes.contains($0.intended) }) else { throw Failure.invalid }
        return state
    }
    private static func validServerID(_ value: String?) -> Bool {
        guard let value else { return true }
        let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
        return value.utf8.count == 26 && value.utf8.allSatisfy(alphabet.contains)
    }
    private func save(_ state: Snapshot) throws {
        let bytes = try JSONEncoder().encode(state)
        guard bytes.count <= 262_144 else { throw Failure.capacity }
        try bytes.write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw Failure.unavailable }
    }
}
