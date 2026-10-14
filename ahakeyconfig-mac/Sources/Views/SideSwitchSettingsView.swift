import SwiftUI
import AhaKeyConfigShared

struct SideSwitchSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var baseline: SideSwitchReadback?
    @State private var draft: SideSwitchBindingDraft?
    @State private var generation: UInt64?
    @State private var message: String?
    private let labels = ["出厂自动", "出厂手动", "禁用", "自定义"]

    var body: some View {
        Section {
            ForEach(0..<2, id: \.self) { index in
                CompatLabeledContent("位置 \(index + 1) · 键盘当前绑定") {
                    Text(currentText(index))
                }
                if let draft, draft.positions.count == 2 {
                    SideSwitchPositionEditor(position: Binding(get: {
                        self.draft?.positions[index] ?? draft.positions[index]
                    }, set: { self.draft?.set($0, at: index) }), title: "位置 \(index + 1) · 待应用")
                    .disabled(busy || generation != bleManager.configurationSnapshot.generation)
                    Button("保留位置 \(index + 1) 的当前绑定") {
                        guard let actual = bleManager.configurationSnapshot.sideSwitch, actual.positions.count == 2 else { return }
                        self.draft?.set(actual.positions[index], at: index)
                    }
                    .disabled(busy || bleManager.configurationSnapshot.sideSwitch == nil || generation != bleManager.configurationSnapshot.generation)
                }
            }
            HStack {
                Button(bleManager.isReadingSideSwitch ? "读取中…" : "读取当前拨杆绑定") {
                    message = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.readSideSwitchForEditing()
                            // A refresh after a failed save preserves the draft on the same connection.
                            if draft == nil || generation != bleManager.configurationSnapshot.generation {
                                draft = SideSwitchBindingDraft(readback: actual)
                            }
                            baseline = actual
                            generation = bleManager.configurationSnapshot.generation
                        } catch { message = error.localizedDescription }
                    }
                }
                Button(bleManager.isSettingSideSwitch ? "应用中…" : "应用两档绑定") {
                    guard let baseline, let draft, let generation else { return }
                    message = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.setSideSwitchConfirmed(baseline: baseline.positions, target: draft.positions, expectedGeneration: generation)
                            self.baseline = actual
                            self.draft = SideSwitchBindingDraft(readback: actual)
                            message = "两档绑定已读回一致；断电后的保存结果仍需重启验证。"
                        } catch { message = "绑定未确认：\(error.localizedDescription)；待应用设置已保留。" }
                    }
                }
                .disabled(!canApply)
            }
            .disabled(busy || !bleManager.isConnected)
            if let draft {
                Text("两档动作占用 \(draft.positions.reduce(0) { $0 + $1.action.count }) / 52 字节")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text("只自定义一边时，未明确设置的另一边默认禁用。可点“保留当前绑定”明确保留另一边。自定义动作只在实体拨动时执行；只有位置 1 的出厂自动绑定允许自动批准。")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("实体拨杆绑定") }
    }

    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var canApply: Bool {
        guard let draft, baseline != nil, generation == bleManager.configurationSnapshot.generation,
              bleManager.configurationSnapshot.sideSwitch != nil,
              bleManager.firmwareCapabilityProfile?.mayQuerySideSwitchBindings == true else { return false }
        return SideSwitchBindingConfiguration.request(positions: draft.positions) != nil
    }
    private func currentText(_ index: Int) -> String {
        guard let actual = bleManager.configurationSnapshot.sideSwitch, actual.positions.count == 2 else { return "未确认" }
        let position = actual.positions[index]
        return labels[Int(position.bindType)] + (position.action.isEmpty ? "" : " · " + position.action.hexString)
    }
}

private struct SideSwitchPositionEditor: View {
    @Binding var position: SideSwitchReadback.Position
    let title: String
    private let labels = ["出厂自动", "出厂手动", "禁用", "自定义"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: Binding(get: { Int(position.bindType) }, set: { value in
                position = .init(bindType: UInt8(value), action: value == 3 ? Data([0x73, 0]) : Data())
            })) {
                ForEach(0..<4, id: \.self) { Text(labels[$0]).tag($0) }
            }
            if position.bindType == 3 {
                KeyboardActionEditor(action: Binding(get: { position.action }, set: { position = .init(bindType: 3, action: $0) }))
            }
        }
    }

}

struct KeyboardActionEditor: View {
    @Binding var action: Data
    var allowEmptyShortcut = false
    var maximumPayloadBytes = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                Picker("动作类型", selection: Binding(get: { action.first == 0x74 ? 1 : 0 }, set: { value in
                    action = value == 1 ? Data([0x74, 2, 4, 0]) : Data([0x73, 0])
                })) {
                    Text("快捷键").tag(0)
                    Text("宏").tag(1)
                }
                if action.first == 0x74 {
                    if steps.count * 2 == max(0, action.count - 2) { macroEditor }
                    else {
                        Text("当前宏包含无法表示的步骤，保留原始数据。")
                        Button("重新创建宏") { action = Data([0x74, 2, 4, 0]) }
                    }
                } else if Data([0x73, UInt8(shortcut.hidCodes.count)] + shortcut.hidCodes) == action {
                    ShortcutBindingEditor(shortcut: Binding(get: { shortcut }, set: { value in
                        let keys = value.hidCodes
                        action = Data([0x73, UInt8(keys.count)] + keys)
                    }))
                } else {
                    Text("当前组合无法完整表示，保留原始数据。")
                    Button("重新设置快捷键") { action = Data([0x73, 0]) }
                }
                if !(allowEmptyShortcut && action == Data([0x73, 0])) && !SideSwitchBindingConfiguration.validAction(action, maximumBytes: maximumPayloadBytes + 2) {
                    Text("请设置有效快捷键，或检查宏中的按下/松开是否配对。")
                        .font(.caption).foregroundStyle(.orange)
                }
        }
    }

    private var shortcut: ShortcutBinding {
        let codes = Array(action.dropFirst(2))
        let modifiers = ShortcutModifier.allCases.filter { codes.contains($0.hidCode) }
        return ShortcutBinding(modifiers: modifiers, keyCode: codes.first { !modifiers.map(\.hidCode).contains($0) } ?? 0)
    }
    private var steps: [MacroStep] {
        let b = Array(action.dropFirst(2))
        guard b.count % 2 == 0 else { return [] }
        return stride(from: 0, to: b.count, by: 2).compactMap { index in
            MacroAction(rawValue: b[index]).map { MacroStep(action: $0, param: b[index + 1]) }
        }
    }
    private func updateSteps(_ next: [MacroStep]) {
        let bytes = next.flattenedBytes
        guard bytes.count <= maximumPayloadBytes else { return }
        action = Data([0x74, UInt8(bytes.count)] + bytes)
    }
    private func step(at index: Int) -> MacroStep {
        steps.indices.contains(index) ? steps[index] : MacroStep(action: .noOp)
    }
    private var macroEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                HStack {
                    Text("\(index + 1)")
                    Picker("动作", selection: Binding(get: { step(at: index).action }, set: { action in
                        var next = steps; guard next.indices.contains(index) else { return }; next[index].action = action
                        next[index].param = action.takesKeycodeParam ? HIDUsage.enter : 0
                        updateSteps(next)
                    })) {
                        ForEach(MacroAction.allCases) { Text($0.title).tag($0) }
                    }
                    if step(at: index).action.takesKeycodeParam {
                        Picker("按键", selection: Binding(get: { step(at: index).param }, set: { value in
                            var next = steps; guard next.indices.contains(index) else { return }; next[index].param = value; updateSteps(next)
                        })) {
                            ForEach(HIDUsage.allOptions, id: \.code) { Text($0.name).tag($0.code) }
                        }
                    } else if step(at: index).action.takesDelayParam {
                        Stepper("\(Int(step(at: index).param) * 3) ms", value: Binding(get: { Int(step(at: index).param) }, set: { value in
                            var next = steps; guard next.indices.contains(index) else { return }; next[index].param = UInt8(value); updateSteps(next)
                        }), in: 0...255)
                    }
                    Button("删除") { var next = steps; guard next.indices.contains(index) else { return }; next.remove(at: index); updateSteps(next) }
                }
            }
            HStack {
                Button("添加按键步骤") { updateSteps(steps + [MacroStep(action: .downKey, param: HIDUsage.enter)]) }
                Button("添加全部松开") { updateSteps(steps + [MacroStep(action: .upAllKeys)]) }
            }.disabled(steps.count >= maximumPayloadBytes / 2)
        }
    }
}
