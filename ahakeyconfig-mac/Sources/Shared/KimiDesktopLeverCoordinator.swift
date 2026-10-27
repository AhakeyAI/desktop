import Foundation

/// Event-driven original-session reconciliation. Defaults, TUI approval stdout,
/// and ordinary Kimi Work are deliberately separate capability paths.
public actor KimiDesktopLeverCoordinator {
    public enum Authority: Equatable, Sendable { case automatic, manual, unmanaged }
    public enum Outcome: String, Sendable { case synchronized, restored, externalChange, unchanged, unmanaged, notSynchronized }
    public struct Dependencies: Sendable {
        public let authority: @Sendable () async -> Authority
        public let controlEnabled: @Sendable () -> Bool
        public let read: @Sendable (KimiDesktopLeverState.Target) async throws -> KimiDesktopPermissionBridge.Mode
        public let write: @Sendable (KimiDesktopLeverState.Lease, KimiDesktopPermissionBridge.Mode, KimiDesktopPermissionBridge.Mode, Bool) async throws -> KimiDesktopPermissionBridge.Receipt
        public init(authority: @escaping @Sendable () async -> Authority,
                    controlEnabled: @escaping @Sendable () -> Bool,
                    read: @escaping @Sendable (KimiDesktopLeverState.Target) async throws -> KimiDesktopPermissionBridge.Mode,
                    write: @escaping @Sendable (KimiDesktopLeverState.Lease, KimiDesktopPermissionBridge.Mode, KimiDesktopPermissionBridge.Mode, Bool) async throws -> KimiDesktopPermissionBridge.Receipt) {
            self.authority = authority; self.controlEnabled = controlEnabled; self.read = read; self.write = write
        }
    }
    private struct Signal: Equatable {
        let targets: Set<KimiDesktopLeverState.Target>
        let granted: Set<KimiDesktopLeverState.Target>
        let hint: Authority
        let epoch: UInt64
        let enabled: Bool
    }
    private let state: KimiDesktopLeverState
    private let dependencies: Dependencies
    private var requested: Signal?
    private var revision: UInt64 = 0
    private var running = false
    private var outcomes: [KimiDesktopLeverState.Target: Outcome] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init(state: KimiDesktopLeverState = .init(), dependencies: Dependencies) { self.state = state; self.dependencies = dependencies }
    public var isRunning: Bool { running }
    public func waitUntilIdle() async { if running { await withCheckedContinuation { waiters.append($0) } } }
    public func reconcile(hint: Authority, epoch: UInt64, retry: Bool = false) async -> [KimiDesktopLeverState.Target: Outcome] {
        let snapshot: KimiDesktopLeverState.Snapshot
        do { snapshot = try state.snapshot() } catch { return outcomes.mapValues { _ in .notSynchronized } }
        let grants = Set(snapshot.grants.map(\.target))
        let signal = Signal(targets: grants.union(snapshot.leases.map(\.target)), granted: grants,
                            hint: hint, epoch: epoch, enabled: dependencies.controlEnabled())
        guard retry || signal != requested else { return outcomes }
        requested = signal; revision &+= 1
        guard !running else { return outcomes }
        running = true
        defer { running = false; let previous = waiters; waiters.removeAll(); previous.forEach { $0.resume() } }
        var processed: UInt64 = 0, passes = 0
        repeat {
            passes += 1
            guard passes <= 4 else {
                for target in requested?.targets ?? [] { outcomes[target] = .notSynchronized }
                break
            }
            guard let current = requested else { break }
            processed = revision
            outcomes = outcomes.filter { current.targets.contains($0.key) }
            for target in current.targets.sorted(by: { ($0.home, $0.sessionID) < ($1.home, $1.sessionID) }) {
                guard processed == revision else { break }
                do { try await synchronize(target, signal: current, token: processed) }
                catch { if processed == revision { outcomes[target] = .notSynchronized } }
            }
        } while processed != revision
        return outcomes
    }
    private func synchronize(_ target: KimiDesktopLeverState.Target, signal: Signal, token: UInt64) async throws {
        var snapshot = try state.snapshot()
        var lease = snapshot.leases.first { $0.target == target }
        let granted = signal.enabled && dependencies.controlEnabled() && snapshot.grants.contains { $0.target == target }
        let authority = granted && signal.hint != .unmanaged ? await dependencies.authority() : .unmanaged
        guard token == revision else { return }
        let desiredMode: KimiDesktopPermissionBridge.Mode? = authority == .automatic ? .auto : authority == .manual ? .manual : nil
        if let override = snapshot.overrides.first(where: { $0.target == target }) {
            if desiredMode == nil || desiredMode == override.heldWhileDesired { outcomes[target] = .externalChange; return }
            try state.clearOverride(target)
        }
        guard authority != .unmanaged || lease != nil else { outcomes[target] = .unmanaged; return }
        let current = try await dependencies.read(target)
        guard token == revision else { return }
        if let old = lease {
            let changed = old.acknowledged ? current != old.intended : current != old.baseline && !old.possibleOwnedModes.contains(current)
            if changed {
                guard try state.removeAfterExternalChange(old, observed: current, holdWhileDesired: desiredMode ?? old.intended) else { throw KimiDesktopLeverState.Failure.staleOperation }
                outcomes[target] = .externalChange; return
            }
        }
        let baseline = lease?.baseline ?? current
        let desired = desiredMode ?? baseline
        if current == desired {
            if let lease {
                if authority == .unmanaged { _ = try state.removeAfterVerifiedRestore(lease) }
                else if current == lease.intended { _ = try state.acknowledge(lease) }
                else { outcomes[target] = .notSynchronized; return }
            }
            outcomes[target] = authority == .unmanaged ? .restored : .unchanged; return
        }
        snapshot = try state.snapshot()
        if authority != .unmanaged {
            guard dependencies.controlEnabled(), snapshot.grants.contains(where: { $0.target == target }),
                  await dependencies.authority() == authority, token == revision else { revision &+= 1; return }
            lease = try state.prepare(target, baseline: baseline, intended: desired)
        }
        guard let operation = lease, token == revision else { return }
        let receipt = try await dependencies.write(operation, current, desired, authority != .unmanaged)
        guard token == revision, receipt.mode == desired else { throw KimiDesktopPermissionBridge.Failure.notApplied }
        if authority == .unmanaged {
            guard try state.removeAfterVerifiedRestore(operation) else { throw KimiDesktopLeverState.Failure.staleOperation }
            outcomes[target] = .restored
        } else {
            guard try state.acknowledge(operation) else { throw KimiDesktopLeverState.Failure.staleOperation }
            let latest = await dependencies.authority()
            let stillGranted = try state.snapshot().grants.contains(where: { $0.target == target })
            if !dependencies.controlEnabled() || !stillGranted || latest != authority {
                revision &+= 1; return
            }
            outcomes[target] = .synchronized
        }
    }
}
