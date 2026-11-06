import SwiftUI
import AhaKeyConfigShared

struct SideSwitchSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var baseline: SideSwitchReadback?
    @State private var draft: SideSwitchBindingDraft?
    @State private var generation: UInt64?
    @State private var message: String?
    private let labels = [NSLocalizedString("出厂自动", comment: ""), NSLocalizedString("出厂手动", comment: ""), NSLocalizedString("禁用", comment: ""), NSLocalizedString("自定义", comment: "")]

    @State private var writeOutcome: KeyboardWriteOutcome?

    var body: some View {
        Section {
            ForEach(0..<2, id: \.self) { index in
                CompatLabeledContent(String(format: NSLocalizedString("位置 %@ · 键盘当前绑定", comment: ""), String(describing: index + 1))) {
                    Text(currentText(index))
                }
                if let draft, draft.positions.count == 2 {
                    SideSwitchPositionEditor(position: Binding(get: {
                        self.draft?.positions[index] ?? draft.positions[index]
                    }, set: { self.draft?.set($0, at: index) }), title: String(format: NSLocalizedString("位置 %@ · 待应用", comment: ""), String(describing: index + 1)))
                    .disabled(busy || generation != bleManager.configurationSnapshot.generation)
                    Button(String(format: NSLocalizedString("保留位置 %@ 的当前绑定", comment: ""), String(describing: index + 1))) {
                        guard let actual = bleManager.configurationSnapshot.sideSwitch, actual.positions.count == 2 else { return }
                        self.draft?.set(actual.positions[index], at: index)
                    }
                    .disabled(busy || bleManager.configurationSnapshot.sideSwitch == nil || generation != bleManager.configurationSnapshot.generation)
                }
            }
            HStack {
                Button(bleManager.isReadingSideSwitch ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取当前拨杆绑定", comment: "")) {
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
                        } catch { message = KeyboardSettingsFeedback.message(for: error) }
                    }
                }
                Button(bleManager.isSettingSideSwitch ? NSLocalizedString("应用中…", comment: "") : NSLocalizedString("写入键盘", comment: "")) {
                    guard let baseline, let draft, let generation else { return }
                    message = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.setSideSwitchConfirmed(baseline: baseline.positions, target: draft.positions, expectedGeneration: generation)
                            self.baseline = actual
                            self.draft = SideSwitchBindingDraft(readback: actual)
                            message = NSLocalizedString("两档绑定已读回一致；断电后的保存结果仍需重启验证。", comment: "")
                writeOutcome = .init(succeeded: true, message: message ?? "")
                        } catch { message = String(format: NSLocalizedString("绑定未确认：%@；待应用设置已保留。", comment: ""), String(describing: KeyboardSettingsFeedback.message(for: error))) }
                    }
                }
                .disabled(!canApply)
            }
            .disabled(busy || !bleManager.isConnected)
            if let draft {
                Text(String(format: NSLocalizedString("两档动作占用 %@ / 52 字节", comment: ""), String(describing: draft.positions.reduce(0) { $0 + $1.action.count })))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("只自定义一边时，未明确设置的另一边默认禁用。可点“保留当前绑定”明确保留另一边。自定义动作只在实体拨动时执行；只有位置 1 的出厂自动绑定允许自动批准。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(NSLocalizedString("实体拨杆绑定", comment: "")) }
        .keyboardWriteResult($writeOutcome)
    }

    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var canApply: Bool {
        guard let draft, baseline != nil, generation == bleManager.configurationSnapshot.generation,
              bleManager.configurationSnapshot.sideSwitch != nil,
              bleManager.firmwareCapabilityProfile?.mayQuerySideSwitchBindings == true else { return false }
        return SideSwitchBindingConfiguration.request(positions: draft.positions) != nil
    }
    private func currentText(_ index: Int) -> String {
        guard let actual = bleManager.configurationSnapshot.sideSwitch, actual.positions.count == 2 else { return NSLocalizedString("未确认", comment: "") }
        let position = actual.positions[index]
        return labels[Int(position.bindType)] + (position.action.isEmpty ? "" : " · " + position.action.hexString)
    }
}

struct SideSwitchPositionEditor: View {
    @Binding var position: SideSwitchReadback.Position
    let title: String
    private let labels = [NSLocalizedString("出厂自动", comment: ""), NSLocalizedString("出厂手动", comment: ""), NSLocalizedString("禁用", comment: ""), NSLocalizedString("自定义", comment: "")]

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
    var showsActionTypePicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                if showsActionTypePicker {
                    Picker(NSLocalizedString("动作类型", comment: ""), selection: Binding(get: { action.first == 0x74 ? 1 : 0 }, set: { value in
                        action = value == 1 ? Data([0x74, 2, 4, 0]) : Data([0x73, 0])
                    })) {
                        Text(NSLocalizedString("快捷键", comment: "")).tag(0)
                        Text(NSLocalizedString("宏", comment: "")).tag(1)
                    }
                }
                if action.first == 0x74 {
                    if steps.count * 2 == max(0, action.count - 2) { macroEditor }
                    else {
                        Text(NSLocalizedString("当前宏包含无法表示的步骤，保留原始数据。", comment: ""))
                        Button(NSLocalizedString("重新创建宏", comment: "")) { action = Data([0x74, 2, 4, 0]) }
                    }
                } else if Data([0x73, UInt8(shortcut.hidCodes.count)] + shortcut.hidCodes) == action {
                    ShortcutBindingEditor(shortcut: Binding(get: { shortcut }, set: { value in
                        let keys = value.hidCodes
                        action = Data([0x73, UInt8(keys.count)] + keys)
                    }))
                } else {
                    Text(NSLocalizedString("当前组合无法完整表示，保留原始数据。", comment: ""))
                    Button(NSLocalizedString("重新设置快捷键", comment: "")) { action = Data([0x73, 0]) }
                }
                if !(allowEmptyShortcut && action == Data([0x73, 0])) && !SideSwitchBindingConfiguration.validAction(action, maximumBytes: maximumPayloadBytes + 2) {
                    Text(NSLocalizedString("请设置有效快捷键，或检查宏中的按下/松开是否配对。", comment: ""))
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
    private var macroEditor: some View {
        MacroStepsEditor(steps: Binding(get: { steps }, set: { updateSteps($0) }),
                         maximumPayloadBytes: maximumPayloadBytes, minimumDelay: 0)
    }
}
