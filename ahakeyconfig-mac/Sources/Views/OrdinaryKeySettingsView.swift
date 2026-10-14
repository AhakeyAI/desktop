import SwiftUI
import AhaKeyConfigShared

/// Device-backed editing never imports or applies the old local Studio draft.
struct OrdinaryKeySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var mode: UInt8 = 2
    @State private var index: UInt8 = 3
    @State private var baseline: OrdinaryKeyReadback?
    @State private var action = Data([0x73, 0])
    @State private var descriptionText = ""
    @State private var descriptionEdited = false
    @State private var generation: UInt64?
    @State private var message: String?

    var body: some View {
        Section {
            HStack {
                Picker("模式", selection: $mode) {
                    ForEach(0..<4, id: \.self) { Text("Mode \($0 + 1)").tag(UInt8($0)) }
                }
                Picker("按键", selection: $index) {
                    ForEach(0..<4, id: \.self) { Text("Key \($0 + 1)").tag(UInt8($0)) }
                }
            }
            .disabled(busy)
            .onChange(of: mode) { _ in clearDraft() }
            .onChange(of: index) { _ in clearDraft() }
            Text("键盘当前：\(currentText)").font(.caption).textSelection(.enabled)
            if let baseline, baseline.isKnownEditableAction {
                KeyboardActionEditor(action: $action, allowEmptyShortcut: true, maximumPayloadBytes: max(0, 53 - (target?.description.count ?? 20)))
                    .disabled(busy || !sameSession)
                TextField("待应用描述（英文，最多 20 字节）", text: Binding(get: { descriptionText }, set: {
                    descriptionText = $0; descriptionEdited = true
                }))
                .disabled(busy || !sameSession)
                Text("动作与描述读回共占用 \(11 + max(0, action.count - 2) + (target?.description.count ?? 0)) / 64 字节")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(busy ? "处理中…" : "读取当前按键") { readKey() }
                Button("应用此键改动") { applyKey() }
                    .disabled(!canApply)
            }
            .disabled(busy || !bleManager.isConnected)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text("只编辑所选键，不切换模式或导入旧草稿。Voice 预设未移交时不能改其动作。超长或未知动作保持只读；失败可能已改变键盘临时值，不表示已回滚。保存后的断电保持性仍需验证。")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("普通键 · 差量保存") }
    }

    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var sameSession: Bool { generation == bleManager.configurationSnapshot.generation }
    private var target: OrdinaryKeyReadback? {
        guard let baseline, action.count >= 2 else { return nil }
        var desc = baseline.description
        if descriptionEdited {
            guard let ascii = descriptionText.data(using: .ascii, allowLossyConversion: false) else { return nil }
            desc = ascii
            while desc.last == 0x20 { desc.removeLast() }
        }
        let payload = Data(action.dropFirst(2))
        let kind = baseline.actionType == 0 && action == Data([0x73, 0]) ? UInt8(0) : action[0]
        return .init(mode: mode, keyIndex: index, actionType: kind, action: payload, description: desc)
    }
    private var canApply: Bool {
        guard sameSession, let baseline, let target, baseline != target,
              bleManager.firmwareCapabilityProfile?.mayQueryOrdinaryKeys == true,
              bleManager.configurationSnapshot.keys[.key(mode: mode, index: index)] != nil else { return false }
        return baseline.isKnownEditableAction && OrdinaryKeyConfiguration.valid(target)
    }
    private var currentText: String {
        guard let result = bleManager.configurationSnapshot.keys[.key(mode: mode, index: index)] else { return "未确认" }
        switch result {
        case .value(let key): return "动作 \(key.actionType) · \(key.action.hexString) · 描述 \(String(data: key.description, encoding: .ascii) ?? key.description.hexString)"
        case .tooLarge: return "超过固件读回容量，只读"
        case .rejected(let status): return "读取被拒绝（\(status)）"
        case .malformed: return "格式未确认"
        }
    }
    private func clearDraft() {
        baseline = nil; generation = nil; action = Data([0x73, 0]); descriptionText = ""; descriptionEdited = false; message = nil
    }
    private func load(_ actual: OrdinaryKeyReadback) {
        guard actual.mode == mode, actual.keyIndex == index else { return }
        baseline = actual
        action = actual.actionType == 0 ? Data([0x73, 0]) : Data([actual.actionType, UInt8(actual.action.count)]) + actual.action
        descriptionText = String(data: actual.description, encoding: .ascii) ?? ""
        descriptionEdited = false
        generation = bleManager.configurationSnapshot.generation
    }
    private func readKey() {
        message = nil
        Task { @MainActor in
            do {
                let actual = try await bleManager.readOrdinaryKeyForEditing(mode: mode, index: index)
                guard actual.mode == mode, actual.keyIndex == index else { return }
                if baseline == nil || !sameSession { load(actual) } else { baseline = actual }
            } catch { message = error.localizedDescription }
        }
    }
    private func applyKey() {
        guard let baseline, let target, let generation else { return }
        message = nil
        Task { @MainActor in
            do {
                let actual = try await bleManager.setOrdinaryKeyConfirmed(baseline: baseline, target: target, expectedGeneration: generation)
                load(actual)
                message = "此键改动已保存并读回一致；断电保持性尚未验证。"
            } catch { message = "设置未确认：\(error.localizedDescription)；待应用改动已保留。" }
        }
    }
}
