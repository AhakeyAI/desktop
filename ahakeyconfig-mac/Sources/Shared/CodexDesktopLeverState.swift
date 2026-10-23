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
        /// A previous submitted value may still be live when the next write's
        /// acknowledgement is lost. Keep it distinguishable from a user edit.
        public let possibleOwnedSettings: [CodexDesktopSessionBridge.Settings]
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
    public func hasPendingRecovery() throws -> Bool {
        var info = stat()
        if lstat(file.path, &info) != 0 {
            guard errno == ENOENT else { throw StateError.invalid }
            return false
        }
        return try !snapshot().leases.isEmpty
    }

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
            var possible = index.map { state.leases[$0].possibleOwnedSettings } ?? []
            if !possible.contains(intended) { possible.append(intended) }
            guard possible.count <= 8 else { throw StateError.capacity }
            let lease = Lease(owner: owner, baseline: index.map { state.leases[$0].baseline } ?? baseline,
                intended: intended, operationID: UUID(), acknowledged: false, possibleOwnedSettings: possible)
            if let index { state.leases[index] = lease } else { state.leases.append(lease) }
            try save(state)
            return lease
        }
    }

    @discardableResult
    public func acknowledge(_ lease: Lease) throws -> Bool {
        try transaction { state in
            guard let index = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.owner == lease.owner }) else { return false }
            // Called only after the owner's pending-update barrier and exact
            // native readback. Older possible values are no longer outstanding;
            // retaining them would hide a later user change to an ordinary mode.
            let value = state.leases[index]
            state.leases[index] = Lease(owner: value.owner, baseline: value.baseline, intended: value.intended,
                operationID: value.operationID, acknowledged: true, possibleOwnedSettings: [value.intended])
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

    /// Drop ownership only after a native read proves that the user selected a
    /// value outside every value this lease might have submitted.
    @discardableResult
    public func removeAfterExternalChange(_ lease: Lease, observed: CodexDesktopSessionBridge.Settings) throws -> Bool {
        if lease.acknowledged {
            guard observed != lease.intended else { return false }
        } else {
            guard observed != lease.baseline, !lease.possibleOwnedSettings.contains(observed) else { return false }
        }
        return try removeAfterVerifiedRestore(lease)
    }

    public func rebindForRecovery(_ lease: Lease, to owner: CodexDesktopSessionBridge.Owner,
                                  observed: CodexDesktopSessionBridge.Settings) throws -> Lease {
        try transaction { state in
            guard owner.threadID == lease.owner.threadID, UUID(uuidString: owner.clientID) != nil,
                  observed == lease.baseline || lease.possibleOwnedSettings.contains(observed),
                  let index = state.leases.firstIndex(where: { $0.operationID == lease.operationID && $0.owner == lease.owner }) else { throw StateError.ownerChanged }
            let rebound = Lease(owner: owner, baseline: lease.baseline, intended: lease.intended,
                operationID: UUID(), acknowledged: false, possibleOwnedSettings: lease.possibleOwnedSettings)
            state.leases[index] = rebound; try save(state); return rebound
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
              state.leases.allSatisfy({ UUID(uuidString: $0.owner.threadID) != nil && UUID(uuidString: $0.owner.clientID) != nil &&
                  !$0.possibleOwnedSettings.isEmpty && $0.possibleOwnedSettings.count <= 8 && $0.possibleOwnedSettings.contains($0.intended) }) else { throw StateError.invalid }
        return state
    }
    private func save(_ state: Snapshot) throws {
        let data = try JSONEncoder().encode(state)
        guard data.count <= 262_144 else { throw StateError.capacity }
        try data.write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw StateError.unavailable }
    }
}

extension CodexDesktopLeverState.Lease {
    private enum CodingKeys: String, CodingKey { case owner, baseline, intended, operationID, acknowledged, possibleOwnedSettings }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        owner = try values.decode(CodexDesktopSessionBridge.Owner.self, forKey: .owner)
        baseline = try values.decode(CodexDesktopSessionBridge.Settings.self, forKey: .baseline)
        intended = try values.decode(CodexDesktopSessionBridge.Settings.self, forKey: .intended)
        operationID = try values.decode(UUID.self, forKey: .operationID)
        acknowledged = try values.decode(Bool.self, forKey: .acknowledged)
        possibleOwnedSettings = try values.decodeIfPresent([CodexDesktopSessionBridge.Settings].self, forKey: .possibleOwnedSettings) ?? [intended]
    }
}
