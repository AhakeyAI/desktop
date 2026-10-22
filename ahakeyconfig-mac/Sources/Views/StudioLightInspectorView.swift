import SwiftUI
import AhaKeyConfigShared

struct StudioLightInspectorView: View {
    @ObservedObject var model: StudioLightInspectorModel
    @ObservedObject var session: StudioInspectorSession
    let bleManager: AhaKeyBLEManager
    let mode: AhaKeyModeSlot
    let selectPreviewState: (UInt8) -> Void
    @State private var showsDiscardDrafts = false

    private var target: StudioLightDrafts.Target { model.target(for: mode) }
    private var busy: Bool { model.isBusy || session.isBusy }
    private var editable: Bool { model.values.facts[target].map { target.accepts($0.value) } ?? false }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(IDEState.workflowOrder) { item in
                    Button { model.selectedState = item.rawValue } label: {
                        Text(item.shortLabel)
                            .font(.caption.weight(model.selectedState == item.rawValue ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(model.selectedState == item.rawValue ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).disabled(busy)
                }
            }

            HStack(spacing: 8) {
                Text(readbackTitle).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if model.values.dirtyTargets.contains(target) { Text("未保存").font(.caption).foregroundStyle(.orange) }
            }
            if model.values.unconfirmed.contains(target) {
                Label("保存结果待确认，请重新读取后保存。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if model.isBusy { ProgressView("处理中…").controlSize(.small) }
            if model.showsError {
                Label("操作未完成，请重试。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Text("选择灯效").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(LightEffectStyle.allCases) { effect in effectCard(effect) }
            }

            brightnessControls
            moreControls
        }
        .alert("键盘当前值已变化", isPresented: Binding(get: { model.conflict != nil }, set: { if !$0 { model.conflict = nil } }), presenting: model.conflict) { conflict in
            Button("确认修改") { model.run(target: conflict.target, ble: bleManager, session: session, save: true, overwrite: conflict) }
            Button("采用键盘当前值") { model.values.adopt(conflict.target) }
            Button("取消", role: .cancel) { }
        } message: { conflict in
            Text(String(format: NSLocalizedString("%@\n键盘当前：%@\n你的选择：%@", comment: ""), StudioLightInspectorModel.scopeTitle(conflict.target), label(conflict.actual.value, target: conflict.target), label(conflict.desired, target: conflict.target)))
        }
        .confirmationDialog("放弃所有未保存的灯光修改？", isPresented: $showsDiscardDrafts) {
            Button("放弃灯光修改", role: .destructive) {
                model.discardDrafts()
                readSelectedState()
            }
        } message: {
            Text("清除全部模式的本地灯光修改；已经写入键盘的更改不会撤销。")
        }
        .onAppear {
            selectPreviewState(model.selectedState)
            if model.values.facts[target] == nil { readSelectedState() }
        }
        .onChange(of: mode) { _ in resetSelectionFeedback() }
        .onChange(of: model.selectedState) { value in
            selectPreviewState(value)
            resetSelectionFeedback()
        }
        .onDisappear { model.cancel() }
    }

    private var readbackTitle: String {
        guard let fact = model.values.facts[target] else { return NSLocalizedString("尚未读取", comment: "") }
        return String(format: NSLocalizedString("已读取：%@", comment: ""), label(fact.value, target: target))
    }

    private func effectCard(_ effect: LightEffectStyle) -> some View {
        let selected = model.values.drafts[target] == effect.firmwareIndex
        return ZStack(alignment: .topTrailing) {
            Button { model.values.edit(target, value: effect.firmwareIndex) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(effect.title).font(.caption.weight(.semibold)).padding(.trailing, 24)
                    Text(effect.detail).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
                .padding(10)
                .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(busy || !editable)
            .accessibilityLabel(effect.title).accessibilityHint(effect.detail)
            if effect != .off {
                Button {
                    model.previewEffect(effect, mode: mode, ble: bleManager, session: session)
                } label: {
                    Image(systemName: "play.circle").font(.system(size: 17))
                        .foregroundStyle(Color.accentColor).frame(width: 25, height: 25)
                }
                .buttonStyle(.plain).padding(5)
                .disabled(busy || !editable || model.values.drafts[.brightness] == nil)
                .help(String(format: NSLocalizedString("预览 %@", comment: ""), effect.title))
                .accessibilityLabel(String(format: NSLocalizedString("预览 %@", comment: ""), effect.title))
            }
        }
    }

    private var brightnessControls: some View {
        let item = StudioLightDrafts.Target.brightness
        let value = model.values.drafts[item]
        let canEdit = model.values.facts[item].map { item.accepts($0.value) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 2)
            HStack(spacing: 8) {
                Text("亮度").font(.subheadline.weight(.semibold))
                Text("全部模式").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value.map { "\($0)%" } ?? "—").font(.caption.monospacedDigit())
                Button("保存亮度") { model.run(target: item, ble: bleManager, session: session, save: true) }
                    .controlSize(.small)
                    .disabled(busy || !canEdit || (!model.values.dirtyTargets.contains(item) && !model.values.unconfirmed.contains(item)))
            }
            Slider(value: Binding(get: { Double(value ?? 35) }, set: { model.values.edit(item, value: UInt8($0.rounded())) }), in: 1...100, step: 1)
                .disabled(busy || !canEdit).accessibilityLabel(NSLocalizedString("灯光亮度", comment: ""))
            if model.values.unconfirmed.contains(item) {
                Text("亮度保存结果待确认，请重新读取后保存。").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var moreControls: some View {
        DisclosureGroup("更多") {
            VStack(alignment: .leading, spacing: 12) {
                Button("查看全部模式灯效") { model.readCatalog(ble: bleManager, session: session) }.disabled(busy)
                if let catalog = model.catalog {
                    Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 6) {
                        GridRow {
                            Text("状态").frame(width: 48, alignment: .leading)
                            ForEach(AhaKeyModeSlot.allCases) { Text($0.name).lineLimit(1).frame(width: 56, alignment: .leading) }
                        }
                        ForEach(IDEState.allCases) { item in
                            GridRow {
                                Text(item.shortLabel).frame(width: 48, alignment: .leading)
                                ForEach(AhaKeyModeSlot.allCases) { slot in
                                    if let light = catalog.light(mode: UInt8(slot.rawValue), state: item.rawValue) {
                                        Text(label(light.effect, target: .effect(mode: light.mode, state: light.state)))
                                            .lineLimit(1).frame(width: 56, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }.font(.caption2)
                }
                ForEach(AhaKeyModeSlot.allCases) { slot in
                    ForEach(IDEState.allCases) { item in
                        if model.values.unconfirmed.contains(.effect(mode: UInt8(slot.rawValue), state: item.rawValue)) {
                            Text(String(format: NSLocalizedString("%@ · %@：待确认", comment: ""), slot.name, item.shortLabel))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if model.showsError, let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
                Button("放弃未保存的灯光修改…") { showsDiscardDrafts = true }.disabled(busy)
            }.padding(.top, 10)
        }.font(.caption)
    }

    private func readSelectedState() {
        model.run(target: target, ble: bleManager, session: session)
    }

    private func resetSelectionFeedback() {
        model.conflict = nil
        model.message = nil
        if model.values.facts[target] == nil { readSelectedState() }
    }

    private func label(_ value: UInt8, target: StudioLightDrafts.Target) -> String {
        if target == .brightness { return "\(value)%" }
        return LightEffectStyle(firmwareIndex: value)?.title ?? NSLocalizedString("未知灯效（只读）", comment: "")
    }
}

struct StudioLightInspectorActions: View {
    @ObservedObject var model: StudioLightInspectorModel
    @ObservedObject var session: StudioInspectorSession
    let bleManager: AhaKeyBLEManager
    let mode: AhaKeyModeSlot

    private var target: StudioLightDrafts.Target { model.target(for: mode) }
    private var busy: Bool { model.isBusy || session.isBusy }
    private var effect: LightEffectStyle? { model.values.drafts[target].flatMap { LightEffectStyle(firmwareIndex: $0) } }
    private var known: Bool { model.values.facts[target].map { target.accepts($0.value) } ?? false }

    var body: some View {
        Group {
            if busy {
                Button("取消") { model.cancel() }
            } else {
                Button("预览") {
                    if let effect { model.previewEffect(effect, mode: mode, ble: bleManager, session: session) }
                }.disabled(!known || effect == nil || effect == .off || model.values.drafts[.brightness] == nil)
                Button("停止") { model.run(target: target, ble: bleManager, session: session, preview: .stop) }
                    .help(NSLocalizedString("停止灯效预览", comment: ""))
            }
            Button("保存灯效") { model.run(target: target, ble: bleManager, session: session, save: true) }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !known || (!model.values.dirtyTargets.contains(target) && !model.values.unconfirmed.contains(target)))
        }.controlSize(.small)
    }
}
