import SwiftUI
import AhaKeyConfigShared

struct VoiceHandoffSettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var baseline: VoiceHandoffSnapshot?
    @State private var generation: UInt64?
    @State private var choice: DesktopSpeechChoice?
    @State private var showsConfirmation = false
    @State private var message: String?

    var body: some View {
        Section {
            Text("键盘当前语音：\(currentState)")
            if let baseline, sameSession {
                ForEach(baseline.keys, id: \.mode) { key in
                    Text("上次读取 Mode \(Int(key.mode) + 1) · Voice：\(key.actionType) / \(key.action.hexString)")
                        .font(.caption).textSelection(.enabled)
                }
            }
            Button(bleManager.isManagingVoiceHandoff ? "处理中…" : "读取四模式语音状态（只读）") { readState() }
                .disabled(busy || !bleManager.isConnected)
            Picker("明确切换到", selection: $choice) {
                Text("保留键盘当前方案").tag(Optional<DesktopSpeechChoice>.none)
                ForEach(DesktopSpeechChoice.allCases) { Text($0.title).tag(Optional($0)) }
            }.disabled(busy)
            Button("接管四个模式的 Voice 键…") { showsConfirmation = true }
                .disabled(busy || !bleManager.isConnected || !sameSession || baseline == nil || choice == nil)
            if choice == .ahaType {
                Text("识别后的文字会发送给 AhaType 整理，需要已登录账号；云端可用性在实际转写时验证。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text("保持当前方案不会写入键盘。App 接管需要 App 运行以及麦克风、语音识别、输入监控和辅助功能权限。切换会覆盖四个模式的 Voice 绑定并关闭固件系统听写；当前固件不支持在客户端一键切回 Consumer。其他按键不变。")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("语音方案 · 显式接管") }
        .confirmationDialog("确认切换全部四个模式的 Voice？", isPresented: $showsConfirmation) {
            Button("确认切换至 \(choice?.title ?? "App")") { apply() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先准备 App 语音与四个 Voice 绑定并读回，再关闭固件系统听写。当前固件不支持客户端一键恢复 Consumer。原 Voice 绑定会本地备份；失败可能已有部分变更。\(choice == .ahaType ? "识别文字将发送给 AhaType 整理。" : "")")
        }
    }
    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var sameSession: Bool { generation == bleManager.configurationSnapshot.generation }
    private var currentState: String {
        guard let state = bleManager.configurationSnapshot.voiceOnboardingState else { return "未确认" }
        switch state {
        case 0: return "固件平台未选择"
        case 1: return "固件 Windows 语音预设"
        case 2: return "固件 Mac 系统听写（Consumer）"
        case 3: return liveDesktopBindingsConfirmed && sameSession ? "桌面接管，四个 F18 绑定已确认" : "桌面接管，Voice 绑定未确认"
        default: return "固件语音预设已跳过"
        }
    }
    private var liveDesktopBindingsConfirmed: Bool {
        var keys: [OrdinaryKeyReadback] = []
        for mode: UInt8 in 0..<4 {
            guard case .value(let key) = bleManager.configurationSnapshot.keys[.key(mode: mode, index: 0)] else { return false }
            keys.append(key)
        }
        return VoiceHandoffSnapshot(onboardingState: bleManager.configurationSnapshot.voiceOnboardingState ?? 255, keys: keys).isDesktopF18Confirmed
    }
    private func readState() {
        message = nil
        Task { @MainActor in
            do {
                baseline = try await bleManager.readVoiceHandoffForEditing()
                generation = bleManager.configurationSnapshot.generation
            } catch { baseline = nil; message = error.localizedDescription }
        }
    }
    private func apply() {
        guard let baseline, let generation, let choice else { return }
        message = nil
        Task { @MainActor in
            do {
                let actual = try await bleManager.takeOverVoiceConfirmed(baseline: baseline, expectedGeneration: generation,
                    checkHostReady: { try VoiceHandoffHost.checkReady(choice) },
                    prepareHost: { try VoiceHandoffHost.prepare(choice, baseline: baseline) })
                self.baseline = actual
                message = "键盘接管和四个触发绑定已读回确认。请在文本框短按开始、再次短按停止，验证实际语音输入；读回不能证明系统已转写。"
            } catch {
                message = "切换未确认：\(error.localizedDescription)；App 路由或键盘可能已有部分变更，请重新读取核对。"
            }
        }
    }
}
