import SwiftUI
import UniformTypeIdentifiers
import AhaKeyConfigShared

struct StudioResourceInspectorView: View {
    @ObservedObject var model: StudioResourceInspectorModel
    @ObservedObject var ble: AhaKeyBLEManager
    @ObservedObject var session: StudioInspectorSession
    let mode: AhaKeyModeSlot
    @State private var choosingFile = false
    @State private var showsAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("屏幕素材", comment: "")).font(.headline)
                Spacer()
                Button { model.read(ble: ble, session: session) } label: { Image(systemName: "arrow.clockwise") }
                    .help(NSLocalizedString("读取显示信息（只读）", comment: ""))
                    .disabled(model.isBusy || session.isBusy)
            }
            Picker(NSLocalizedString("画面状态", comment: ""), selection: $model.entry) {
                ForEach(mode.rawValue * 4..<(mode.rawValue * 4 + 4), id: \.self) { id in
                    Text(StudioResourceInspectorModel.title(UInt8(id))).tag(UInt8(id))
                }
                if model.entry >= 16 {
                    Text(StudioResourceInspectorModel.title(model.entry)).tag(model.entry)
                }
            }.disabled(model.isBusy || model.isPreparing)
            DisclosureGroup(NSLocalizedString("多任务画面", comment: ""), isExpanded: $showsAdvanced) {
                ForEach(16..<19, id: \.self) { id in
                    Button(StudioResourceInspectorModel.title(UInt8(id))) { model.entry = UInt8(id) }
                        .disabled(model.isBusy || model.isPreparing)
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("最多 %d 帧 · 10 FPS", comment: ""),
                Int(WS3ResourceReadback.maximumFrames(model.entry))))
                .font(.caption).foregroundStyle(.secondary)
            if let draft = model.draft {
                if let image = draft.thumbnail {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 120)
                        .background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("\(draft.filename) · \(draft.payload.frameCount) \(NSLocalizedString("帧", comment: ""))")
                    .font(.caption).lineLimit(2)
            }
            Button(model.isPreparing ? NSLocalizedString("正在准备素材…", comment: "") : NSLocalizedString("选择图片或 GIF…", comment: "")) {
                choosingFile = true
            }.disabled(model.isBusy || model.isPreparing || model.selected == nil)
            Button(NSLocalizedString("重新核对所选素材（只读）", comment: "")) {
                model.read(ble: ble, session: session, verifying: true)
            }.disabled(model.isBusy || model.isPreparing || model.draft == nil)
            Button(NSLocalizedString("恢复此位置的默认显示…", comment: "")) { model.confirmsRestore = true }
                .disabled(model.isBusy || model.selected.map { WS3ResourceRestoreCommand.reportsDefault($0) || $0.writeState == .writing } != false)
            if let progress = ble.oledUploadProgress, model.isBusy {
                ProgressView(value: Double(progress.completedChunks), total: Double(max(1, progress.totalChunks)))
                Text(String(format: NSLocalizedString("已确认 %d / %d 个分块；完成后还会核对元数据。", comment: ""),
                    progress.completedChunks, progress.totalChunks)).font(.caption)
            }
            if model.unconfirmed.contains(model.entry) {
                Text(NSLocalizedString("此位置上次写入未确认，请重新读取后核对。", comment: "")).font(.caption).foregroundStyle(.orange)
            }
            if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("只写入所选画面。开始上传后可能覆盖原素材；取消不保证恢复。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.gif, .png, .jpeg, .bmp, .tiff]) { result in
            switch result {
            case .success(let url): model.prepare(url)
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .confirmationDialog(NSLocalizedString("上传到这个素材位置？", comment: ""), isPresented: $model.confirmsUpload, titleVisibility: .visible) {
            Button(NSLocalizedString("写入键盘", comment: ""), role: .destructive) { model.write(ble: ble, session: session) }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(uploadConfirmationText)
        }
        .confirmationDialog(NSLocalizedString("恢复这个位置的默认显示？", comment: ""), isPresented: $model.confirmsRestore, titleVisibility: .visible) {
            Button(NSLocalizedString("确认恢复此位置", comment: ""), role: .destructive) { model.write(ble: ble, session: session, restoring: true) }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: { Text(StudioResourceInspectorModel.title(model.entry)) }
        .alert(NSLocalizedString("键盘当前素材已变化", comment: ""), isPresented: Binding(get: { model.conflict != nil }, set: { if !$0 { model.conflict = nil } }), presenting: model.conflict) { conflict in
            Button(NSLocalizedString("采用键盘当前值", comment: ""), role: .cancel) { model.adopt(conflict, discardDraft: true) }
            Button(NSLocalizedString("确认修改", comment: "")) {
                model.adopt(conflict, discardDraft: false)
                model.write(ble: ble, session: session, restoring: conflict.restoring)
            }
        } message: { conflict in
            Text(StudioResourceInspectorModel.title(conflict.entry) + "\n" +
                NSLocalizedString("键盘内容与开始编辑时不同，草稿已保留。确认后仍会重新核对。", comment: ""))
        }
    }

    private var status: String {
        if model.unconfirmed.contains(model.entry) { return NSLocalizedString("此位置上次写入未确认，请重新读取后核对。", comment: "") }
        guard let selected = model.selected else { return NSLocalizedString("请先读取当前素材位置。", comment: "") }
        if selected.reportsValidUserResource {
            return String(format: NSLocalizedString("键盘当前：自定义素材，%d 帧。", comment: ""), Int(selected.frames))
        }
        return NSLocalizedString(WS3ResourceRestoreCommand.reportsDefault(selected)
            ? "键盘当前：默认显示（无自定义素材）。" : "键盘当前：自定义素材不可用，按固件规则回退显示。", comment: "")
    }
    private var uploadConfirmationText: String {
        [StudioResourceInspectorModel.title(model.entry), model.draft?.filename ?? "",
         NSLocalizedString("开始上传后可能覆盖原素材；失败或取消不保证回滚。其他素材和键位不变。", comment: "")].joined(separator: "\n")
    }
}
