import SwiftUI
import UniformTypeIdentifiers
import AhaKeyConfigShared

struct StudioResourceInspectorView: View {
    @ObservedObject var model: StudioResourceInspectorModel
    @ObservedObject var ble: AhaKeyBLEManager
    @ObservedObject var session: StudioInspectorSession
    @ObservedObject var presentation: StudioLCDInspectorModel
    let mode: AhaKeyModeSlot
    var onWrite: (() -> Void)? = nil
    @State private var choosingFile = false
    @Environment(\.isEnabled) private var editorEnabled

    private var busy: Bool { model.isBusy || model.isPreparing || session.isBusy }
    private var multitask: Bool { model.entry >= 16 }
    private var entries: [UInt8] {
        StudioScreenArtworkPlan.entries(mode: mode.rawValue, presentation: multitask ? .multi : .single)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(NSLocalizedString("展示模式", comment: ""), selection: Binding(get: { multitask }, set: { value in
                presentation.chooseMode(value ? .multi : .single)
                model.selectPresentation(value ? .multi : .single, mode: mode)
            })) {
                Text(NSLocalizedString("单任务", comment: "")).tag(false)
                Text(NSLocalizedString("多任务", comment: "")).tag(true)
            }
            .pickerStyle(.segmented).disabled(busy)

            Text(NSLocalizedString("写入所选模式的图片并启用该模式，灯条与 LCD 联动。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)

            if multitask {
                Text(NSLocalizedString("多任务画面为所有模式共用", comment: "")).font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(entries, id: \.self) { resourceCard($0) }
            }

            HStack {
                Text(currentStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.read(ble: ble, session: session) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(NSLocalizedString("读取显示信息（只读）", comment: ""))
                    .disabled(busy)
                Button { model.chooseDefault() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(NSLocalizedString("使用默认素材", comment: ""))
                    .help(NSLocalizedString("选择默认素材，写入后生效。", comment: ""))
                    .disabled(busy || model.selected.map { WS3ResourceRestoreCommand.reportsDefault($0) || $0.writeState == .writing } != false)
            }

            artworkPicker

            if !multitask {
                Text(NSLocalizedString("已完成画面也用于键盘默认画面。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if multitask { StudioLCDForegroundOption(model: presentation) }


            if let draft = model.draft {
                HStack(spacing: 8) {
                    Text(draft.filename).lineLimit(1).truncationMode(.middle).help(draft.filename)
                    Spacer(minLength: 0)
                    Button { model.read(ble: ble, session: session, verifying: true) } label: { Image(systemName: "checkmark.seal") }
                        .buttonStyle(.borderless).disabled(busy)
                        .accessibilityLabel(NSLocalizedString("核对素材", comment: ""))
                        .help(NSLocalizedString("只读核对所选文件，不会上传。", comment: ""))
                    Button { model.discardSelection() } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).disabled(busy)
                        .accessibilityLabel(NSLocalizedString("取消素材选择", comment: ""))
                        .help(NSLocalizedString("仅清除本地选择，不改变键盘。", comment: ""))
                    Button(NSLocalizedString("更换", comment: "")) { choosingFile = true }.buttonStyle(.link).disabled(busy)
                }.font(.caption)
                Text(String(format: NSLocalizedString("%d 帧 · 传输 %@", comment: ""), Int(draft.payload.frameCount),
                    ByteCountFormatter.string(fromByteCount: Int64(draft.payload.bytes.count), countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
                if let summary = draft.adaptationSummary {
                    Label(summary, systemImage: "wand.and.stars").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.defaultDrafts.contains(model.entry) {
                Button("撤销默认素材选择") { model.discardSelection() }
                    .buttonStyle(.link).font(.caption).disabled(busy)
            }
            Text(String(format: NSLocalizedString("最多 %d 帧 · 10 FPS", comment: ""),
                Int(WS3ResourceReadback.maximumFrames(model.entry))))
                .font(.caption).foregroundStyle(.secondary)

            operationFeedback


        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.gif, .png, .jpeg, .bmp, .tiff]) { result in
            switch result {
            case .success(let url):
                if model.entry < 16, model.entry % 4 == 0 { model.selectEntry(model.entry + 3) }
                model.prepare(url)
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .alert(NSLocalizedString("键盘当前素材已变化", comment: ""), isPresented: Binding(get: {
            StudioResourceConflictReadiness.mayPresent(hasConflict: model.conflict != nil,
                editorEnabled: editorEnabled, operationBusy: busy)
        }, set: { if !$0 && editorEnabled && !busy { model.conflict = nil } }), presenting: model.conflict) { conflict in
            Button(NSLocalizedString("采用键盘当前值", comment: "")) { model.adopt(conflict, discardDraft: true) }
            Button(NSLocalizedString("确认修改", comment: "")) {
                model.adopt(conflict, discardDraft: false)
                if let onWrite { onWrite() }
                else { model.write(ble: ble, session: session, restoring: conflict.restoring) }
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) { model.conflict = nil }
        } message: { conflict in Text(conflictDescription(conflict)) }
    }

    private func resourceCard(_ entry: UInt8) -> some View {
        let selected = model.entry == entry || (model.entry < 16 && model.entry % 4 == 0 && entry == model.entry + 3)
        let dirty = model.dirtyEntries.contains(entry) || hasPendingFallback(entry)
        return Button { model.selectEntry(entry) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.2))
                    if let image = model.drafts[entry]?.thumbnail {
                        Image(nsImage: image).resizable().scaledToFit().padding(3)
                    } else {
                        Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.tertiary)
                    }
                }.frame(height: 42)
                HStack(spacing: 4) {
                    Image(systemName: stateIcon(entry))
                    Text(stateTitle(entry)).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if dirty { Circle().fill(.orange).frame(width: 5, height: 5) }
                }.font(.caption.weight(.medium))
                Text(cardStatus(entry)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityLabel(stateTitle(entry) + " · " + cardStatus(entry))
        .accessibilityValue(selected ? NSLocalizedString("已选中", comment: "") : "")
        .help(NSLocalizedString("编辑此状态的画面", comment: ""))
    }

    private var artworkPicker: some View {
        Button { choosingFile = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor))
                if let image = model.draft?.thumbnail {
                    Image(nsImage: image).resizable().scaledToFit().padding(8)
                } else if model.defaultDrafts.contains(model.entry) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                        Text(NSLocalizedString("默认素材（待写入）", comment: "")).font(.caption)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                        Text(NSLocalizedString("选择图片或 GIF…", comment: "")).font(.callout.weight(.medium))
                        if model.selected?.reportsValidUserResource == true {
                            Text(NSLocalizedString("键盘上的图片暂不支持回看", comment: "")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 110).frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain).disabled(busy || model.selected == nil)
        .accessibilityLabel(NSLocalizedString("选择图片或 GIF…", comment: ""))
    }

    @ViewBuilder private var operationFeedback: some View {
        if let progress = ble.oledUploadProgress, model.isBusy {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(progress.completedChunks), total: Double(max(1, progress.totalChunks)))
                HStack {
                    Text(NSLocalizedString("正在写入画面…", comment: ""))
                    Spacer()
                    Text("\(Int(Double(progress.completedChunks) / Double(max(1, progress.totalChunks)) * 100))%")
                        .monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
                if let transfer = progress.transfer {
                    Text(transferDescription(transfer)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Label(WS3ResourceUploadGuidance.cancellationRisk, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        } else if busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString(model.isPreparing ? "正在准备素材…" : "正在处理所选画面…", comment: "")).font(.caption).foregroundStyle(.secondary)
            }
        }
        if model.unconfirmed.contains(model.entry) && !model.isBusy {
            Label(WS3ResourceUploadGuidance.unconfirmed, systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange)
        }
        if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    }

    private func transferDescription(_ value: WS3ResourceTransferProgress) -> String {
        func size(_ bytes: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        var parts = [size(value.completedBytes) + " / " + size(value.totalBytes)]
        if let rate = value.bytesPerSecond {
            parts.append(size(Int(rate.rounded())) + NSLocalizedString("/秒", comment: ""))
        }
        if let remaining = value.estimatedRemainingSeconds, remaining >= 1 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute, .second]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 2
            if let text = formatter.string(from: remaining) {
                parts.append(String(format: NSLocalizedString("预计剩余 %@", comment: ""), text))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var currentStatus: String {
        if model.defaultDrafts.contains(model.entry) { return NSLocalizedString("已选择默认素材，写入后生效。", comment: "") }
        guard let selected = model.selected else { return NSLocalizedString("未读取", comment: "") }
        if model.unconfirmed.contains(model.entry) { return NSLocalizedString("待核对", comment: "") }
        if selected.reportsValidUserResource {
            return String(format: NSLocalizedString("键盘：自定义素材 · %d 帧", comment: ""), Int(selected.frames))
        }
        return NSLocalizedString(WS3ResourceRestoreCommand.reportsDefault(selected) ? "键盘：默认素材" : "键盘素材暂不可用", comment: "")
    }
    private func stateTitle(_ entry: UInt8) -> String {
        let index = entry >= 16 ? Int(entry - 15) : Int(entry % 4)
        return NSLocalizedString(["默认画面", "进行中", "等待处理", "已完成"][index], comment: "")
    }
    private func stateIcon(_ entry: UInt8) -> String {
        let index = entry >= 16 ? Int(entry - 15) : Int(entry % 4)
        return ["photo", "arrow.triangle.2.circlepath", "pause.circle", "checkmark.circle"][index]
    }
    private func hasPendingFallback(_ entry: UInt8) -> Bool {
        entry < 16 && entry % 4 == 3 && model.completedFallbacks.contains(entry - 3) && model.screenDirtyEntries.contains(entry - 3)
    }
    private func cardStatus(_ entry: UInt8) -> String {
        if hasPendingFallback(entry) { return NSLocalizedString("待完成写入", comment: "") }
        if model.defaultDrafts.contains(entry) { return NSLocalizedString("待恢复默认", comment: "") }
        if model.unconfirmed.contains(entry) { return NSLocalizedString("待核对", comment: "") }
        if model.dirtyEntries.contains(entry) { return NSLocalizedString("未写入", comment: "") }
        if let actual = model.display?.resources.first(where: { $0.id == entry }) {
            if actual.reportsValidUserResource { return String(format: NSLocalizedString("已设置 · %d 帧", comment: ""), Int(actual.frames)) }
            if WS3ResourceRestoreCommand.reportsDefault(actual) { return NSLocalizedString("默认显示", comment: "") }
            return NSLocalizedString("待核对", comment: "")
        }
        return NSLocalizedString("未读取", comment: "")
    }
    private var feedback: String? {
        guard let message = model.message else { return nil }
        let routine = ["已读取键盘素材信息。", "素材上传完成，帧数、长度和 CRC 元数据已核对一致；请在键盘确认画面并验证重启保持。", "此位置已恢复默认显示，空素材标记读回一致；请在键盘确认实际显示。", "此画面已恢复默认，请在键盘上确认效果。", "画面已写入，请在键盘上确认效果。"].map { NSLocalizedString($0, comment: "") }
        if routine.contains(message) { return nil }
        if message == NSLocalizedString("所选文件与最近读回的素材元数据一致；实际画面仍需在键盘确认。", comment: "") { return NSLocalizedString("素材与键盘一致", comment: "") }
        if message == NSLocalizedString("所选文件与最近读回的素材元数据不同；本次核对未更改键盘。", comment: "") { return NSLocalizedString("素材不同，尚未写入键盘", comment: "") }
        return message
    }
    private func conflictDescription(_ conflict: StudioResourceInspectorModel.Conflict) -> String {
        let actual = conflict.snapshot.resources.first { $0.id == conflict.entry }
        let current = actual?.reportsValidUserResource == true
            ? String(format: NSLocalizedString("自定义素材 · %d 帧", comment: ""), Int(actual?.frames ?? 0)) : NSLocalizedString("默认显示", comment: "")
        return [StudioResourceInspectorModel.title(conflict.entry), NSLocalizedString("键盘当前：", comment: "") + current,
            NSLocalizedString("待写入：", comment: "") + (conflict.restoring ? NSLocalizedString("默认显示", comment: "") : model.draft?.filename ?? ""),
            NSLocalizedString("键盘内容与开始编辑时不同，草稿已保留。确认后仍会重新核对。", comment: "")].joined(separator: "\n")
    }
}
