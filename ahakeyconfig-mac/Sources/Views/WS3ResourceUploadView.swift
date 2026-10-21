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
    @State private var isChoosing = false
    @State private var isPreparing = false
    @State private var confirmsUpload = false
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
                Text(selected.reportsValidUserResource
                    ? String(format: NSLocalizedString("键盘当前：自定义素材，%d 帧。", comment: ""), Int(selected.frames))
                    : NSLocalizedString("键盘当前没有有效自定义素材，使用固件默认显示。", comment: ""))
                    .font(.caption)
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
                .buttonStyle(.borderedProminent).disabled(!ready || payload?.entryID != entry)
            Text(NSLocalizedString("只上传所选位置，不修改其他设置。预览为首帧；上传后仍需在键盘确认实际显示。中断不代表恢复原素材。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let progress = bleManager.oledUploadProgress, bleManager.isUploadingOLED {
                ProgressView(value: Double(progress.completedChunks), total: Double(max(1, progress.totalChunks)))
                Text(String(format: NSLocalizedString("已确认 %d / %d 个分块；完成后还会核对元数据。", comment: ""), progress.completedChunks, progress.totalChunks)).font(.caption)
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
        .onChange(of: entry) { _ in payload = nil; thumbnail = nil; filename = ""; message = nil }
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

    private func upload() {
        guard ready, let payload, payload.entryID == entry, let snapshot else { return }
        message = nil
        operation = Task { @MainActor in
            do {
                _ = try await bleManager.uploadWS3Resource(payload, baseline: snapshot)
                message = NSLocalizedString("素材上传完成，帧数、长度和 CRC 元数据已核对一致；请在键盘确认画面并验证重启保持。", comment: "")
            } catch {
                message = NSLocalizedString("素材上传未确认完成。已写入内容可能生效，请重新连接并读取；如仍不可读，请正常重启键盘。原素材不保证恢复。", comment: "") + "\n" + error.localizedDescription
            }
        }
    }
}
