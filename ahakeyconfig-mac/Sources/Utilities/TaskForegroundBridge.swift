import AppKit
import Combine
import AhaKeyConfigShared

/// Host preference only. It never activates a display mode, opens a BLE lease,
/// or changes persistent keyboard settings.
@MainActor
final class TaskForegroundBridge: ObservableObject {
    static let shared = TaskForegroundBridge()
    private static let preferenceKey = "lab.jawa.ahakeyconfig.followTerminalForeground"
    @Published var enabled = UserDefaults.standard.bool(forKey: preferenceKey) {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
            if ble != nil { source.setEnabled(enabled) }
        }
    }
    @Published private(set) var deliveryMessage: String?
    let source = TerminalForegroundSource.shared
    private weak var ble: AhaKeyBLEManager?
    private let origin = WS3ProcessInstance.capture(getpid())
    private var pending: (WS3ForegroundUpdate.Focus?, UInt64)?
    private var latestSequence: UInt64 = 0
    private var sending: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var refreshObserver: NSObjectProtocol?

    func attach(_ ble: AhaKeyBLEManager) {
        guard self.ble !== ble else { return }
        self.ble = ble
        subscriptions.removeAll()
        source.onChange = { [weak self] focus, sequence in self?.enqueue(focus, sequence: sequence) }
        source.setEnabled(enabled)
        AgentManager.shared.$bluetoothConnectionOwner.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        AgentManager.shared.$isAgentBLEConnected.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        ble.$coreSnapshot.map(\.isConnected).removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        if refreshObserver == nil {
            refreshObserver = DistributedNotificationCenter.default().addObserver(forName: WS3ForegroundReceiver.refreshNotification,
                object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        }
    }
    deinit {
        sending?.cancel()
        if let refreshObserver { DistributedNotificationCenter.default().removeObserver(refreshObserver) }
    }
    func refresh() { if enabled { source.refresh(force: true) } }
    private func enqueue(_ focus: WS3ForegroundUpdate.Focus?, sequence: UInt64) {
        latestSequence = sequence; pending = (focus, sequence)
        guard sending == nil else { return }
        sending = Task { @MainActor [weak self] in
            defer { self?.sending = nil }
            while let self, let item = self.pending, let origin = self.origin, !Task.isCancelled {
                self.pending = nil
                let manager = AgentManager.shared, ownership = manager.bluetoothOwnershipRevision
                let accepted: Bool
                if manager.bluetoothConnectionOwner == .ahaKeyStudio {
                    guard let ble = self.ble, ble.presentationRuntimeActive,
                          let context = ble.studioPresentation.foregroundContext else { continue }
                    accepted = ble.studioPresentation.receiveForeground(.init(origin: origin, sequence: item.1, context: context, focus: item.0))
                } else {
                    guard let report = await manager.readTaskOverview(), report.connected, report.requestedMode == .multi,
                          report.presentationBusy == false, let generation = report.connectionGeneration, let revision = report.presentationRevision,
                          self.latestSequence == item.1, manager.bluetoothOwnershipRevision == ownership else { continue }
                    accepted = await manager.updatePresentationForeground(.init(origin: origin, sequence: item.1,
                        context: .init(generation: generation, presentation: revision), focus: item.0))
                }
                guard self.latestSequence == item.1, manager.bluetoothOwnershipRevision == ownership else { continue }
                let message = !accepted && item.0 != nil ? NSLocalizedString("当前连接暂不能跟随前台任务。", comment: "") : nil
                if self.deliveryMessage != message { self.deliveryMessage = message }
            }
        }
    }
}
