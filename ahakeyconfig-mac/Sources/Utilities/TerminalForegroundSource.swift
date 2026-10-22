import AppKit
import Combine
import ApplicationServices
import AhaKeyConfigShared

/// One event-driven native observation. Disabled by default. Only an explicit
/// permission action can ask for access; restored preferences do not prompt.
@MainActor
final class TerminalForegroundSource: ObservableObject {
    struct Target: Equatable, Sendable {
        let provider: TerminalSelectionQuery.Provider
        let instance: WS3ProcessInstance
    }
    struct Access {
        let frontmost: () -> Target?
        let accessibilityTrusted: () -> Bool
        let observe: (Target, @escaping () -> Void) -> Bool
        let stopObserving: () -> Void
        let read: (Target) async throws -> String
        let identify: (String) -> WS3TerminalTaskIdentity?
        let authorize: (Target?) async -> Bool
    }
    enum Status: Equatable { case disabled, waiting, accessibility, automation, unavailable, following }
    @Published private(set) var status: Status = .disabled
    private(set) var enabled = false
    private(set) var focus: WS3ForegroundUpdate.Focus?
    var onChange: ((WS3ForegroundUpdate.Focus?, UInt64) -> Void)?
    private let access: Access
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastTarget: Target?
    private var requestEpoch: UInt64 = 0
    private var sequence: UInt64 = 0
    private var pending = false
    private var forced = false
    private var suspended = false
    private var query: Task<Void, Never>?
    private var queryID: UUID?

    init(access: Access, observeWorkspace: Bool = false) {
        self.access = access
        if observeWorkspace {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                })
            }
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = false; self?.refresh(force: true) }
            })
        }
    }
    static let shared: TerminalForegroundSource = {
        let native = TerminalFocusAccess.shared
        return .init(access: Access(frontmost: { native.frontmost() }, accessibilityTrusted: { AXIsProcessTrusted() },
            observe: { native.start($0, changed: $1) }, stopObserving: { native.stop() },
            read: { try await TerminalSelectionQuery.readTTY(processID: $0.instance.pid, provider: $0.provider) },
            identify: { WS3TerminalTaskIdentity.captureTTY($0) }, authorize: { await native.authorize($0) }), observeWorkspace: true)
    }()
    deinit { query?.cancel(); workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value { refresh(force: true) } else { stop(status: .disabled) }
    }
    func suspend() { suspended = true; stop(status: enabled ? .waiting : .disabled) }
    func authorize() async {
        guard enabled else { return }
        stop(status: .waiting)
        _ = await access.authorize(lastTarget)
        if enabled { refresh(force: true) }
    }
    func refresh(force: Bool = false) {
        guard enabled, !suspended else { return }
        guard let target = access.frontmost() else { stop(status: .waiting); return }
        lastTarget = target
        guard access.accessibilityTrusted() else { stop(status: .accessibility); return }
        // A notification invalidates the selected-tab proof even when the app
        // and old TTY remain alive. Revoke before the asynchronous re-query.
        if focus != nil { publish(nil, status: .waiting, force: false) }
        requestEpoch &+= 1; pending = true; forced = forced || force
        guard query == nil else { return }
        let id = UUID(); queryID = id
        query = Task { @MainActor [weak self] in
            defer { if self?.queryID == id { self?.query = nil; self?.queryID = nil } }
            while let self, self.pending, self.enabled, !self.suspended, !Task.isCancelled {
                self.pending = false
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self.enabled, !self.suspended else { return }
                self.pending = false
                let epoch = self.requestEpoch, force = self.forced
                self.forced = false
                guard let target = self.access.frontmost() else { self.stop(status: .waiting); return }
                self.lastTarget = target
                guard self.access.observe(target, { [weak self] in self?.refresh() }) else { self.stop(status: .unavailable); return }
                do {
                    let path = try await self.access.read(target)
                    guard !Task.isCancelled, self.enabled, !self.suspended else { return }
                    guard epoch == self.requestEpoch, self.access.frontmost() == target else { self.pending = true; continue }
                    let focus = self.access.identify(path).map { WS3ForegroundUpdate.Focus(application: target.instance, terminal: $0) }
                    self.publish(focus, status: focus == nil ? .unavailable : .following, force: force)
                } catch {
                    guard !Task.isCancelled, epoch == self.requestEpoch, self.enabled else { continue }
                    self.publish(nil, status: error as? TerminalSelectionQuery.Failure == .authorizationRequired ? .automation : .unavailable, force: force)
                }
            }
        }
    }
    private func stop(status: Status) {
        requestEpoch &+= 1; pending = false; forced = false
        query?.cancel(); query = nil; queryID = nil
        access.stopObserving()
        publish(nil, status: status, force: true)
    }
    private func publish(_ value: WS3ForegroundUpdate.Focus?, status: Status, force: Bool) {
        if self.status != status { self.status = status }
        guard focus != value || force else { return }
        focus = value; sequence &+= 1
        onChange?(value, sequence)
    }
}
