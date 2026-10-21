import SwiftUI
import UniformTypeIdentifiers
import AhaKeyConfigShared

struct WS3ResourceUploadView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var entry: UInt8
    @State private var payload: WS3ResourcePayload?
    @State private var thumbnail: NSImage?
    @State private var filename = ""
    @State private var message: String?
    @State private var uploadFeedback = WS3UploadFeedback()
    @State private var isChoosing = false
    @State private var isPreparing = false
    @State private var confirmsUpload = false
    @State private var confirmsRestore = false
    @State private var restoreBaseline: WS3DisplaySnapshot?
    @State private var preparation: Task<Void, Never>?
    @State private var operation: Task<Void, Never>?

    init(bleManager: AhaKeyBLEManager, initialEntry: UInt8 = 0) {
        self.bleManager = bleManager
        _entry = State(initialValue: initialEntry < 19 ? initialEntry : 0)
    }
    private var snapshot: WS3DisplaySnapshot? {
        guard let value = bleManager.ws3DisplaySnapshot,
              value.generation == bleManager.configurationSnapshot.generation else { return nil }
        return value
    }
    private var ready: Bool { bleManager.canEditWS3Display && !bleManager.isConfigurationOperationInProgress && !isPreparing }
    private var uploadInProgress: Bool { snapshot?.resources.contains { $0.writeState == .writing } == true }
    private var selected: WS3ResourceReadback? { snapshot?.resources.first { $0.id == entry } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("显示素材上传", comment: "")).font(.headline)
            Picker(NSLocalizedString("素材位置", comment: ""), selection: $entry) {
                ForEach(0..<19) { id in Text(title(UInt8(id))).tag(UInt8(id)) }
            }.disabled(!ready)
            Text(String(format: NSLocalizedString("此位置最多 %d 帧；播放速度由当前固件固定为 10 帧/秒。", comment: ""), Int(WS3ResourceReadback.maximumFrames(entry))))
                .font(.caption).foregroundStyle(.secondary)
            if let selected {
                Text(resourceStatus(selected)).font(.caption)
            }
            HStack(alignment: .top) {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 160, height: 80)
                        .background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button(isPreparing ? NSLocalizedString("正在准备素材…", comment: "") : NSLocalizedString("选择图片或 GIF…", comment: "")) { isChoosing = true }.disabled(!ready)
                    if let payload { Text("\(filename) · \(payload.frameCount) \(NSLocalizedString("帧", comment: ""))").font(.caption).lineLimit(2) }
                }
            }
            Button(NSLocalizedString("上传并核对素材", comment: "")) { confirmsUpload = true }
                .buttonStyle(.borderedProminent).disabled(!ready || payload?.entryID != entry || uploadInProgress)
            if uploadInProgress {
                Text(WS3ResourceUploadError.uploadInProgress.localizedDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(NSLocalizedString("重新核对所选素材（只读）", comment: "")) { verify() }
                    .disabled(!ready || payload?.entryID != entry)
                Button(NSLocalizedString("恢复此位置的默认显示…", comment: "")) {
                    restoreBaseline = snapshot
                    confirmsRestore = true
                }.disabled(!ready || selected.map { WS3ResourceRestoreCommand.reportsDefault($0) || $0.writeState == .writing } != false)
            }
            if let payload, let selected, payload.entryID == entry {
                Text(comparisonMessage(WS3ResourceMetadataComparison(payload: payload, resource: selected)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("核对只比较键盘最近读回的元数据，不会上传。恢复仅停用此处自定义素材，不能找回以前的图片或恢复其他设置。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            Text(NSLocalizedString("只上传所选位置，不修改其他设置。预览为首帧；上传后仍需在键盘确认实际显示。中断不代表恢复原素材。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let progress = bleManager.oledUploadProgress, bleManager.isUploadingOLED {
                ProgressView(value: Double(progress.completedChunks), total: Double(max(1, progress.totalChunks)))
                Text(String(format: NSLocalizedString("已确认 %d / %d 个分块；完成后还会核对元数据。", comment: ""), progress.completedChunks, progress.totalChunks)).font(.caption)
            }
            ForEach(uploadFeedback.unconfirmedEntries.sorted(), id: \.self) { affected in
                Text(title(affected) + " · " + NSLocalizedString("上次素材上传未确认完成。请重新连接并读取；若读取被拒绝，请正常重启键盘。原素材不保证恢复。", comment: ""))
                    .font(.caption).textSelection(.enabled)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.gif, .png, .jpeg, .bmp, .tiff], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { prepare(url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .confirmationDialog(NSLocalizedString("上传到这个素材位置？", comment: ""), isPresented: $confirmsUpload, titleVisibility: .visible) {
            Button(NSLocalizedString("上传并覆盖此位置", comment: ""), role: .destructive) { upload() }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text("\(title(entry)) · \(filename)\n" + NSLocalizedString("开始上传后可能覆盖原素材；失败或取消不保证回滚。其他素材和键位不变。", comment: ""))
        }
        .confirmationDialog(NSLocalizedString("恢复这个位置的默认显示？", comment: ""), isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button(NSLocalizedString("确认恢复此位置", comment: ""), role: .destructive) { restore() }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { restoreBaseline = nil }
        } message: {
            Text(title(entry) + "\n" + NSLocalizedString("此位置的自定义图片将不再使用；失败不保证回滚。其他素材、按键和语音不变。", comment: ""))
        }
        .onChange(of: entry) { _ in
            payload = nil; thumbnail = nil; filename = ""; message = nil
            confirmsRestore = false; restoreBaseline = nil
        }
        .onChange(of: bleManager.configurationSnapshot.generation) { _ in
            uploadFeedback.connectionChanged(to: bleManager.configurationSnapshot.generation)
            message = nil; confirmsRestore = false; restoreBaseline = nil
        }
        .onDisappear { preparation?.cancel(); operation?.cancel() }
    }

    private func title(_ id: UInt8) -> String {
        let states = [NSLocalizedString("默认画面", comment: ""), NSLocalizedString("进行中", comment: ""), NSLocalizedString("等待处理", comment: ""), NSLocalizedString("已完成", comment: "")]
        if id >= 16 { return NSLocalizedString("多任务", comment: "") + " · " + states[Int(id - 15)] }
        return (AhaKeyModeSlot(rawValue: Int(id / 4))?.name ?? "") + " · " + states[Int(id % 4)]
    }

    private func prepare(_ url: URL) {
        preparation?.cancel(); payload = nil; thumbnail = nil; message = nil; isPreparing = true
        let target = entry
        preparation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let frames = try OLEDFrameEncoder.frames(fromGIFAt: url, maximumFrames: Int(WS3ResourceReadback.maximumFrames(target)))
                let encoded = try WS3ResourcePayload(entryID: target, frames: frames)
                return (encoded, NSImage(contentsOf: url))
            }
            defer { isPreparing = false }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard entry == target else { return }
                payload = result.0; thumbnail = result.1; filename = url.lastPathComponent
            } catch { if !(error is CancellationError) { message = error.localizedDescription } }
        }
    }

    private func resourceStatus(_ resource: WS3ResourceReadback) -> String {
        if resource.reportsValidUserResource {
            return String(format: NSLocalizedString("键盘当前：自定义素材，%d 帧。", comment: ""), Int(resource.frames))
        }
        if WS3ResourceRestoreCommand.reportsDefault(resource) {
            return NSLocalizedString("键盘当前：默认显示（无自定义素材）。", comment: "")
        }
        if resource.writeState == .writing {
            return NSLocalizedString("键盘当前：素材上传中，暂不能恢复默认。", comment: "")
        }
        return NSLocalizedString("键盘当前：自定义素材不可用，按固件规则回退显示。", comment: "")
    }

    private func comparisonMessage(_ comparison: WS3ResourceMetadataComparison) -> String {
        switch comparison {
        case .matches: return NSLocalizedString("所选文件与最近读回的素材元数据一致；实际画面仍需在键盘确认。", comment: "")
        case .different: return NSLocalizedString("所选文件与最近读回的素材元数据不同；本次核对未更改键盘。", comment: "")
        case .noValidCustomResource: return NSLocalizedString("此位置未读到有效自定义素材；选择文件不会自动上传。", comment: "")
        }
    }

    private func verify() {
        guard ready, let payload, payload.entryID == entry else { return }
        message = nil
        let generation = bleManager.configurationSnapshot.generation
        operation = Task { @MainActor in
            do {
                _ = try await bleManager.verifyWS3Resource(payload)
                guard generation == bleManager.configurationSnapshot.generation else { return }
                message = NSLocalizedString("已重新读取此位置并核对元数据，未写入键盘。", comment: "")
            } catch {
                guard generation == bleManager.configurationSnapshot.generation else { return }
                message = error.localizedDescription
            }
        }
    }

    private func restore() {
        guard ready, let baseline = restoreBaseline,
              baseline.generation == bleManager.configurationSnapshot.generation else { return }
        restoreBaseline = nil; message = nil
        let target = entry
        operation = Task { @MainActor in
            do {
                _ = try await bleManager.restoreWS3ResourceDefault(entry: target, baseline: baseline)
                guard baseline.generation == bleManager.configurationSnapshot.generation else { return }
                uploadFeedback.restoredDefault(entry: target)
                message = NSLocalizedString("此位置已恢复默认显示，空素材标记读回一致；请在键盘确认实际显示。", comment: "")
            } catch {
                guard baseline.generation == bleManager.configurationSnapshot.generation else { return }
                message = NSLocalizedString("恢复未确认完成。已发出的更改可能生效，请重新读取；原自定义素材不保证恢复。", comment: "") + "\n" + error.localizedDescription
            }
        }
    }

    private func upload() {
        guard ready, !uploadInProgress, let payload, payload.entryID == entry, let snapshot else { return }
        message = nil
        let attempt = uploadFeedback.begin(entry: entry, generation: snapshot.generation)
        operation = Task { @MainActor in
            do {
                _ = try await bleManager.uploadWS3Resource(payload, baseline: snapshot)
                guard uploadFeedback.confirm(attempt, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
                message = NSLocalizedString("素材上传完成，帧数、长度和 CRC 元数据已核对一致；请在键盘确认画面并验证重启保持。", comment: "")
            } catch {
                guard uploadFeedback.fail(attempt, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
                message = error.localizedDescription
            }
        }
    }
}
