import Foundation

/// Shared by the App and Agent on the main queue. All async work is
/// explicitly on MainActor; IO is injected so the real routing is testable.
public final class WS3PresentationSession {
    private let exchange: @MainActor (Data) async throws -> Data
    private let sendSingleDefault: () -> Bool
    private let onFault: () -> Void
    private let now: () -> TimeInterval
    public var onOverviewChanged: ((WS3TaskOverview) -> Void)?
    private var tasks = WS3TaskRegistry()
    private var generation: UInt64 = 0
    private var connected = false
    private var presentationRevision: UInt64 = 0
    public private(set) var requestedMode: WS3PresentationMode?
    private var activationID: UUID?
    private var activationDeadline: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var flushID: UUID?
    private var dirty = false
    private var expiry: DispatchWorkItem?

    public init(exchange: @escaping @MainActor (Data) async throws -> Data,
         sendSingleDefault: @escaping () -> Bool, onFault: @escaping () -> Void,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.exchange = exchange; self.sendSingleDefault = sendSingleDefault
        self.onFault = onFault; self.now = now
    }

    public var isChangingMode: Bool { activationID != nil }
    public var allowsLegacySingle: Bool { !isChangingMode && requestedMode != .multi }

    public func updateConnection(connected: Bool, generation: UInt64) {
        if self.connected != connected || self.generation != generation {
            clearRuntime()
        }
        self.connected = connected; self.generation = generation
        notifyOverview()
    }

    private func notifyOverview() {
        guard let onOverviewChanged else { return }
        onOverviewChanged(overview())
    }

    public var foregroundContext: WS3ForegroundContext? {
        guard connected, requestedMode == .multi, !isChangingMode else { return nil }
        return .init(generation: generation, presentation: presentationRevision)
    }

    private func clearRuntime() {
        presentationRevision &+= 1
        activationID = nil; activationDeadline?.cancel(); activationDeadline = nil
        flushID = nil; flushTask?.cancel(); flushTask = nil
        expiry?.cancel(); expiry = nil
        requestedMode = nil; dirty = false; tasks.clear()
    }

    public func overview() -> WS3TaskOverview {
        tasks.overview(connected: connected, at: now())
            .reportingPresentation(mode: requestedMode, busy: isChangingMode, generation: connected ? generation : nil,
                revision: requestedMode != nil ? presentationRevision : nil)
    }

    public func observe(_ metadata: WS3TaskMetadata, state: UInt8) {
        guard connected, !isChangingMode else { return }
        if tasks.observe(metadata, state: state, at: now()), requestedMode == .multi {
            requestFlush()
        }
        notifyOverview()
    }

    public func observe(_ event: WS3LiveTaskEvent) {
        guard connected, !isChangingMode else { return }
        if tasks.observe(event, at: now()), requestedMode == .multi { requestFlush() }
        notifyOverview()
    }

    /// Caller supplies an independently verified native foreground source.
    /// It changes presentation priority only, never task freshness or approval.
    public func setForegroundTerminal(_ terminal: WS3TerminalTaskIdentity?) {
        guard connected, !isChangingMode else { return }
        let before = tasks.snapshot(at: now())
        guard tasks.setForegroundTerminal(terminal) else { return }
        notifyOverview()
        if requestedMode == .multi, before != tasks.snapshot(at: now()) { requestFlush() }
    }

    @MainActor
    public func activate(_ target: WS3PresentationMode) async throws -> WS3TaskOverview {
        guard connected else { throw WS3PresentationError.unavailable }
        guard !isChangingMode else { throw WS3PresentationError.busy }
        if requestedMode == target { return overview() } // No clearing on an idempotent repeat.
        let id = UUID(), epoch = generation
        presentationRevision &+= 1
        activationID = id
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.activationID == id, self.generation == epoch else { return }
            self.clearRuntime(); self.connected = false; self.onFault()
        }
        activationDeadline = timeout
        defer {
            timeout.cancel()
            if activationID == id { activationID = nil; activationDeadline = nil }
        }
        do {
            // Finish an already submitted 0x99 before attempting the mode write;
            // its ACK has no request ID and must not be reused by a new sender.
            if let pending = flushTask { await pending.value }
            try check(id: id, epoch: epoch)
            expiry?.cancel(); expiry = nil; dirty = false
            tasks.clear(); requestedMode = nil
            try await ConfirmedWS3Presentation.activate(target, generation: epoch, checkSession: {
                try self.check(id: id, epoch: epoch)
            }, exchange: exchange)
            try check(id: id, epoch: epoch)
            // SINGLE state ACKs can belong to old fire-and-forget hooks, so this
            // default-state write is intentionally not treated as readback.
            if target == .single, !sendSingleDefault() { throw WS3PresentationError.unavailable }
            requestedMode = target
            activationDeadline = nil
            activationID = nil
            notifyOverview()
            return overview()
        } catch {
            if activationID == id, generation == epoch { requestedMode = nil; tasks.clear() }
            throw error
        }
    }

    private func check(id: UUID, epoch: UInt64) throws {
        try Task.checkCancellation()
        guard connected, generation == epoch, activationID == id else { throw WS3PresentationError.connectionChanged }
    }

    private func requestFlush() {
        dirty = true
        guard flushTask == nil, connected, requestedMode == .multi, !isChangingMode else { return }
        let id = UUID(), epoch = generation
        flushID = id
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.flushID == id { self.flushTask = nil; self.flushID = nil } }
            do {
                while self.connected, self.generation == epoch, self.flushID == id,
                      self.requestedMode == .multi, !self.isChangingMode, self.dirty {
                    try await Task.sleep(nanoseconds: 50_000_000) // Coalesce event bursts, not a keepalive.
                    guard self.generation == epoch, self.flushID == id, !self.isChangingMode else { return }
                    self.dirty = false
                    let command = WS3PresentationCommand.multi(self.tasks.snapshot(at: self.now()))
                    self.scheduleExpiry()
                    let reply = try await self.exchange(command.request!)
                    guard self.generation == epoch, self.flushID == id else { return }
                    guard WS3PresentationAcknowledgement.parse(reply, for: command) == .received else {
                        throw WS3PresentationError.rejected
                    }
                }
            } catch {
                guard self.generation == epoch, self.flushID == id else { return }
                self.clearRuntime(); self.connected = false; self.onFault()
            }
        }
    }

    private func scheduleExpiry() {
        expiry?.cancel(); expiry = nil
        guard requestedMode == .multi, let deadline = tasks.nextExpiry else { return }
        let epoch = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == epoch else { return }
            self.expireTasks()
        }
        expiry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, deadline - now()), execute: item)
    }

    /// Production one-shot deadline and isolated clock tests share this path.
    public func expireTasks() {
        guard connected, requestedMode == .multi, !isChangingMode else { return }
        _ = tasks.snapshot(at: now())
        notifyOverview()
        requestFlush()
    }

    public func keyboardWorkModeChanged() {
        presentationRevision &+= 1
        tasks.clear(); expiry?.cancel(); expiry = nil
        notifyOverview()
        if connected, requestedMode == .multi, !isChangingMode { requestFlush() }
    }

    /// launchd stop and GUI handoff may leave the macOS HID link connected.
    /// Clear our proven WS3 runtime before exiting instead of waiting for BLE
    /// physical-disconnect notification or the device's five-minute lease.
    @MainActor
    public func quiesce() async {
        guard connected, let mode = requestedMode, !isChangingMode else {
            let interrupted = isChangingMode
            clearRuntime(); connected = false
            if interrupted { onFault() }
            return
        }
        let id = UUID(), epoch = generation
        activationID = id
        let deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.activationID == id, self.generation == epoch else { return }
            self.clearRuntime(); self.connected = false; self.onFault()
        }
        defer { deadline.cancel() }
        do {
            if let pending = flushTask { await pending.value }
            try check(id: id, epoch: epoch)
            expiry?.cancel(); expiry = nil; tasks.clear(); dirty = false
            // A mode round trip clears SINGLE too. Do not await ambiguous ACKs
            // from legacy fire-and-forget 0x90 hooks during graceful shutdown.
            var commands: [WS3PresentationCommand] = []
            if mode == .single { commands.append(.setMode(.multi)) }
            commands += [.multi(WS3TaskSnapshot(slots: [nil, nil, nil, nil])!), .setMode(.single)]
            for command in commands {
                try check(id: id, epoch: epoch)
                let reply = try await exchange(command.request!)
                try check(id: id, epoch: epoch)
                guard WS3PresentationAcknowledgement.parse(reply, for: command) == .received else {
                    throw WS3PresentationError.rejected
                }
            }
            clearRuntime(); connected = false
            notifyOverview()
        } catch {
            if generation == epoch, activationID == id { clearRuntime(); connected = false; onFault() }
        }
    }
}
