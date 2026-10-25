import Combine
import Foundation
import AhaKeyConfigShared

@MainActor
final class StudioRestoreInspectorModel: ObservableObject {
    enum Failure: Error, LocalizedError {
        case voiceActive
        var errorDescription: String? {
            NSLocalizedString("请先停止录音或松开语音键，再恢复键盘设置。本次尚未执行。", comment: "")
        }
    }
    struct Fact {
        let deviceID: String
        let value: RestoreInitializationTransaction.Snapshot
    }
    struct Output {
        let result: RestoreInitializationTransaction.Result
        let readback: RestoreInitializationReadback?
    }
    struct Access {
        let read: () async throws -> Fact
        let start: (Fact, Bool, Bool) async throws -> Output
        let verify: (Fact) async throws -> Output
    }
    static let pendingKey = "ahakey.studio.restore.pending-devices.v1"
    private let defaults: UserDefaults
    private var pending: Set<String>
    @Published private(set) var fact: Fact?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published var intendsRestore = false
    @Published var usbPowerConfirmed = false
    let writeCompleted = PassthroughSubject<KeyboardWriteOutcome, Never>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pending = Set((defaults.stringArray(forKey: Self.pendingKey) ?? [])
            .filter { !$0.isEmpty && $0.utf8.count <= 128 }.prefix(32))
        if !pending.isEmpty { message = NSLocalizedString("上次恢复结果尚未核对，请先读取恢复状态。", comment: "") }
    }
    var canSubmit: Bool {
        guard let fact else { return false }
        return !isBusy && intendsRestore && usbPowerConfirmed && fact.value.canStart &&
            !pending.contains(fact.deviceID) && pending.count < 32
    }
    var canVerify: Bool { !isBusy && fact?.value.handled == true && fact?.value.state == .complete }
    func clearIntent() { intendsRestore = false; usbPowerConfirmed = false }

    func read(using access: Access) async {
        guard !isBusy else { return }
        isBusy = true; clearIntent()
        defer { isBusy = false }
        do {
            let actual = try await access.read()
            guard !actual.deviceID.isEmpty else { throw StudioInspectorSession.Failure.deviceChanged }
            fact = actual
            if actual.value.handled && [.never, .incomplete].contains(actual.value.state) {
                markPending(actual.deviceID, value: false)
            }
            message = pending.count >= 32
                ? NSLocalizedString("还有其他键盘的恢复结果待核对，请先完成核对。", comment: "") : nil
        } catch { fact = nil; message = error.localizedDescription }
    }
    func start(using access: Access, userConfirmed: Bool) async {
        guard userConfirmed, canSubmit, let baseline = fact else { return }
        isBusy = true
        let power = usbPowerConfirmed
        clearIntent()
        // Persist intent before calling the transport. Restart recovery is always read-only.
        markPending(baseline.deviceID, value: true)
        message = NSLocalizedString("正在恢复并核对设置，请保持 USB 供电。", comment: "")
        defer { isBusy = false }
        do { accept(try await access.start(baseline, userConfirmed, power), deviceID: baseline.deviceID, wrote: true) }
        catch Failure.voiceActive {
            markPending(baseline.deviceID, value: false)
            message = Failure.voiceActive.localizedDescription
            writeCompleted.send(.init(succeeded: false, message: message ?? "", wrote: false))
        }
        catch {
            fact = nil
            message = error.localizedDescription + "\n" + NSLocalizedString("请重新读取恢复状态，不要直接重复恢复。", comment: "")
            writeCompleted.send(.init(succeeded: false, message: message ?? "", wrote: true))
        }
    }
    func verify(using access: Access) async {
        guard canVerify, let baseline = fact else { return }
        isBusy = true; clearIntent()
        message = NSLocalizedString("正在核对恢复后的设置，本次不执行恢复。", comment: "")
        defer { isBusy = false }
        do { accept(try await access.verify(baseline), deviceID: baseline.deviceID, wrote: false) }
        catch {
            message = error.localizedDescription
            writeCompleted.send(.init(succeeded: false, message: message ?? "", wrote: false))
        }
    }
    private func accept(_ output: Output, deviceID: String, wrote: Bool) {
        let snapshot: RestoreInitializationTransaction.Snapshot
        var succeeded = false
        switch output.result {
        case .verified(let value):
            snapshot = value
            succeeded = output.readback?.matchesX1RefactorDefaults == true
            message = succeeded
                ? NSLocalizedString("恢复后的键位、语音路由、待机、拨杆和显示灯光已核对一致；断电保持仍待验证。本地草稿保留。", comment: "")
                : NSLocalizedString("键盘报告已恢复，但默认设置尚未完整核对。", comment: "")
        case .needsReadback(let value):
            snapshot = value
            message = NSLocalizedString("键盘报告已恢复，但部分设置与预期默认值不同，请重新核对。", comment: "")
        case .unfinished(let value):
            snapshot = value
            message = NSLocalizedString("恢复尚未完成，请先读取状态，再明确选择是否重试。", comment: "")
        case .refused(let value):
            snapshot = value
            message = NSLocalizedString("键盘未接受本次恢复，请检查 USB 供电并重新读取状态。", comment: "")
        }
        fact = .init(deviceID: deviceID, value: snapshot)
        if succeeded { markPending(deviceID, value: false) }
        writeCompleted.send(.init(succeeded: succeeded, message: message ?? "", wrote: wrote))
    }
    private func markPending(_ deviceID: String, value: Bool) {
        let previous = pending
        if value { pending.insert(deviceID) } else { pending.remove(deviceID) }
        guard pending != previous else { return }
        defaults.set(Array(pending.sorted().prefix(32)), forKey: Self.pendingKey)
    }
}
