import SwiftUI
import AhaKeyConfigShared

struct StandbySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var standbyDraft: UInt16?
    @State private var standbyMessage: String?

    var body: some View {
        Section {
            CompatLabeledContent("键盘当前待机时间") {
                Text(bleManager.configurationSnapshot.standbyMinutes.map { $0 == 0 ? "不自动待机" : "\($0) 分钟" } ?? "未确认")
            }
            Picker("待应用设置", selection: $standbyDraft) {
                Text("请选择").tag(Optional<UInt16>.none)
                ForEach([UInt16(0), 30, 60, 120], id: \.self) { value in
                    Text(value == 0 ? "不自动待机" : "\(value) 分钟").tag(Optional(value))
                }
            }
            HStack {
                Button(bleManager.isReadingStandby ? "读取中…" : "读取当前待机") {
                    standbyMessage = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.readStandbyForEditing()
                            if standbyDraft == nil { standbyDraft = actual }
                        } catch { standbyMessage = error.localizedDescription }
                    }
                }
                Button(bleManager.isSettingStandby ? "应用中…" : "应用待机设置") {
                    guard let target = standbyDraft else { return }
                    standbyMessage = nil
                    Task { @MainActor in
                        do {
                            let actual = try await bleManager.setStandbyConfirmed(target)
                            standbyMessage = actual == 0 ? "键盘已确认不自动待机。" : "键盘已确认待机时间为 \(actual) 分钟。"
                        } catch { standbyMessage = "设置未确认：\(error.localizedDescription)；待应用选项已保留。" }
                    }
                }
                .disabled(standbyDraft == nil || bleManager.configurationSnapshot.standbyMinutes == nil || bleManager.firmwareCapabilityProfile?.mayQueryStandby != true)
            }
            .disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
            if let standbyMessage { Text(standbyMessage).font(.caption).textSelection(.enabled) }
            Text("只修改待机时间，不覆盖键位、语音和显示配置。")
                .font(.caption).foregroundStyle(.secondary)
        } header: { Text("键盘待机设置") }
    }

}
