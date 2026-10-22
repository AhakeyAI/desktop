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
    @Published var standbyDraft: UInt16?
    @Published private(set) var standbyFact: StudioConfirmedEdit.Fact<UInt16>?
    @Published var leverDraft: SideSwitchBindingDraft?
    @Published private(set) var leverFact: StudioConfirmedEdit.Fact<[SideSwitchReadback.Position]>?
    @Published var conflict: Conflict?
    @Published var message: String?
    @Published private(set) var isBusy = false
    @Published private(set) var unconfirmed: Set<Setting> = []
    let writeCompleted = PassthroughSubject<KeyboardWriteOutcome, Never>()
    private var operation: Task<Void, Never>?
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
                self.leverFact = fact
                if self.leverDraft == nil { self.leverDraft = .init(readback: .init(physicalState: 0, positions: fact.value)) }
            } else {
                let fact = try await session.withConnection { context in
                    StudioConfirmedEdit.Fact(deviceID: context.deviceID, value: try await ble.readStandbyForEditing())
                }
                self.standbyFact = fact
                if self.standbyDraft == nil { self.standbyDraft = fact.value }
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
                case .unconfirmed(let actual): self.leverFact = actual; self.persistenceUnconfirmed()
                case .saved(let actual, let wrote):
                    self.leverFact = actual
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
                case .unconfirmed(let actual): self.standbyFact = actual; self.persistenceUnconfirmed()
                case .saved(let actual, let wrote):
                    self.standbyFact = actual; self.standbyDraft = actual.value
                    self.succeeded(setting: .standby, scope: NSLocalizedString("待机时间", comment: ""), wrote: wrote)
                }
            }
        }
    }
    func adopt(_ conflict: Conflict, keepDraft: Bool) {
        switch conflict.value {
        case .standby(let fact, let desired): standbyFact = fact; standbyDraft = keepDraft ? desired : fact.value
        case .lever(let fact, let desired):
            leverFact = fact
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
