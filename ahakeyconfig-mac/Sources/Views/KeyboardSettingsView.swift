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
                Text("键盘设置").font(.title2.bold())
                Spacer()
                Button(bleManager.firmwareCapabilityProfile?.identity == .legacy ? "关闭并回到画布" : "关闭并返回日常连接") {
                    if bleManager.firmwareCapabilityProfile?.identity != .legacy {
                        agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
                    }
                    dismiss()
                }.disabled(busy).keyboardShortcut(.cancelAction)
            }
            Text("打开和浏览不会保存。先读取键盘当前值，再明确应用；重新连接后需重新读取。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(bleManager.isConnected ? "设置连接已就绪" : (agentManager.isAgentBLEConnected ? "后台已连接，进入编辑后可读取和保存" : "等待设置连接"))
                Spacer()
                Button(bleManager.isConnected ? "返回日常连接" : "进入设置编辑") {
                    if !bleManager.isConnected, agentManager.bluetoothConnectionOwner == .ahaKeyStudio {
                        bleManager.userInitiatedConnect()
                    } else {
                        agentManager.setBluetoothConnectionOwner(bleManager.isConnected ? .agentDaemon : .ahaKeyStudio, bleManager: bleManager)
                    }
                }.disabled(busy)
            }
            Text(capabilityMessage).font(.caption).foregroundStyle(.secondary)
            TabView(selection: $tab) {
                Form {
                    OrdinaryKeySettingsView(bleManager: bleManager, mode: mode, index: index, proposedKey: proposedKey, proposalError: proposalError)
                }.tabItem { Text("按键") }.tag(KeyboardSettingsTab.keys)
                Form { WorkModeSettingsView(bleManager: bleManager) }.tabItem { Text("工作模式") }.tag(KeyboardSettingsTab.mode)
                Form { StandbySettingsView(bleManager: bleManager) }.tabItem { Text("待机") }.tag(KeyboardSettingsTab.standby)
                Form { SideSwitchSettingsView(bleManager: bleManager) }.tabItem { Text("实体拨杆") }.tag(KeyboardSettingsTab.lever)
                Form { VoiceHandoffSettingsView(bleManager: bleManager) }.tabItem { Text("语音方案") }.tag(KeyboardSettingsTab.voice)
                VStack(alignment: .leading, spacing: 12) {
                    Text("显示与灯光").font(.headline)
                    Text("画布中的素材和预览仍保留。新固件的显示、灯光保存尚未适配完成，当前不能在此应用。")
                    Text("旧版设备继续使用画布原有保存流程。")
                    Spacer()
                }.padding().tabItem { Text("显示与灯光") }.tag(KeyboardSettingsTab.display)
            }.disabled(busy)
        }
        .padding(20).frame(width: 800, height: 720)
        .interactiveDismissDisabled(busy)
    }
    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var capabilityMessage: String {
        switch bleManager.firmwareCapabilityProfile?.identity {
        case .knownWS2Catalog: return "此设备支持分别确认按键、待机、拨杆与语音设置；未开放显示与灯光保存。"
        case .legacy: return "这是旧版设备，请关闭此面板后使用画布原有保存流程。"
        default: return "读取当前项目后识别设备能力；未知设备不会开放新设置写入。"
        }
    }
}

private struct WorkModeSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var target: UInt8?
    @State private var message: String?
    var body: some View {
        Section {
            Text("键盘当前模式：\(bleManager.workModeForDisplay.flatMap { AhaKeyModeSlot(rawValue: $0)?.name } ?? "未确认")")
            Picker("待切换模式", selection: $target) {
                Text("请选择").tag(Optional<UInt8>.none)
                ForEach(AhaKeyModeSlot.allCases) { Text($0.name).tag(Optional(UInt8($0.rawValue))) }
            }
            Button("切换并核对模式") {
                guard let target else { return }
                message = nil
                Task { @MainActor in
                    do {
                        let actual = try await bleManager.switchWorkModeConfirmed(target)
                        message = "键盘已确认切换到 \(AhaKeyModeSlot(rawValue: Int(actual))?.name ?? "所选模式")。"
                    } catch { message = "切换未确认：\(error.localizedDescription)" }
                }
            }.disabled(target == nil || !bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
            if let message { Text(message).font(.caption) }
            Text("只切换工作模式，不保存按键或显示配置；实体拨杆档位仍由键盘决定。")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("工作模式") }
    }
}
