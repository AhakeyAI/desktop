import Foundation
import Combine
import AhaKeyConfigShared

/// One screen-edit submission: artwork first, then an explicit runtime choice.
/// Refresh never applies a mode, and completed artwork is not rolled back when
/// a later stage fails. Unsubmitted choices remain drafts.
@MainActor
final class StudioLCDInspectorModel: ObservableObject {
    struct Access {
        var revision: () -> UInt64
        var available: () -> Bool
        var read: () async -> WS3TaskOverview?
        var apply: (WS3PresentationMode, String, UInt64) async throws -> WS3TaskOverview
        var followEnabled: () -> Bool
        var setFollow: (Bool) -> Void
        var pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }
    }
    struct ArtworkAction {
        let title: String
        let run: @MainActor () async throws -> Void
    }
    enum Failure: Error, LocalizedError {
        case unavailable, changed, artworkNeedsAttention, oldBackend
        var errorDescription: String? {
            switch self {
            case .unavailable: return NSLocalizedString("未能读取当前连接，请刷新后重试。", comment: "")
            case .changed: return NSLocalizedString("键盘连接已改变，请重新读取后写入。", comment: "")
            case .artworkNeedsAttention: return NSLocalizedString("画面尚未确认，请处理素材区的提示后重试。", comment: "")
            case .oldBackend: return NSLocalizedString("请更新并重启后台后重试。", comment: "")
            }
        }
    }

    @Published private(set) var overview: WS3TaskOverview?
    @Published private(set) var modeDraft: WS3PresentationMode?
    @Published private(set) var followDraft: Bool?
    @Published private(set) var actualFollow = false
    @Published private(set) var isReading = false
    @Published private(set) var isWriting = false
    @Published private(set) var message: String?
    let writeCompleted = PassthroughSubject<KeyboardWriteOutcome, Never>()
    private var readTask: Task<Void, Never>?
    private var readID: UUID?
    private var readRevision: UInt64?
    private var writeTask: Task<Void, Never>?

    var selectedMode: WS3PresentationMode? { modeDraft ?? overview?.requestedMode }
    var followsTerminal: Bool { followDraft ?? actualFollow }
    var hasSettingsDraft: Bool { modeDraft != nil || followDraft != nil }

    func chooseMode(_ value: WS3PresentationMode) {
        guard !isWriting else { return }
        modeDraft = value == overview?.requestedMode ? nil : value; message = nil
    }
    func chooseFollow(_ value: Bool) {
        guard !isWriting else { return }
        followDraft = value == actualFollow ? nil : value; message = nil
    }

    func invalidateFacts(ownershipRevision: UInt64? = nil) {
        overview = nil
        // SwiftUI can deliver an earlier owner-change notification after a new
        // read has already started on that owner. Do not cancel the new read.
        if ownershipRevision != readRevision || ownershipRevision == nil { cancelRead() }
    }
    func invalidateConnectionFacts() {
        overview = nil
        // Revoke the read token as well: an old socket reply must not resurrect
        // facts after the heartbeat has already reported a lost connection.
        cancelRead()
    }
    func cancelRead() {
        readID = nil; readRevision = nil; readTask?.cancel(); readTask = nil; isReading = false
    }

    func read(using access: Access) {
        guard !isWriting else { return }
        cancelRead()
        actualFollow = access.followEnabled()
        let id = UUID(); readID = id; readRevision = access.revision(); isReading = true; message = nil
        readTask = Task { @MainActor in
            defer { if self.readID == id { self.isReading = false; self.readTask = nil; self.readID = nil; self.readRevision = nil } }
            do {
                let value = try await self.freshOverview(using: access)
                guard self.readID == id else { return }
                self.overview = value; self.actualFollow = access.followEnabled()
            } catch {
                if self.readID == id, !(error is CancellationError) {
                    self.overview = nil; self.message = error.localizedDescription
                }
            }
        }
    }

    /// Bounded reconnect wait for an explicit read/write, never a background poll.
    private func freshOverview(using access: Access) async throws -> WS3TaskOverview {
        let revision = access.revision()
        for _ in 0..<20 {
            try Task.checkCancellation()
            guard access.revision() == revision else { throw Failure.changed }
            if access.available(), let value = await access.read() {
                guard access.revision() == revision else { throw Failure.changed }
                if value.connected, value.presentationBusy == false, value.connectionGeneration != nil { return value }
            }
            try await access.pause()
        }
        throw Failure.unavailable
    }

    func write(artwork: [ArtworkAction], deviceID: String?, using access: Access) {
        guard !isWriting, !isReading, !artwork.isEmpty || hasSettingsDraft else { return }
        let mode = modeDraft, follow = followDraft
        guard mode == nil || deviceID?.isEmpty == false else { message = Failure.unavailable.localizedDescription; return }
        isWriting = true; message = nil
        writeTask = Task { @MainActor in
            var completed: [String] = []
            defer { self.isWriting = false; self.writeTask = nil }
            do {
                for item in artwork {
                    try Task.checkCancellation()
                    try await item.run()
                    completed.append(item.title)
                }
                if let mode, let deviceID {
                    let fresh = try await self.freshOverview(using: access)
                    guard fresh.targetedModeWrites == true else { throw Failure.oldBackend }
                    guard let generation = fresh.connectionGeneration else { throw Failure.unavailable }
                    let revision = access.revision()
                    let result = try await access.apply(mode, deviceID, generation)
                    try Task.checkCancellation()
                    guard access.revision() == revision, result.connected, result.requestedMode == mode,
                          result.connectionGeneration == generation else { throw Failure.changed }
                    self.overview = result
                    if self.modeDraft == mode { self.modeDraft = nil }
                    completed.append(NSLocalizedString("展示方式", comment: ""))
                }
                try Task.checkCancellation()
                if let follow {
                    access.setFollow(follow); self.actualFollow = follow
                    if self.followDraft == follow { self.followDraft = nil }
                    completed.append(NSLocalizedString("跟随当前终端", comment: ""))
                }
                self.message = NSLocalizedString("屏幕设置已更新，请在键盘上确认效果。", comment: "")
                self.writeCompleted.send(.init(succeeded: true,
                    message: completed.joined(separator: "、") + "\n" + (self.message ?? ""),
                    wrote: !artwork.isEmpty || mode != nil))
            } catch {
                let prefix = completed.isEmpty ? "" : String(format:
                    NSLocalizedString("已完成：%@。其余改动仍保留，请核对后重试。", comment: ""), completed.joined(separator: "、")) + "\n"
                self.message = prefix + (error is CancellationError
                    ? NSLocalizedString("操作已停止，已发出的改动可能生效，请刷新核对。", comment: "") : error.localizedDescription)
                // The artwork view owns its conflict dialog and uncertain-upload
                // notice. Do not put a second alert over either of them.
                if case Failure.artworkNeedsAttention = error { return }
                self.writeCompleted.send(.init(succeeded: false, message: self.message ?? ""))
            }
        }
    }
    func cancelWrite() { writeTask?.cancel() }
}
