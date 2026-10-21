import SwiftUI
import AhaKeyConfigShared

enum KeyboardSettingsTab: Hashable { case keys, mode, standby, lever, voice, display }

struct KeyboardSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject private var agentManager = AgentManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var tab: KeyboardSettingsTab
    let mode: UInt8
    let index: UInt8
    let proposedKey: OrdinaryKeyReadback?
    let proposalError: String?

    init(bleManager: AhaKeyBLEManager, initialTab: KeyboardSettingsTab = .keys, mode: UInt8 = 2, index: UInt8 = 3,
         proposedKey: OrdinaryKeyReadback? = nil, proposalError: String? = nil) {
        self.bleManager = bleManager
        _tab = State(initialValue: initialTab)
        self.mode = mode; self.index = index
        self.proposedKey = proposedKey; self.proposalError = proposalError
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("键盘设置", comment: "")).font(.title2.bold())
                Spacer()
                Button(bleManager.firmwareCapabilityProfile?.identity == .legacy ? NSLocalizedString("关闭并回到画布", comment: "") : NSLocalizedString("关闭并返回日常连接", comment: "")) {
                    if bleManager.firmwareCapabilityProfile?.identity != .legacy {
                        agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
                    }
                    dismiss()
                }.disabled(busy).keyboardShortcut(.cancelAction)
            }
            Text(NSLocalizedString("打开和浏览不会保存。先读取键盘当前值，再明确应用；重新连接后需重新读取。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(bleManager.isConnected ? NSLocalizedString("设置连接已就绪", comment: "") : (agentManager.isAgentBLEConnected ? NSLocalizedString("后台已连接，进入编辑后可读取和保存", comment: "") : NSLocalizedString("等待设置连接", comment: "")))
                Spacer()
                Button(bleManager.isConnected ? NSLocalizedString("返回日常连接", comment: "") : NSLocalizedString("进入设置编辑", comment: "")) {
                    if !bleManager.isConnected, agentManager.bluetoothConnectionOwner == .ahaKeyStudio {
                        bleManager.userInitiatedConnect()
                    } else {
                        agentManager.setBluetoothConnectionOwner(bleManager.isConnected ? .agentDaemon : .ahaKeyStudio, bleManager: bleManager)
                    }
                }.disabled(busy)
            }
            if busy {
                HStack {
                    Button(NSLocalizedString("取消当前操作", comment: "")) { bleManager.cancelConfigurationOperation() }
                    Text(NSLocalizedString("取消后需重新连接并读取；已发出的更改可能已生效，草稿仍保留。", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(capabilityMessage).font(.caption).foregroundStyle(.secondary)
            TabView(selection: $tab) {
                Form {
                    OrdinaryKeySettingsView(bleManager: bleManager, mode: mode, index: index, proposedKey: proposedKey, proposalError: proposalError)
                }.tabItem { Text(NSLocalizedString("按键", comment: "")) }.tag(KeyboardSettingsTab.keys)
                Form { WorkModeSettingsView(bleManager: bleManager) }.tabItem { Text(NSLocalizedString("工作模式", comment: "")) }.tag(KeyboardSettingsTab.mode)
                Form { StandbySettingsView(bleManager: bleManager) }.tabItem { Text(NSLocalizedString("待机", comment: "")) }.tag(KeyboardSettingsTab.standby)
                Form { SideSwitchSettingsView(bleManager: bleManager) }.tabItem { Text(NSLocalizedString("实体拨杆", comment: "")) }.tag(KeyboardSettingsTab.lever)
                Form { VoiceHandoffSettingsView(bleManager: bleManager) }.tabItem { Text(NSLocalizedString("语音方案", comment: "")) }.tag(KeyboardSettingsTab.voice)
                WS3DisplaySettingsView(bleManager: bleManager)
                    .tabItem { Text(NSLocalizedString("显示与灯光", comment: "")) }.tag(KeyboardSettingsTab.display)
            }.disabled(busy)
        }
        .padding(20).frame(width: 800, height: 720)
        .interactiveDismissDisabled(busy)
    }
    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var capabilityMessage: String {
        switch bleManager.firmwareCapabilityProfile?.identity {
        case .knownWS2Catalog: return NSLocalizedString("此设备支持分别确认按键、待机、拨杆与语音设置；显示与灯光需单独读回确认，素材写入未开放。", comment: "")
        case .legacy: return NSLocalizedString("这是旧版设备，请关闭此面板后使用画布原有保存流程。", comment: "")
        default: return NSLocalizedString("读取当前项目后识别设备能力；未知设备不会开放新设置写入。", comment: "")
        }
    }
}

private struct WorkModeSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var target: UInt8?
    @State private var message: String?
    var body: some View {
        Section {
            Text(String(format: NSLocalizedString("键盘当前模式：%@", comment: ""), String(describing: bleManager.workModeForDisplay.flatMap { AhaKeyModeSlot(rawValue: $0)?.name } ?? NSLocalizedString("未确认", comment: ""))))
            Picker(NSLocalizedString("待切换模式", comment: ""), selection: $target) {
                Text(NSLocalizedString("请选择", comment: "")).tag(Optional<UInt8>.none)
                ForEach(AhaKeyModeSlot.allCases) { Text($0.name).tag(Optional(UInt8($0.rawValue))) }
            }
            Button(NSLocalizedString("切换并核对模式", comment: "")) {
                guard let target else { return }
                message = nil
                Task { @MainActor in
                    do {
                        let actual = try await bleManager.switchWorkModeConfirmed(target)
                        message = String(format: NSLocalizedString("键盘已确认切换到 %@。", comment: ""), String(describing: AhaKeyModeSlot(rawValue: Int(actual))?.name ?? NSLocalizedString("所选模式", comment: "")))
                    } catch { message = String(format: NSLocalizedString("切换未确认：%@", comment: ""), String(describing: KeyboardSettingsFeedback.message(for: error))) }
                }
            }.disabled(target == nil || !bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
            if let message { Text(message).font(.caption) }
            Text(NSLocalizedString("只切换工作模式，不保存按键或显示配置；实体拨杆档位仍由键盘决定。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(NSLocalizedString("工作模式", comment: "")) }
    }
}
