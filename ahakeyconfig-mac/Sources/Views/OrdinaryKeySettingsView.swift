import SwiftUI
import AhaKeyConfigShared

/// Device-backed editing can load a reviewed proposal only after an explicit read.
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

    let proposedKey: OrdinaryKeyReadback?
    let proposalError: String?

    init(bleManager: AhaKeyBLEManager, mode: UInt8 = 2, index: UInt8 = 3,
         proposedKey: OrdinaryKeyReadback? = nil, proposalError: String? = nil) {
        self.bleManager = bleManager
        _mode = State(initialValue: mode)
        _index = State(initialValue: index)
        self.proposedKey = proposedKey
        self.proposalError = proposalError
    }

    var body: some View {
        Section {
            HStack {
                Picker(NSLocalizedString("模式", comment: ""), selection: $mode) {
                    ForEach(0..<4, id: \.self) { Text("Mode \($0 + 1)").tag(UInt8($0)) }
                }
                Picker(NSLocalizedString("按键", comment: ""), selection: $index) {
                    ForEach(0..<4, id: \.self) { Text("Key \($0 + 1)").tag(UInt8($0)) }
                }
            }
            .disabled(busy)
            .onChange(of: mode) { _ in clearDraft() }
            .onChange(of: index) { _ in clearDraft() }
            Text(String(format: NSLocalizedString("键盘当前：%@", comment: ""), String(describing: currentText))).font(.caption).textSelection(.enabled)
            if let baseline, baseline.isKnownEditableAction {
                KeyboardActionEditor(action: $action, allowEmptyShortcut: true, maximumPayloadBytes: max(0, 53 - (target?.description.count ?? 20)))
                    .disabled(busy || !sameSession)
                TextField(NSLocalizedString("待应用描述（英文，最多 20 字节）", comment: ""), text: Binding(get: { descriptionText }, set: {
                    descriptionText = $0; descriptionEdited = true
                }))
                .disabled(busy || !sameSession)
                Text(String(format: NSLocalizedString("动作与描述读回共占用 %@ / 64 字节", comment: ""), String(describing: 11 + max(0, action.count - 2) + (target?.description.count ?? 0))))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let proposedKey {
                Button(NSLocalizedString("从画布载入此键草稿（不写入）", comment: "")) {
                    guard baseline != nil, sameSession, proposedKey.mode == mode, proposedKey.keyIndex == index else { return }
                    action = Data([proposedKey.actionType, UInt8(proposedKey.action.count)]) + proposedKey.action
                    descriptionText = String(data: proposedKey.description, encoding: .ascii) ?? ""
                    descriptionEdited = true
                    message = NSLocalizedString("已载入待应用草稿，键盘当前值未改变；核对后点击应用。", comment: "")
                }
                .disabled(busy || !sameSession || baseline?.isKnownEditableAction != true || proposedKey.mode != mode || proposedKey.keyIndex != index)
            }
            if let proposalError { Text(proposalError).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(busy ? NSLocalizedString("处理中…", comment: "") : NSLocalizedString("读取当前按键", comment: "")) { readKey() }
                Button(NSLocalizedString("应用此键改动", comment: "")) { applyKey() }
                    .disabled(!canApply)
            }
            .disabled(busy || !bleManager.isConnected)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("只编辑所选键，不切换模式或导入旧草稿。Voice 预设未移交时不能改其动作。超长或未知动作保持只读；失败可能已改变键盘临时值，不表示已回滚。保存后的断电保持性仍需验证。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(NSLocalizedString("普通键 · 差量保存", comment: "")) }
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
        guard let result = bleManager.configurationSnapshot.keys[.key(mode: mode, index: index)] else { return NSLocalizedString("未确认", comment: "") }
        switch result {
        case .value(let key):
            let action: String
            switch key.actionType {
            case 0: action = NSLocalizedString("无按键动作", comment: "")
            case 0x73: action = key.action.isEmpty ? NSLocalizedString("无按键动作", comment: "") : key.action.map { HIDUsage.name(for: $0) }.joined(separator: " + ")
            case 0x74: action = key.action.count % 2 == 0 ? String(format: NSLocalizedString("宏（%@ 步）", comment: ""), String(describing: key.action.count / 2)) : NSLocalizedString("未识别宏，保留原数据", comment: "")
            default: action = NSLocalizedString("未识别动作，保留原数据", comment: "")
            }
            return String(format: NSLocalizedString("%@ · 描述 %@", comment: ""), String(describing: action), String(describing: String(data: key.description, encoding: .ascii) ?? NSLocalizedString("无法显示，保留原描述", comment: "")))
        case .tooLarge: return NSLocalizedString("超过固件读回容量，只读", comment: "")
        case .rejected(let status): return String(format: NSLocalizedString("读取被拒绝（%@）", comment: ""), String(describing: status))
        case .malformed: return NSLocalizedString("格式未确认", comment: "")
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
            } catch { message = KeyboardSettingsFeedback.message(for: error) }
        }
    }
    private func applyKey() {
        guard let baseline, let target, let generation else { return }
        message = nil
        Task { @MainActor in
            do {
                let actual = try await bleManager.setOrdinaryKeyConfirmed(baseline: baseline, target: target, expectedGeneration: generation)
                load(actual)
                NotificationCenter.default.post(name: .ahaKeyOrdinaryKeyConfirmed, object: actual)
                message = NSLocalizedString("此键改动已保存并读回一致；断电保持性尚未验证。", comment: "")
            } catch { message = String(format: NSLocalizedString("设置未确认：%@；待应用改动已保留。", comment: ""), String(describing: KeyboardSettingsFeedback.message(for: error))) }
        }
    }
}
