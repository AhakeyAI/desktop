import AppKit
import Combine
import AhaKeyConfigShared

@MainActor
final class StudioResourceInspectorModel: ObservableObject {
    struct Draft {
        let payload: WS3ResourcePayload
        let thumbnail: NSImage?
        let filename: String
    }
    struct Conflict: Identifiable {
        let id = UUID()
        let entry: UInt8
        let snapshot: WS3DisplaySnapshot
        let restoring: Bool
    }
    enum Failure: Error, LocalizedError {
        case missingReadback
        var errorDescription: String? { NSLocalizedString("请先读取当前素材位置。", comment: "") }
    }
    @Published var entry: UInt8 = 0
    @Published private(set) var drafts: [UInt8: Draft] = [:]
    @Published private(set) var display: WS3DisplaySnapshot?
    @Published private(set) var deviceID: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isPreparing = false
    @Published private(set) var unconfirmed: Set<UInt8> = []
    @Published var message: String?
    @Published var confirmsUpload = false
    @Published var confirmsRestore = false
    @Published var conflict: Conflict?
    let writeCompleted = PassthroughSubject<KeyboardWriteOutcome, Never>()
    private var operation: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    var draft: Draft? { drafts[entry] }
    var selected: WS3ResourceReadback? { display?.resources.first { $0.id == entry } }
    var canWrite: Bool { !isBusy && !isPreparing && draft != nil && selected != nil && selected?.writeState != .writing }
    var dirtyEntries: Set<UInt8> {
        Set(drafts.compactMap { id, draft in
            guard let actual = display?.resources.first(where: { $0.id == id }),
                  WS3ResourceMetadataComparison(payload: draft.payload, resource: actual) == .matches,
                  !unconfirmed.contains(id) else { return id }
            return nil
        })
    }

    func select(mode: AhaKeyModeSlot) {
        guard !isBusy else { return }
        entry = UInt8(mode.rawValue * 4)
        message = nil; conflict = nil; confirmsUpload = false; confirmsRestore = false
    }
    func cancel(ble: AhaKeyBLEManager) {
        preparation?.cancel(); operation?.cancel()
        if ble.isConfigurationOperationInProgress { ble.cancelConfigurationOperation() }
    }

    func read(ble: AhaKeyBLEManager, session: StudioInspectorSession, verifying: Bool = false) {
        let target = entry, payload = draft?.payload
        perform(session: session) {
            let result = try await session.withConnection { context in
                (context.deviceID, try await ble.readWS3DisplayForEditing())
            }
            self.deviceID = result.0; self.display = result.1
            self.message = NSLocalizedString("已读取键盘素材信息。", comment: "")
            if verifying, let payload, let actual = result.1.resources.first(where: { $0.id == target }) {
                switch WS3ResourceMetadataComparison(payload: payload, resource: actual) {
                case .matches: self.message = NSLocalizedString("所选文件与最近读回的素材元数据一致；实际画面仍需在键盘确认。", comment: "")
                case .different: self.message = NSLocalizedString("所选文件与最近读回的素材元数据不同；本次核对未更改键盘。", comment: "")
                case .noValidCustomResource: self.message = NSLocalizedString("此位置未读到有效自定义素材；选择文件不会自动上传。", comment: "")
                }
            }
        }
    }

    func prepare(_ url: URL) {
        guard !isBusy else { return }
        preparation?.cancel()
        let target = entry
        drafts[target] = nil; isPreparing = true; message = nil
        preparation = Task { @MainActor in
            defer { isPreparing = false }
            let worker = Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let frames = try OLEDFrameEncoder.frames(fromGIFAt: url,
                    maximumFrames: Int(WS3ResourceReadback.maximumFrames(target)))
                return Draft(payload: try .init(entryID: target, frames: frames),
                    thumbnail: NSImage(contentsOf: url), filename: url.lastPathComponent)
            }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                drafts[target] = value
            } catch { if !(error is CancellationError) { message = error.localizedDescription } }
        }
    }

    func write(ble: AhaKeyBLEManager, session: StudioInspectorSession, restoring: Bool = false) {
        let target = entry
        guard let baseline = selected, let deviceID, restoring || canWrite else { return }
        let payload = draft?.payload
        guard restoring || payload?.entryID == target else { return }
        confirmsRestore = false; confirmsUpload = false; conflict = nil
        perform(session: session) {
            let result: (snapshot: WS3DisplaySnapshot, changed: Bool) = try await session.withConnection(expectedDeviceID: deviceID) { _ in
                // Every lease obtains the complete CP2 proof; cached facts never authorize a write.
                let fresh = try await ble.readWS3DisplayForEditing()
                guard let actual = fresh.resources.first(where: { $0.id == target }) else { throw Failure.missingReadback }
                guard actual == baseline else {
                    return (fresh, true)
                }
                try Task.checkCancellation()
                self.unconfirmed.insert(target)
                let confirmed: WS3ResourceReadback
                if restoring {
                    confirmed = try await ble.restoreWS3ResourceDefault(entry: target, baseline: fresh)
                } else {
                    guard let payload else { throw Failure.missingReadback }
                    confirmed = try await ble.uploadWS3Resource(payload, baseline: fresh)
                }
                return (WS3DisplaySnapshot(generation: fresh.generation, brightness: fresh.brightness,
                    resources: fresh.resources.map { $0.id == target ? confirmed : $0 }), false)
            }
            if result.changed {
                self.conflict = .init(entry: target, snapshot: result.snapshot, restoring: restoring)
                return
            }
            self.display = result.snapshot; self.unconfirmed.remove(target)
            if restoring { self.drafts[target] = nil }
            self.message = NSLocalizedString(restoring ? "此位置已恢复默认显示，空素材标记读回一致；请在键盘确认实际显示。" :
                "素材上传完成，帧数、长度和 CRC 元数据已核对一致；请在键盘确认画面并验证重启保持。", comment: "")
            self.writeCompleted.send(.init(succeeded: true, message: Self.title(target) + "\n" + (self.message ?? "")))
        }
    }

    func adopt(_ value: Conflict, discardDraft: Bool) {
        guard !isBusy else { return }
        display = value.snapshot
        if discardDraft { drafts[value.entry] = nil }
        conflict = nil
    }

    private func perform(session: StudioInspectorSession, action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !session.isBusy, !isPreparing else { return }
        isBusy = true; message = nil
        operation = Task { @MainActor in
            defer { isBusy = false; operation = nil }
            do { try await action() }
            catch {
                message = KeyboardSettingsFeedback.message(for: error)
                if !unconfirmed.isEmpty {
                    message = (message ?? "") + "\n" + NSLocalizedString("上次素材上传未确认完成。请重新连接并读取；若读取被拒绝，请正常重启键盘。原素材不保证恢复。", comment: "")
                }
            }
        }
    }

    static func title(_ id: UInt8) -> String {
        let states = ["默认画面", "进行中", "等待处理", "已完成"].map { NSLocalizedString($0, comment: "") }
        if id >= 16 { return NSLocalizedString("多任务", comment: "") + " · " + states[Int(id - 15)] }
        return (AhaKeyModeSlot(rawValue: Int(id / 4))?.name ?? "") + " · " + states[Int(id % 4)]
    }
}
