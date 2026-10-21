import SwiftUI
import AhaKeyConfigShared

struct WS3DisplaySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var message: String?
    @State private var brightnessDraft: UInt8?
    @State private var mode: UInt8 = 0
    @State private var state: UInt8 = 0
    @State private var effectDraft: UInt8?

    private var display: WS3DisplaySnapshot? {
        guard let value = bleManager.ws3DisplaySnapshot,
              value.generation == bleManager.configurationSnapshot.generation else { return nil }
        return value
    }
    private var light: WS3SingleLightSnapshot? {
        guard let value = bleManager.ws3SingleLightSnapshot, value.mode == mode, value.state == state,
              value.generation == bleManager.configurationSnapshot.generation else { return nil }
        return value
    }
    private var ready: Bool { bleManager.canEditWS3Display && !bleManager.isConfigurationOperationInProgress }
    private var pendingBrightness: UInt8 { brightnessDraft ?? display?.brightness ?? 50 }
    private var knownLight: Bool { light.map { $0.effect <= 16 } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("显示与灯光", comment: "")).font(.headline)
                WS3TaskOverviewView()
                Divider()
                Button(bleManager.isReadingWS3Display ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取显示信息（只读）", comment: "")) {
                    perform {
                        let actual = try await bleManager.readWS3DisplayForEditing()
                        if brightnessDraft == nil { brightnessDraft = actual.brightness }
                    }
                }.disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
                if let display {
                    Text(String(format: NSLocalizedString("键盘报告亮度：%@%%", comment: ""), String(display.brightness)))
                    Text(String(format: NSLocalizedString("键盘报告有效的自定义素材：%@ / 19", comment: ""), String(display.resources.filter(\.reportsValidUserResource).count)))
                }
                Text(NSLocalizedString("读取不会保存。预览和保存只在本次连接读回确认后开放。素材上传、清空和恢复仍未开放。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(NSLocalizedString("全局灯光亮度", comment: "")).font(.headline)
                HStack {
                    Slider(value: Binding(get: { Double(pendingBrightness) }, set: { brightnessDraft = UInt8($0.rounded()) }), in: 1...100, step: 1)
                    Text("\(pendingBrightness)%").monospacedDigit().frame(width: 48)
                }.disabled(!ready)
                HStack {
                    Button(NSLocalizedString("预览亮度（10 秒）", comment: "")) {
                        perform {
                            try await bleManager.previewWS3Display(.brightness(pendingBrightness))
                            message = NSLocalizedString("预览请求已接受，未保存；键盘将在约 10 秒后结束预览，实际显示请在键盘上确认。", comment: "")
                        }
                    }
                    Button(NSLocalizedString("保存亮度并核对", comment: "")) {
                        guard let display else { return }
                        perform {
                            try await bleManager.saveWS3DisplaySetting(.brightness(pendingBrightness), baseline: display.brightness, expectedGeneration: display.generation)
                            message = NSLocalizedString("此项已保存并读回一致；断电保持性仍需验证。", comment: "")
                        }
                    }
                }.disabled(!ready)
                Divider()
                Text(NSLocalizedString("单任务模式灯效", comment: "")).font(.headline)
                HStack {
                    Picker(NSLocalizedString("模式", comment: ""), selection: $mode) {
                        ForEach(AhaKeyModeSlot.allCases) { Text($0.name).tag(UInt8($0.rawValue)) }
                    }
                    Picker(NSLocalizedString("工作状态", comment: ""), selection: $state) {
                        ForEach(IDEState.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Text(String(format: NSLocalizedString("键盘当前灯效：%@", comment: ""), light.map { LightEffectStyle(firmwareIndex: $0.effect)?.title ?? String(format: NSLocalizedString("未知灯效 %@（只读）", comment: ""), String($0.effect)) } ?? NSLocalizedString("未确认", comment: "")))
                Button(NSLocalizedString("读取此模式状态灯效", comment: "")) {
                    perform {
                        let actual = try await bleManager.readWS3SingleLightForEditing(mode: mode, state: state)
                        if effectDraft == nil, actual.effect <= 16 { effectDraft = actual.effect }
                    }
                }.disabled(!ready)
                Picker(NSLocalizedString("待保存灯效", comment: ""), selection: $effectDraft) {
                    Text(NSLocalizedString("请选择", comment: "")).tag(Optional<UInt8>.none)
                    ForEach(LightEffectStyle.allCases) { Text($0.title).tag(Optional($0.firmwareIndex)) }
                }.disabled(!ready || !knownLight)
                HStack {
                    Button(NSLocalizedString("预览灯效（10 秒）", comment: "")) {
                        guard let effect = effectDraft else { return }
                        perform {
                            try await bleManager.previewWS3Display(.light(effect: effect, brightness: pendingBrightness))
                            message = NSLocalizedString("预览请求已接受，未保存；键盘将在约 10 秒后结束预览，实际显示请在键盘上确认。", comment: "")
                        }
                    }.disabled(effectDraft == nil || effectDraft == 0 || !knownLight)
                    Button(NSLocalizedString("保存此灯效并核对", comment: "")) {
                        guard let light, let effect = effectDraft else { return }
                        perform {
                            try await bleManager.saveWS3DisplaySetting(.singleLight(mode: mode, state: state, effect: effect), baseline: light.effect, expectedGeneration: light.generation)
                            message = NSLocalizedString("此项已保存并读回一致；断电保持性仍需验证。", comment: "")
                        }
                    }.disabled(effectDraft == nil || !knownLight)
                }.disabled(!ready)
                Text(NSLocalizedString("灯效保存只修改所选模式与状态，不会立即播放或切换工作模式。熄灭可以保存，不支持预览。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Button(NSLocalizedString("停止临时预览", comment: "")) {
                    perform {
                        try await bleManager.previewWS3Display(.stop)
                        message = NSLocalizedString("停止预览请求已接受，未修改保存配置。", comment: "")
                    }
                }.disabled(!ready)
                if let message { Text(message).font(.caption).textSelection(.enabled) }
                Text(NSLocalizedString("元数据不等于实际图像内容校验。保存失败或取消不代表回滚；重新连接后须重新读取。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString("旧版设备继续使用画布原有保存流程。", comment: ""))
            }.padding()
        }
        .onChange(of: mode) { _ in effectDraft = nil; message = nil }
        .onChange(of: state) { _ in effectDraft = nil; message = nil }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        message = nil
        Task { @MainActor in
            do { try await operation() }
            catch { message = KeyboardSettingsFeedback.message(for: error) }
        }
    }
}
