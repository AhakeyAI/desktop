import AppKit
import Combine
import AhaKeyConfigShared

@MainActor
final class StudioResourceInspectorModel: ObservableObject {
    struct Draft {
        let payload: WS3ResourcePayload
        let thumbnail: NSImage?
        let filename: String
        let sourceFrameCount: Int
        let wasResized: Bool
        var adaptationSummary: String? {
            if sourceFrameCount > Int(payload.frameCount) {
                return String(format: NSLocalizedString("已自动抽帧：%d→%d 帧，时长可能缩短", comment: ""), sourceFrameCount, Int(payload.frameCount))
            }
            return wasResized ? NSLocalizedString("已自动适配键盘屏幕", comment: "") : nil
        }
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
    @Published private(set) var defaultDrafts: Set<UInt8> = []
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
    var canWrite: Bool { !isBusy && !isPreparing && (draft != nil || defaultDrafts.contains(entry)) && selected != nil && selected?.writeState != .writing }
    var dirtyEntries: Set<UInt8> {
        Set(drafts.compactMap { id, draft in
            guard let actual = display?.resources.first(where: { $0.id == id }),
                  WS3ResourceMetadataComparison(payload: draft.payload, resource: actual) == .matches,
                  !unconfirmed.contains(id) else { return id }
            return nil
        }).union(defaultDrafts)
    }

    static func pendingEntries(mode: Int, dirty: Set<UInt8>) -> [UInt8] {
        guard (0..<4).contains(mode) else { return [] }
        return dirty.filter { $0 < 16 ? Int($0 / 4) == mode : (16..<19).contains($0) }.sorted()
    }

    func select(mode: AhaKeyModeSlot) {
        selectEntry(UInt8(mode.rawValue * 4))
    }
    func selectEntry(_ target: UInt8) {
        guard !isBusy, !isPreparing, target < 19 else { return }
        entry = target
        message = nil; conflict = nil; confirmsUpload = false; confirmsRestore = false
    }
    func cancel(ble: AhaKeyBLEManager) {
        preparation?.cancel(); operation?.cancel()
        if ble.isConfigurationOperationInProgress { ble.cancelConfigurationOperation() }
    }
    func discardSelection() {
        guard !isBusy, !isPreparing else { return }
        drafts[entry] = nil
        defaultDrafts.remove(entry)
        message = nil; conflict = nil; confirmsUpload = false
    }

    func chooseDefault() {
        guard !isBusy, !isPreparing, let selected, !WS3ResourceRestoreCommand.reportsDefault(selected) else { return }
        drafts[entry] = nil; defaultDrafts.insert(entry); message = nil
    }

    func read(ble: AhaKeyBLEManager, session: StudioInspectorSession, verifying: Bool = false,
              completion: ((Bool) -> Void)? = nil) {
        let target = entry, payload = draft?.payload
        perform(session: session, completion: completion) {
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
        defaultDrafts.remove(target)
        drafts[target] = nil; isPreparing = true; message = nil
        preparation = Task { @MainActor in
            defer { isPreparing = false }
            let worker = Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let prepared = try OLEDFrameEncoder.adaptedFrames(at: url,
                    maximumFrames: Int(WS3ResourceReadback.maximumFrames(target)))
                return (try WS3ResourcePayload(entryID: target, frames: prepared.frames), prepared)
            }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                drafts[target] = Draft(payload: value.0, thumbnail: NSImage(data: value.1.previewPNG),
                    filename: url.lastPathComponent, sourceFrameCount: value.1.sourceFrameCount, wasResized: value.1.wasResized)
            } catch { if !(error is CancellationError) { message = error.localizedDescription } }
        }
    }

    func write(ble: AhaKeyBLEManager, session: StudioInspectorSession, restoring: Bool = false,
               completion: ((Bool) -> Void)? = nil) {
        let target = entry
        guard let baseline = selected, let deviceID, restoring || canWrite else { completion?(false); return }
        let payload = draft?.payload
        guard restoring || payload?.entryID == target else { completion?(false); return }
        confirmsRestore = false; confirmsUpload = false; conflict = nil
        var confirmed = false
        perform(session: session, completion: { completion?($0 && confirmed) }) {
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
            if restoring { self.drafts[target] = nil; self.defaultDrafts.remove(target) }
            confirmed = true
            self.message = NSLocalizedString(restoring ? "此画面已恢复默认，请在键盘上确认效果。" :
                "画面已写入，请在键盘上确认效果。", comment: "")
            self.writeCompleted.send(.init(succeeded: true, message: Self.title(target) + "\n" + (self.message ?? "")))
        }
    }

    func adopt(_ value: Conflict, discardDraft: Bool) {
        guard !isBusy else { return }
        display = value.snapshot
        if discardDraft { drafts[value.entry] = nil; defaultDrafts.remove(value.entry) }
        conflict = nil
    }

    private func perform(session: StudioInspectorSession, completion: ((Bool) -> Void)? = nil,
                         action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !session.isBusy, !isPreparing else { completion?(false); return }
        isBusy = true; message = nil
        operation = Task { @MainActor in
            var succeeded = false
            defer { isBusy = false; operation = nil; completion?(succeeded) }
            do { try await action(); succeeded = true }
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
