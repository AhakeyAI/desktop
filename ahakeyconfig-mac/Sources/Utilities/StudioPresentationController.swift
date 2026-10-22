import Foundation
import Combine
import AppKit
import AhaKeyConfigShared

/// App-owned runtime only. Configuration uses a short lease and quiesces this
/// coordinator first; it does not silently resume a previous presentation mode.
@MainActor
final class StudioPresentationController: ObservableObject {
    @Published private(set) var overview = WS3TaskOverview(connected: false, tasks: [], unrepresentedEvents: 0)
    @Published private(set) var isBusy = false
    @Published private(set) var eventsMayBeIncomplete = false
    private weak var ble: AhaKeyBLEManager?
    private let source = StudioLiveTaskSource()
    private var generation: UInt64 = 0
    private var isQuiescing = false
    private var workMode: Int?
    private var singleReset: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var sleepObserver: NSObjectProtocol?
    private lazy var runtime: WS3PresentationSession = {
        let session = WS3PresentationSession(exchange: { [weak self] request in
        guard let self, let ble = self.ble else { throw WS3PresentationError.unavailable }
        return try await ble.exchangePresentation(request, generation: self.generation)
    }, sendSingleDefault: { [weak self] in
        guard let self, let ble = self.ble else { return false }
        return ble.sendPresentationDefault(generation: self.generation)
    }, onFault: { [weak self] in self?.fault() })
        session.onOverviewChanged = { [weak self] value in
            if self?.overview != value { self?.overview = value }
        }
        return session
    }()

    private var foregroundReceiver: WS3ForegroundReceiver?
    var foregroundContext: WS3ForegroundContext? { runtime.foregroundContext }
    func receiveForeground(_ update: WS3ForegroundUpdate) -> Bool {
        guard let ble, ble.isConnected, ble.configurationSnapshot.generation == generation,
              AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio else { return false }
        if foregroundReceiver == nil {
            foregroundReceiver = WS3ForegroundReceiver(context: { [weak self] in self?.runtime.foregroundContext },
                apply: { [weak self] in self?.runtime.setForegroundTerminal($0) })
        }
        return foregroundReceiver?.receive(update) ?? false
    }

    init(ble: AhaKeyBLEManager) {
        self.ble = ble
        ble.$coreSnapshot.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateConnection() }.store(in: &subscriptions)
        ble.$configurationSnapshot.map(\.generation).removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateConnection() }.store(in: &subscriptions)
        AgentManager.shared.$bluetoothConnectionOwner.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateConnection() }.store(in: &subscriptions)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.fault() } }
    }
    deinit { if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) } }

    func readOverview() -> WS3TaskOverview { updateConnection(); overview = runtime.overview(); return overview }
    func activate(_ mode: WS3PresentationMode) async throws -> WS3TaskOverview {
        guard !isBusy, let ble, AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio,
              ble.isConnected else { throw WS3PresentationError.unavailable }
        updateConnection()
        if runtime.requestedMode == mode { return try await runtime.activate(mode) }
        isBusy = true
        defer { isBusy = false }
        source.stop(); singleReset?.cancel()
        let initialEpoch = ble.configurationSnapshot.generation
        do {
            if runtime.requestedMode != nil { await quiesce() }
            _ = try await ble.readWS3DisplayForEditing()
            guard ble.configurationSnapshot.generation == initialEpoch else { throw WS3PresentationError.connectionChanged }
            let epoch = try ble.beginPresentationOperation()
            generation = epoch
            defer { ble.finishPresentationOperation(generation: epoch) }
            runtime.updateConnection(connected: true, generation: epoch)
            overview = try await runtime.activate(mode)
            ble.blockLegacySinglePresentation(mode == .multi)
            ble.setPresentationRuntimeActive(true)
            eventsMayBeIncomplete = false
            try startSource()
            DistributedNotificationCenter.default().postNotificationName( WS3ForegroundReceiver.refreshNotification, object: nil,
                userInfo: nil, deliverImmediately: true)
            return overview
        } catch {
            fault(expectedGeneration: initialEpoch)
            throw error
        }
    }
    func quiesce() async {
        guard !isQuiescing else { return }
        isQuiescing = true
        defer { isQuiescing = false }
        let initialEpoch = generation
        foregroundReceiver?.reset()
        source.stop(); singleReset?.cancel(); singleReset = nil
        guard let ble else { return }
        if runtime.requestedMode != nil {
            do {
                let epoch = try ble.beginPresentationOperation()
                defer { ble.finishPresentationOperation(generation: epoch) }
                await runtime.quiesce()
            } catch { fault(expectedGeneration: initialEpoch) }
        }
        ble.setPresentationRuntimeActive(false)
        ble.blockLegacySinglePresentation(false)
        overview = runtime.overview()
    }
    private func updateConnection() {
        guard let ble else { return }
        let connected = ble.isConnected && AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio
        let epoch = ble.configurationSnapshot.generation
        if !connected || epoch != generation {
            source.stop(); singleReset?.cancel(); singleReset = nil; ble.blockLegacySinglePresentation(false)
            ble.setPresentationRuntimeActive(false)
        } else if !isBusy, !isQuiescing, workMode != nil, workMode != ble.workMode, runtime.requestedMode != nil {
            source.stop(); singleReset?.cancel(); singleReset = nil
            runtime.keyboardWorkModeChanged()
            foregroundReceiver?.revalidate()
            DistributedNotificationCenter.default().postNotificationName(WS3ForegroundReceiver.refreshNotification,
                object: nil, userInfo: nil, deliverImmediately: true)
            do { try startSource() } catch { fault(); return }
        }
        workMode = ble.workMode
        generation = epoch
        runtime.updateConnection(connected: connected, generation: epoch)
        overview = runtime.overview()
        foregroundReceiver?.revalidate()
    }
    private func startSource() throws {
        try source.start(consume: { [weak self] events, gap in
            guard let self, let ble = self.ble, ble.isConnected,
                  ble.configurationSnapshot.generation == self.generation,
                  AgentManager.shared.bluetoothConnectionOwner == .ahaKeyStudio else { return }
            if gap {
                self.eventsMayBeIncomplete = true; self.runtime.keyboardWorkModeChanged()
                self.foregroundReceiver?.revalidate()
                DistributedNotificationCenter.default().postNotificationName(WS3ForegroundReceiver.refreshNotification,
                    object: nil, userInfo: nil, deliverImmediately: true)
            }
            for event in events {
                self.runtime.observe(event)
                if self.runtime.requestedMode == .single { self.sendSingle(event) }
            }
            self.overview = self.runtime.overview()
        }, fault: { [weak self] in self?.fault() })
    }
    private func sendSingle(_ event: WS3LiveTaskEvent) {
        guard let display = event.singleDisplay(at: ProcessInfo.processInfo.systemUptime), let ble else { return }
        singleReset?.cancel()
        guard ble.sendPresentationState(display.state, generation: generation) else { fault(); return }
        guard display.remaining > 0 else { return }
        let epoch = generation
        singleReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(display.remaining))
            guard !Task.isCancelled, let self, self.generation == epoch, self.runtime.requestedMode == .single else { return }
            _ = self.ble?.sendPresentationState(display.reset, generation: epoch)
        }
    }
    private func fault(expectedGeneration: UInt64? = nil) {
        if let expectedGeneration, expectedGeneration != generation || ble?.configurationSnapshot.generation != expectedGeneration { return }
        foregroundReceiver?.reset()
        source.stop(); singleReset?.cancel(); singleReset = nil
        runtime.updateConnection(connected: false, generation: generation)
        overview = runtime.overview()
        ble?.blockLegacySinglePresentation(false)
        ble?.setPresentationRuntimeActive(false)
        ble?.poisonPresentationConnection(generation: generation)
    }
}
