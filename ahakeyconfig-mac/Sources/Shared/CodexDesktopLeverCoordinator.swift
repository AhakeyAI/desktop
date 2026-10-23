import Foundation

/// One serial reconciliation worker. A physical hint schedules work; only a
/// fresh Agent proof can authorize full access. Repeated identical hints never
/// poll the desktop's expensive conversation-snapshot path.
public actor CodexDesktopLeverCoordinator {
    public enum Authority: Equatable, Sendable { case verifiedAutomatic, manual, unmanaged }
    public enum Outcome: String, Sendable { case nextTurn, restored, externalChange, unchanged, unmanaged, notSynchronized }
    public struct Dependencies: Sendable {
        public var discover: @Sendable (String) async throws -> CodexDesktopSessionBridge.Owner
        public var read: @Sendable (CodexDesktopSessionBridge.Owner) async throws -> CodexDesktopSessionBridge.Settings
        public var write: @Sendable (CodexDesktopSessionBridge.Owner, CodexDesktopSessionBridge.Settings) async throws -> Void
        public var authority: @Sendable () async -> Authority
        public var controlEnabled: @Sendable () -> Bool
        public init(authority: @escaping @Sendable () async -> Authority,
                    controlEnabled: @escaping @Sendable () -> Bool = { ApprovalAutomationControl.isEnabled(.codex) },
                    discover: @escaping @Sendable (String) async throws -> CodexDesktopSessionBridge.Owner = { id in
                        try await Task.detached { try CodexDesktopSessionBridge().discoverOwner(threadID: id) }.value
                    }, read: @escaping @Sendable (CodexDesktopSessionBridge.Owner) async throws -> CodexDesktopSessionBridge.Settings = { owner in
                        try await Task.detached { try CodexDesktopSessionBridge().readSettings(owner: owner) }.value
                    }, write: @escaping @Sendable (CodexDesktopSessionBridge.Owner, CodexDesktopSessionBridge.Settings) async throws -> Void = { owner, settings in
                        try await Task.detached { try CodexDesktopSessionBridge().updateNextTurn(owner: owner, settings: settings) }.value
                    }) {
            self.authority = authority; self.controlEnabled = controlEnabled
            self.discover = discover; self.read = read; self.write = write
        }
    }
    private struct Signal: Equatable {
        let threads: Set<String>
        let hint: Authority
        let epoch: UInt64
        let enabled: Bool
        let control: Bool
    }
    private let state: CodexDesktopLeverState
    private let dependencies: Dependencies
    private var requested: Signal?
    private var revision: UInt64 = 0
    private var running = false
    private var heldForUserChange = Set<String>()
    private var outcomes: [String: Outcome] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    public var isRunning: Bool { running }
    public func waitUntilIdle() async {
        if running { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    public init(state: CodexDesktopLeverState = .init(), dependencies: Dependencies) {
        self.state = state; self.dependencies = dependencies
    }

    /// Concurrent requests coalesce into the latest signal. `retry` is for a
    /// bounded recovery schedule, not a high-frequency status/UI heartbeat.
    @discardableResult
    public func reconcile(threadIDs: [String], hint: Authority, epoch: UInt64, retry: Bool = false) async -> [String: Outcome] {
        let snapshot: CodexDesktopLeverState.Snapshot
        do { snapshot = try state.snapshot() } catch { return ["storage": .notSynchronized] }
        let ids = Set(threadIDs.filter { UUID(uuidString: $0) != nil }).union(snapshot.leases.map { $0.owner.threadID })
        guard ids.count <= 32 else { return ["capacity": .notSynchronized] }
        let next = Signal(threads: ids, hint: hint, epoch: epoch, enabled: snapshot.managementEnabled, control: dependencies.controlEnabled())
        guard retry || requested != next else { return outcomes }
        if requested?.hint != hint || requested?.epoch != epoch || requested?.enabled != next.enabled {
            heldForUserChange.removeAll()
        }
        requested = next; revision &+= 1
        outcomes = outcomes.filter { ids.contains($0.key) }
        guard !running else { return outcomes }
        running = true
        defer {
            running = false
            let waiters = idleWaiters; idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        var processed: UInt64
        var passes = 0
        repeat {
            passes += 1
            guard passes <= 4 else {
                for id in requested?.threads ?? [] { outcomes[id] = .notSynchronized }
                break
            }
            processed = revision
            guard let signal = requested else { break }
            let owned = Set((try? state.snapshot().leases.map { $0.owner.threadID }) ?? [])
            let ordered = signal.threads.sorted { left, right in
                if owned.contains(left) != owned.contains(right) { return owned.contains(left) }
                return left < right
            }
            for id in ordered {
                guard processed == revision else { break }
                do { try await synchronize(id, signal: signal, revision: processed) }
                catch { if processed == revision { outcomes[id] = .notSynchronized } }
            }
        } while processed != revision
        return outcomes
    }

    private func synchronize(_ id: String, signal: Signal, revision token: UInt64) async throws {
        var snapshot = try state.snapshot()
        var lease = snapshot.leases.first { $0.owner.threadID == id }
        let managed = signal.enabled && signal.control && snapshot.managementEnabled && dependencies.controlEnabled()
        if !managed && lease == nil { outcomes[id] = .unmanaged; return }
        if heldForUserChange.contains(id), lease == nil { outcomes[id] = .externalChange; return }
        let authority = managed && signal.hint != .unmanaged ? await dependencies.authority() : .unmanaged
        guard token == revision else { return }
        if authority == .unmanaged && lease == nil { outcomes[id] = .unmanaged; return }
        let owner = try await dependencies.discover(id)
        guard token == revision else { return }
        let current = try await dependencies.read(owner)
        guard token == revision else { return }
        if let existing = lease {
            let externallyChanged = existing.acknowledged ? current != existing.intended :
                current != existing.baseline && !existing.possibleOwnedSettings.contains(current)
            if externallyChanged {
                guard try state.removeAfterExternalChange(existing, observed: current) else { throw CodexDesktopSessionBridge.BridgeError.ownerChanged }
                heldForUserChange.insert(id); outcomes[id] = .externalChange; return
            }
            if existing.owner != owner {
                lease = try state.rebindForRecovery(existing, to: owner, observed: current)
            }
        }
        let baseline = lease?.baseline ?? current
        let desired: CodexDesktopSessionBridge.Settings
        switch authority {
        case .verifiedAutomatic:
            _ = try baseline.requestingApproval() // Do not grant a profile we cannot later return to manual.
            desired = .fullAccess
        case .manual: desired = try baseline.requestingApproval()
        case .unmanaged: desired = baseline
        }
        if current == desired {
            if let lease {
                if authority == .unmanaged { _ = try state.removeAfterVerifiedRestore(lease) }
                else if current == lease.intended { _ = try state.acknowledge(lease) }
            }
            outcomes[id] = authority == .unmanaged ? .restored : .unchanged
            return
        }
        snapshot = try state.snapshot()
        // Consent may have been revoked while reading the original desktop.
        if authority != .unmanaged && (!snapshot.managementEnabled || !dependencies.controlEnabled()) {
            revision &+= 1; return
        }
        if authority != .unmanaged {
            guard await dependencies.authority() == authority, token == revision else { revision &+= 1; return }
            lease = try state.prepare(owner: owner, baseline: baseline, intended: desired)
        }
        guard let operation = lease else { throw CodexDesktopSessionBridge.BridgeError.notApplied }
        guard token == revision else { return }
        // A lost reply is ambiguous. Independent native readback, rather than a
        // transport error alone, decides whether the original desktop applied it.
        do { try await dependencies.write(owner, desired) } catch { /* Keep the write-ahead recovery record. */ }
        guard token == revision else { return }
        let actual = try await dependencies.read(owner)
        guard token == revision else { return }
        guard actual == desired else { throw CodexDesktopSessionBridge.BridgeError.notApplied }
        if authority == .unmanaged {
            guard try state.removeAfterVerifiedRestore(operation) else { throw CodexDesktopSessionBridge.BridgeError.ownerChanged }
            outcomes[id] = .restored
        } else {
            guard try state.acknowledge(operation) else { throw CodexDesktopSessionBridge.BridgeError.ownerChanged }
            let latestAuthority = await dependencies.authority()
            if !(try state.snapshot().managementEnabled) || !dependencies.controlEnabled() || latestAuthority != authority {
                revision &+= 1; return
            }
            outcomes[id] = .nextTurn
        }
    }
}
