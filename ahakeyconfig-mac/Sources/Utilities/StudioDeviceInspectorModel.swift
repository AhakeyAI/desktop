import Foundation
import Combine
import AhaKeyConfigShared

@MainActor
final class StudioDeviceInspectorModel: ObservableObject {
    enum Setting: Hashable { case standby, lever }
    struct Conflict: Identifiable {
        enum Value {
            case standby(StudioConfirmedEdit.Fact<UInt16>, UInt16)
            case lever(StudioConfirmedEdit.Fact<[SideSwitchReadback.Position]>, [SideSwitchReadback.Position])
        }
        let id = UUID()
        let value: Value
    }
    @Published var standbyDraft: UInt16? { didSet { persistDrafts() } }
    @Published private(set) var standbyFact: StudioConfirmedEdit.Fact<UInt16>?
    @Published var leverDraft: SideSwitchBindingDraft? { didSet { persistDrafts() } }
    @Published private(set) var leverFact: StudioConfirmedEdit.Fact<[SideSwitchReadback.Position]>?
    @Published var conflict: Conflict?
    @Published var message: String?
    @Published private(set) var isBusy = false
    @Published private(set) var unconfirmed: Set<Setting> = [] { didSet { persistDrafts() } }
    let writeCompleted = PassthroughSubject<KeyboardWriteOutcome, Never>()
    private var operation: Task<Void, Never>?
    private let defaults: UserDefaults
    private var history: StudioDeviceDraftHistory
    private var activeDeviceID: String?
    private var isRestoringHistory = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let history = StudioDeviceDraftHistory.load(from: defaults)
        self.history = history
        activeDeviceID = history.lastDeviceID
        let record = history[activeDeviceID]
        standbyDraft = record?.standby
        leverDraft = record?.lever
        if record?.unconfirmedStandby == true { unconfirmed.insert(.standby) }
        if record?.unconfirmedLever == true { unconfirmed.insert(.lever) }
        // Historical baselines intentionally do not populate standbyFact/leverFact.
    }
    private func persistDrafts() {
        guard !isRestoringHistory, let deviceID = activeDeviceID else { return }
        var record = history[deviceID] ?? .init()
        record.standby = standbyDraft; record.lever = leverDraft
        record.unconfirmedStandby = unconfirmed.contains(.standby)
        record.unconfirmedLever = unconfirmed.contains(.lever)
        history.save(record, deviceID: deviceID); history.persist(to: defaults)
    }
    private func activateDevice(_ deviceID: String) {
        guard activeDeviceID != deviceID else { return }
        persistDrafts()
        isRestoringHistory = true
        activeDeviceID = deviceID
        let record = history[deviceID]
        standbyDraft = record?.standby; leverDraft = record?.lever
        standbyFact = nil; leverFact = nil; unconfirmed = []
        if record?.unconfirmedStandby == true { unconfirmed.insert(.standby) }
        if record?.unconfirmedLever == true { unconfirmed.insert(.lever) }
        isRestoringHistory = false
    }
    func observeStandby(_ fact: StudioConfirmedEdit.Fact<UInt16>) {
        activateDevice(fact.deviceID)
        let previous = history[fact.deviceID]?.standbyBaseline
        let clean = standbyDraft == nil || (previous != nil && standbyDraft == previous)
        standbyFact = fact
        if clean { standbyDraft = fact.value }
        var record = history[fact.deviceID] ?? .init()
        record.standbyBaseline = fact.value
        history.save(record, deviceID: fact.deviceID); persistDrafts()
    }
    func observeLever(_ fact: StudioConfirmedEdit.Fact<[SideSwitchReadback.Position]>) {
        activateDevice(fact.deviceID)
        let previous = history[fact.deviceID]?.leverBaseline
        let clean = leverDraft == nil || (previous != nil && leverDraft?.positions == previous)
        leverFact = fact
        if clean && leverDraft?.positions != fact.value {
            leverDraft = .init(readback: .init(physicalState: 0, positions: fact.value))
        }
        var record = history[fact.deviceID] ?? .init()
        record.leverBaseline = fact.value
        history.save(record, deviceID: fact.deviceID); persistDrafts()
    }
    var standbyDirty: Bool { standbyDraft != nil && standbyDraft != standbyFact?.value }
    var leverDirty: Bool { leverDraft != nil && leverDraft?.positions != leverFact?.value }
    var canWriteLever: Bool {
        guard let draft = leverDraft, leverFact != nil else { return false }
        return SideSwitchBindingConfiguration.request(positions: draft.positions) != nil
    }
    func switchMode(_ target: UInt8, ble: AhaKeyBLEManager, session: StudioInspectorSession) {
        perform(session: session) {
            let actual = try await session.withConnection { _ in try await ble.switchWorkModeConfirmed(target) }
            self.message = String(format: NSLocalizedString("键盘已确认切换到 Mode %d。", comment: ""), Int(actual + 1))
        }
    }
    func cancel(ble: AhaKeyBLEManager) {
        operation?.cancel()
        if ble.isConfigurationOperationInProgress { ble.cancelConfigurationOperation() }
    }
    func read(lever: Bool, ble: AhaKeyBLEManager, session: StudioInspectorSession) {
        perform(session: session) {
            if lever {
                let fact = try await session.withConnection { context in
                    StudioConfirmedEdit.Fact(deviceID: context.deviceID, value: try await ble.readSideSwitchForEditing().positions)
                }
                self.observeLever(fact)
            } else {
                let fact = try await session.withConnection { context in
                    StudioConfirmedEdit.Fact(deviceID: context.deviceID, value: try await ble.readStandbyForEditing())
                }
                self.observeStandby(fact)
            }
            self.message = NSLocalizedString("已读取。", comment: "")
        }
    }
    func write(lever: Bool, ble: AhaKeyBLEManager, session: StudioInspectorSession) {
        if lever {
            guard let baseline = leverFact, let desired = leverDraft?.positions, canWriteLever else { return }
            perform(session: session) {
                let result = try await StudioConfirmedEdit.run(baseline: baseline, desired: desired,
                    requiresPersistence: self.unconfirmed.contains(.lever), session: session,
                    read: { _ in try await ble.readSideSwitchForEditing().positions }, write: { actual, context in
                        self.unconfirmed.insert(.lever)
                        return try await ble.setSideSwitchConfirmed(baseline: actual, target: desired, expectedGeneration: context.generation).positions
                    })
                switch result {
                case .conflict(let actual): self.conflict = .init(value: .lever(actual, desired))
                case .unconfirmed(let actual): self.observeLever(actual); self.persistenceUnconfirmed()
                case .saved(let actual, let wrote):
                    self.observeLever(actual)
                    self.leverDraft = .init(readback: .init(physicalState: 0, positions: actual.value))
                    self.succeeded(setting: .lever, scope: NSLocalizedString("实体拨杆绑定", comment: ""), wrote: wrote)
                }
            }
        } else {
            guard let baseline = standbyFact, let desired = standbyDraft else { return }
            perform(session: session) {
                let result = try await StudioConfirmedEdit.run(baseline: baseline, desired: desired,
                    requiresPersistence: self.unconfirmed.contains(.standby), session: session,
                    read: { _ in try await ble.readStandbyForEditing() }, write: { _, _ in
                        self.unconfirmed.insert(.standby)
                        return try await ble.setStandbyConfirmed(desired)
                    })
                switch result {
                case .conflict(let actual): self.conflict = .init(value: .standby(actual, desired))
                case .unconfirmed(let actual): self.observeStandby(actual); self.persistenceUnconfirmed()
                case .saved(let actual, let wrote):
                    self.observeStandby(actual); self.standbyDraft = actual.value
                    self.succeeded(setting: .standby, scope: NSLocalizedString("待机时间", comment: ""), wrote: wrote)
                }
            }
        }
    }
    func adopt(_ conflict: Conflict, keepDraft: Bool) {
        switch conflict.value {
        case .standby(let fact, let desired): observeStandby(fact); standbyDraft = keepDraft ? desired : fact.value
        case .lever(let fact, let desired):
            observeLever(fact)
            leverDraft = .init(readback: .init(physicalState: 0, positions: keepDraft ? desired : fact.value))
        }
        self.conflict = nil
    }
    private func succeeded(setting: Setting, scope: String, wrote: Bool) {
        unconfirmed.remove(setting)
        message = NSLocalizedString(wrote ? "已保存并读回一致；断电保持性尚未验证。" : "当前配置已核对一致，无需写入。", comment: "")
        writeCompleted.send(.init(succeeded: true, message: scope + "\n" + (message ?? ""), wrote: wrote))
    }
    private func persistenceUnconfirmed() {
        message = NSLocalizedString("当前读值一致，但上次保存未确认；请重启键盘后再核对，未清除待确认标记。", comment: "")
    }
    private func perform(session: StudioInspectorSession, action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !session.isBusy else { return }
        isBusy = true; message = nil; conflict = nil
        operation = Task { @MainActor in
            defer { isBusy = false; operation = nil }
            do { try await action() }
            catch {
                message = KeyboardSettingsFeedback.message(for: error)
                if !unconfirmed.isEmpty { message = (message ?? "") + "\n" + NSLocalizedString("已发出的修改可能生效，请重新读取后核对。", comment: "") }
            }
        }
    }
}
