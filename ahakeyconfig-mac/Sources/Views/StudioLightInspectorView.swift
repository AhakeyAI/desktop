import SwiftUI
import AhaKeyConfigShared

struct StudioLightInspectorView: View {
    @ObservedObject var model: StudioLightInspectorModel
    @ObservedObject var session: StudioInspectorSession
    let bleManager: AhaKeyBLEManager
    let mode: AhaKeyModeSlot
    let selectPreviewState: (UInt8) -> Void
    @State private var state: UInt8 = 0
    @State private var showsDiscardDrafts = false

    private var target: StudioLightDrafts.Target { .effect(mode: UInt8(mode.rawValue), state: state) }
    private var busy: Bool { model.isBusy || session.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioInspectorSection("状态灯效") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(mode.name).font(.headline)
                    Picker("工作状态", selection: $state) {
                        ForEach(IDEState.allCases) { Text($0.label).tag($0.rawValue) }
                    }.disabled(busy)
                    controls(target, title: "灯效")
                    Text("只保存当前模式的所选状态，不切换实体模式。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            StudioInspectorSection("全局亮度") {
                VStack(alignment: .leading, spacing: 10) {
                    controls(.brightness, title: "亮度")
                    Text("亮度对全部模式生效，单独保存，不会带存其他草稿。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("四模式灯效总览（只读）") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("读取全部 36 项灯效") { model.readCatalog(ble: bleManager, session: session) }.disabled(busy)
                    if let catalog = model.catalog {
                        Text("上次完整读回；不代表当前连接已确认。").font(.caption).foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 6) {
                            GridRow {
                                Text("状态").frame(width: 48, alignment: .leading)
                                ForEach(AhaKeyModeSlot.allCases) { Text($0.name).lineLimit(1).frame(width: 56, alignment: .leading) }
                            }
                            ForEach(IDEState.allCases) { state in
                                GridRow {
                                    Text(state.shortLabel).frame(width: 48, alignment: .leading)
                                    ForEach(AhaKeyModeSlot.allCases) { slot in
                                        if let light = catalog.light(mode: UInt8(slot.rawValue), state: state.rawValue) {
                                            Text(label(light.effect, target: .effect(mode: light.mode, state: light.state)))
                                                .lineLimit(1).frame(width: 56, alignment: .leading)
                                                .help(slot.name + " · " + state.label + "：" + label(light.effect, target: target))
                                        }
                                    }
                                }
                            }
                        }.font(.caption2)
                    }
                    Text("读取不会播放、保存或覆盖未保存的草稿。").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            HStack {
                Button("停止临时预览") { run(target, preview: .stop) }.disabled(busy)
                if busy { Button("取消当前操作") { model.cancel() } }
            }
            ForEach(AhaKeyModeSlot.allCases) { slot in
                ForEach(IDEState.allCases) { item in
                    if model.values.unconfirmed.contains(.effect(mode: UInt8(slot.rawValue), state: item.rawValue)) {
                        Text(slot.name + " · " + item.label + "：保存尚未确认，请重新读取并保存核对。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            if model.isBusy { ProgressView("正在核对键盘…").controlSize(.small) }
            if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            Button("清除本地灯光草稿…") { showsDiscardDrafts = true }
                .font(.caption).disabled(busy)
            Text("仅读取、保存或预览时临时连接；结束后交还后台。读回一致不代表已验证断电保持。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .alert("键盘当前值已变化", isPresented: Binding(get: { model.conflict != nil }, set: { if !$0 { model.conflict = nil } }), presenting: model.conflict) { conflict in
            Button("确认修改") { model.run(target: conflict.target, ble: bleManager, session: session, save: true, overwrite: conflict) }
            Button("采用键盘当前值") { model.values.adopt(conflict.target) }
            Button("取消", role: .cancel) { }
        } message: { conflict in
            Text("键盘当前：\(label(conflict.actual.value, target: conflict.target))\n你的草稿：\(label(conflict.desired, target: conflict.target))\n确认后仍会重新读取并核对。")
        }
        .confirmationDialog("清除本地灯光草稿和读回记录？", isPresented: $showsDiscardDrafts) {
            Button("清除本地灯光草稿", role: .destructive) {
                model.discardDrafts()
            }
        } message: {
            Text("清除全部模式的本地灯光草稿和读回记录，以便重新读取或更换键盘；不会修改键位、语音或键盘保存值。")
        }
        .onAppear { selectPreviewState(state) }
        .onChange(of: mode) { _ in model.conflict = nil; model.message = nil }
        .onChange(of: state) { value in model.conflict = nil; model.message = nil; selectPreviewState(value) }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private func controls(_ item: StudioLightDrafts.Target, title: String) -> some View {
        let fact = model.values.facts[item]
        let value = model.values.drafts[item]
        let editable = fact.map { item.accepts($0.value) } ?? false
        HStack {
            Text(fact.map { "上次读回：" + label($0.value, target: item) } ?? "尚未读取")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { run(item) } label: { Label("读取", systemImage: "arrow.clockwise") }.disabled(busy)
        }
        if item == .brightness {
            HStack {
                Slider(value: Binding(get: { Double(value ?? 50) }, set: { model.values.edit(item, value: UInt8($0.rounded())) }), in: 1...100, step: 1)
                Text(value.map { "\($0)%" } ?? "—").monospacedDigit()
            }.disabled(busy || !editable)
        } else {
            Picker(title, selection: Binding(get: { value }, set: { if let value = $0 { model.values.edit(item, value: value) } })) {
                Text("请选择").tag(Optional<UInt8>.none)
                ForEach(LightEffectStyle.allCases) { Text($0.title).tag(Optional($0.firmwareIndex)) }
                if let value, !item.accepts(value) { Text("未知灯效（只读）").tag(Optional(value)) }
            }.disabled(busy || !editable)
        }
        if let fact, value != fact.value {
            Button("采用键盘读回值") { model.values.adopt(item) }.disabled(busy)
        }
        HStack {
            Button("预览（10 秒）") {
                guard let value else { return }
                if item == .brightness { run(item, preview: .brightness(value)) }
                else if let brightness = model.values.drafts[.brightness] {
                    run(item, preview: .light(effect: value, brightness: brightness))
                }
            }.disabled(busy || !editable || value == nil || (item != .brightness && (value == 0 || model.values.drafts[.brightness] == nil)))
            Button("保存" + title) { model.run(target: item, ble: bleManager, session: session, save: true) }
                .disabled(busy || !editable || value == nil)
        }
        if model.values.unconfirmed.contains(item) {
            Text("本项保存尚未确认，已发出的修改可能生效；请重新读取并核对保存。")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func run(_ item: StudioLightDrafts.Target, preview: WS3DisplayPreview? = nil) {
        model.run(target: item, ble: bleManager, session: session, preview: preview)
    }

    private func label(_ value: UInt8, target: StudioLightDrafts.Target) -> String {
        if target == .brightness { return "\(value)%" }
        return LightEffectStyle(firmwareIndex: value)?.title ?? "未知灯效 \(value)（只读）"
    }
}
