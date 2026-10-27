import Foundation
import AhaKeyConfigShared

/// Main-queue lifecycle adapter. Session HTTP never blocks Hook replies or BLE.
final class KimiDesktopLeverAgent: @unchecked Sendable {
    private let worker: KimiDesktopLeverCoordinator
    private var hint = KimiDesktopLeverCoordinator.Authority.unmanaged
    private var epoch: UInt64 = 0
    private var timer: DispatchSourceTimer?
    private var stopping = false
    private var publication: UInt64 = 0
    private var report: [String: Any] = ["phase": "noSessions", "authorizedSessions": 0, "managedSessions": 0, "pendingRecovery": 0]
    init(authority: @escaping @Sendable () async -> KimiDesktopLeverCoordinator.Authority) {
        worker = .init(dependencies: .desktop(authority: authority))
    }
    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.report["phase"] as? String == "notSynchronized" || (self.report["pendingRecovery"] as? Int ?? 0) > 0 {
                self.tick(retry: true)
            }
        }
        self.timer = timer; timer.resume(); tick(retry: true)
    }
    deinit { timer?.cancel() }
    func status(physical: Int?, generation: UInt64) {
        guard !stopping else { return }
        let next: KimiDesktopLeverCoordinator.Authority = physical == 0 ? .automatic : physical == 1 ? .manual : .unmanaged
        guard next != hint || epoch != generation else { return }
        hint = next; epoch = generation; tick()
    }
    func controlChanged() { tick(retry: true) }
    func snapshot() -> [String: Any] { report }
    private func tick(retry: Bool = false) {
        guard !stopping, timer != nil else { return }
        publication &+= 1
        let publication = publication, hint = hint, epoch = epoch
        Task {
            let outcomes = await worker.reconcile(hint: hint, epoch: epoch, retry: retry)
            let busy = await worker.isRunning
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopping, self.publication == publication else { return }
                guard let state = try? KimiDesktopLeverState().snapshot() else {
                    self.report = ["phase": "notSynchronized", "storageError": true]; return
                }
                let granted = Set(state.grants.map(\.target))
                let recovering = state.leases.filter { !granted.contains($0.target) || !ApprovalAutomationControl.isEnabled(.kimi) || hint == .unmanaged }
                let phase: String
                if outcomes.values.contains(.notSynchronized) { phase = "notSynchronized" }
                else if busy || !recovering.isEmpty { phase = "recovering" }
                else if outcomes.values.contains(.externalChange) { phase = "externalChange" }
                else if state.grants.isEmpty { phase = "noSessions" }
                else if outcomes.isEmpty { phase = "waiting" }
                else { phase = "synchronized" }
                self.report = ["phase": phase, "authorizedSessions": state.grants.count,
                    "managedSessions": state.leases.filter(\.acknowledged).count,
                    "pendingRecovery": recovering.count + state.leases.filter { !$0.acknowledged && !recovering.contains($0) }.count]
            }
        }
    }
    func shutdown() async {
        let epoch = await MainActor.run { self.stopping = true; self.timer?.cancel(); self.timer = nil; return self.epoch }
        _ = await worker.reconcile(hint: .unmanaged, epoch: epoch &+ 1, retry: true)
        await worker.waitUntilIdle()
    }
}
