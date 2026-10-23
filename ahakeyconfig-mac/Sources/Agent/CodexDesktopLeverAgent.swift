import AhaKeyConfigShared
import Foundation

/// Main-queue adapter. Native IO stays off the BLE and Hook reply paths.
// All mutable state is main-queue confined; async work captures only values and
// the immutable coordinator actor. Shutdown explicitly hops back before edits.
final class CodexDesktopLeverAgent: @unchecked Sendable {
    private let worker: CodexDesktopLeverCoordinator
    private var threads: [String: TimeInterval] = [:]
    private var capacityLimited = false
    private var hint = CodexDesktopLeverCoordinator.Authority.unmanaged
    private var epoch: UInt64 = 0
    private var timer: DispatchSourceTimer?
    private var stopping = false
    private var publication: UInt64 = 0
    private var lastRetry = ProcessInfo.processInfo.systemUptime
    private var report: [String: Any] = ["phase": "waiting", "pendingRecovery": 0, "managedSessions": 0, "appliesTo": "nextTurn"]

    init(authority: @escaping @Sendable () async -> CodexDesktopLeverCoordinator.Authority) {
        worker = .init(dependencies: .init(authority: authority))
    }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    deinit { timer?.cancel() }
    func observe(_ request: [String: Any]) {
        guard !stopping, ["state", "state_with_reset", "permission"].contains(request["cmd"] as? String ?? ""),
              let task = request["task"] as? [String: String], task["client"] == "codex",
              let id = task["session"], UUID(uuidString: id) != nil else { return }
        let isNew = threads[id] == nil
        if isNew, threads.count >= 32 {
            let owned = Set((try? CodexDesktopLeverState().snapshot().leases.map { $0.owner.threadID }) ?? Array(threads.keys))
            guard let oldest = threads.filter({ !owned.contains($0.key) }).min(by: { $0.value < $1.value })?.key else {
                capacityLimited = true; return
            }
            threads.removeValue(forKey: oldest)
        }
        threads[id] = ProcessInfo.processInfo.systemUptime
        if isNew { capacityLimited = false; tick() }
    }
    func status(physical: Int?, generation: UInt64) {
        guard !stopping else { return }
        // Hint only: injected proof checks fresh factory bindings before grants.
        let next: CodexDesktopLeverCoordinator.Authority = physical == 0 ? .verifiedAutomatic : physical == 1 ? .manual : .unmanaged
        guard next != hint || generation != epoch else { return }
        hint = next; epoch = generation; tick()
    }
    func snapshot() -> [String: Any] { report }

    private func tick() {
        guard !stopping, timer != nil else { return }
        publication &+= 1
        let publication = publication, ids = Array(threads.keys), hint = hint, epoch = epoch
        let now = ProcessInfo.processInfo.systemUptime
        let retry = now - lastRetry >= 30 && (report["phase"] as? String == "notSynchronized" || (report["pendingRecovery"] as? Int ?? 0) > 0)
        if retry { lastRetry = now }
        Task {
            let outcomes = await worker.reconcile(threadIDs: ids, hint: hint, epoch: epoch, retry: retry)
            let busy = await worker.isRunning
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopping, self.publication == publication else { return }
                let state = try? CodexDesktopLeverState().snapshot()
                let phase: String
                if self.capacityLimited { phase = "notSynchronized" }
                else if busy { phase = "working" }
                else if outcomes.values.contains(.notSynchronized) { phase = "notSynchronized" }
                else if state?.managementEnabled != true || hint == .unmanaged { phase = "notManaged" }
                else if outcomes.values.contains(.unmanaged) || outcomes.values.contains(.restored) { phase = "notSynchronized" }
                else if outcomes.isEmpty { phase = "waiting" }
                else if outcomes.values.contains(.externalChange) { phase = "externalChange" }
                else { phase = "synchronized" }
                self.report = ["phase": phase, "pendingRecovery": state?.leases.filter { !$0.acknowledged }.count ?? 0,
                    "managedSessions": state?.leases.count ?? 0, "appliesTo": "nextTurn"]
            }
        }
    }
    func shutdown() async {
        let (ids, epoch) = await MainActor.run {
            self.stopping = true; self.timer?.cancel(); self.timer = nil
            return (Array(self.threads.keys), self.epoch)
        }
        _ = await worker.reconcile(threadIDs: ids, hint: .unmanaged, epoch: epoch &+ 1, retry: true)
        await worker.waitUntilIdle()
    }
}
