import SwiftUI
import AhaKeyConfigShared

struct StandbySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var standbyDraft: UInt16?
    @State private var standbyMessage: String?

    var body: some View {
        Section {
            CompatLabeledContent(NSLocalizedString("键盘当前待机时间", comment: "")) {
                Text(bleManager.configurationSnapshot.standbyMinutes.map { $0 == 0 ? NSLocalizedString("不自动待机", comment: "") : String(format: NSLocalizedString("%@ 分钟", comment: ""), String(describing: $0)) } ?? NSLocalizedString("未确认", comment: ""))
            }
            Picker(NSLocalizedString("待应用设置", comment: ""), selection: $standbyDraft) {
                Text(NSLocalizedString("请选择", comment: "")).tag(Optional<UInt16>.none)
                ForEach([UInt16(0), 30, 60, 120], id: \.self) { value in
                    Text(value == 0 ? NSLocalizedString("不自动待机", comment: "") : String(format: NSLocalizedString("%@ 分钟", comment: ""), String(describing: value))).tag(Optional(value))
                }
            }
            HStack {
                Button(bleManager.isReadingStandby ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取当前待机", comment: "")) {
                    standbyMessage = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.readStandbyForEditing()
                            if standbyDraft == nil { standbyDraft = actual }
                        } catch { standbyMessage = KeyboardSettingsFeedback.message(for: error) }
                    }
                }
                Button(bleManager.isSettingStandby ? NSLocalizedString("应用中…", comment: "") : NSLocalizedString("应用待机设置", comment: "")) {
                    guard let target = standbyDraft else { return }
                    standbyMessage = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.setStandbyConfirmed(target)
                            standbyMessage = actual == 0 ? NSLocalizedString("键盘已确认不自动待机。", comment: "") : String(format: NSLocalizedString("键盘已确认待机时间为 %@ 分钟。", comment: ""), String(describing: actual))
                        } catch { standbyMessage = String(format: NSLocalizedString("设置未确认：%@；待应用选项已保留。", comment: ""), String(describing: KeyboardSettingsFeedback.message(for: error))) }
                    }
                }
                .disabled(standbyDraft == nil || bleManager.configurationSnapshot.standbyMinutes == nil || bleManager.firmwareCapabilityProfile?.mayQueryStandby != true)
            }
            .disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
            if let standbyMessage { Text(standbyMessage).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("只修改待机时间，不覆盖键位、语音和显示配置。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text(NSLocalizedString("键盘待机设置", comment: "")) }
    }

}
