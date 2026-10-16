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
            Text(String(format: NSLocalizedString("键盘当前语音：%@", comment: ""), String(describing: currentState)))
            if let baseline, sameSession {
                ForEach(baseline.keys, id: \.mode) { key in
                    Text(String(format: NSLocalizedString("上次读取 Mode %@ · Voice：%@ / %@", comment: ""), String(describing: Int(key.mode) + 1), String(describing: key.actionType), String(describing: key.action.hexString)))
                        .font(.caption).textSelection(.enabled)
                }
            }
            Button(bleManager.isManagingVoiceHandoff ? NSLocalizedString("处理中…", comment: "") : NSLocalizedString("读取四模式语音状态（只读）", comment: "")) { readState() }
                .disabled(busy || !bleManager.isConnected)
            Picker(NSLocalizedString("明确切换到", comment: ""), selection: $choice) {
                Text(NSLocalizedString("保留键盘当前方案", comment: "")).tag(Optional<DesktopSpeechChoice>.none)
                ForEach(DesktopSpeechChoice.allCases) { Text($0.title).tag(Optional($0)) }
            }.disabled(busy)
            Button(NSLocalizedString("接管四个模式的 Voice 键…", comment: "")) { showsConfirmation = true }
                .disabled(busy || !bleManager.isConnected || !sameSession || baseline == nil || choice == nil)
            if choice == .ahaType {
                Text(NSLocalizedString("识别后的文字会发送给 AhaType 整理，需要已登录账号；云端可用性在实际转写时验证。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("保持当前方案不会写入键盘。App 接管需要 App 运行以及麦克风、语音识别、输入监控和辅助功能权限。切换会覆盖四个模式的 Voice 绑定并关闭固件系统听写；当前固件不支持在客户端一键切回 Consumer。其他按键不变。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(NSLocalizedString("语音方案 · 显式接管", comment: "")) }
        .confirmationDialog(NSLocalizedString("确认切换全部四个模式的 Voice？", comment: ""), isPresented: $showsConfirmation) {
            Button(String(format: NSLocalizedString("确认切换至 %@", comment: ""), String(describing: choice?.title ?? "App"))) { apply() }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("将先准备 App 语音与四个 Voice 绑定并读回，再关闭固件系统听写。当前固件不支持客户端一键恢复 Consumer。原 Voice 绑定会本地备份；失败可能已有部分变更。%@", comment: ""), String(describing: choice == .ahaType ? NSLocalizedString("识别文字将发送给 AhaType 整理。", comment: "") : "")))
        }
    }
    private var busy: Bool { bleManager.isConfigurationOperationInProgress }
    private var sameSession: Bool { generation == bleManager.configurationSnapshot.generation }
    private var currentState: String {
        guard let state = bleManager.configurationSnapshot.voiceOnboardingState else { return NSLocalizedString("未确认", comment: "") }
        switch state {
        case 0: return NSLocalizedString("固件平台未选择", comment: "")
        case 1: return NSLocalizedString("固件 Windows 语音预设", comment: "")
        case 2: return NSLocalizedString("固件 Mac 系统听写（Consumer）", comment: "")
        case 3: return liveDesktopBindingsConfirmed && sameSession ? NSLocalizedString("桌面接管，四个 F18 绑定已确认", comment: "") : NSLocalizedString("桌面接管，Voice 绑定未确认", comment: "")
        default: return NSLocalizedString("固件语音预设已跳过", comment: "")
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
                NotificationCenter.default.post(name: .ahaKeyVoiceDesktopConfirmed, object: nil)
                message = NSLocalizedString("键盘接管和四个触发绑定已读回确认。请在文本框短按开始、再次短按停止，验证实际语音输入；读回不能证明系统已转写。", comment: "")
            } catch {
                message = String(format: NSLocalizedString("切换未确认：%@；App 路由或键盘可能已有部分变更，请重新读取核对。", comment: ""), String(describing: error.localizedDescription))
            }
        }
    }
}
