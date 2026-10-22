import SwiftUI
import AhaKeyConfigShared

struct WS3DisplaySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var initialResourceEntry: UInt8 = 0
    @State private var message: String?
    @State private var feedback = WS3DisplaySettingFeedback()
    @State private var operationTask: Task<Void, Never>?
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
        let generation = bleManager.configurationSnapshot.generation
        if let value = bleManager.ws3SingleLightSnapshot, value.mode == mode, value.state == state,
           value.generation == generation { return value }
        guard display != nil, let catalog = bleManager.ws3LightCatalogSnapshot,
              catalog.generation == generation else { return nil }
        return catalog.light(mode: mode, state: state)
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
                    perform(operation: { try await bleManager.readWS3DisplayForEditing() }) { actual in
                        if brightnessDraft == nil { brightnessDraft = actual.brightness }
                    }
                }.disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
                if let display {
                    Text(String(format: NSLocalizedString("键盘报告亮度：%@%%", comment: ""), String(display.brightness)))
                    Text(String(format: NSLocalizedString("键盘报告有效的自定义素材：%@ / 19", comment: ""), String(display.resources.filter(\.reportsValidUserResource).count)))
                }
                Text(NSLocalizedString("读取不会保存。预览和保存只在本次连接读回确认后开放。素材上传与恢复默认需分别确认，仅作用于所选位置。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                WS3ResourceUploadView(bleManager: bleManager, initialEntry: initialResourceEntry)
                Divider()
                Text(NSLocalizedString("全局灯光亮度", comment: "")).font(.headline)
                HStack {
                    Slider(value: Binding(get: { Double(pendingBrightness) }, set: { brightnessDraft = UInt8($0.rounded()) }), in: 1...100, step: 1)
                    Text("\(pendingBrightness)%").monospacedDigit().frame(width: 48)
                }.disabled(!ready)
                HStack {
                    Button(NSLocalizedString("预览亮度（10 秒）", comment: "")) {
                        preview(.brightness(pendingBrightness))
                    }
                    Button(NSLocalizedString("保存亮度并核对", comment: "")) {
                        guard let display else { return }
                        save(.brightness(pendingBrightness), baseline: display.brightness, generation: display.generation)
                    }
                }.disabled(!ready)
                Divider()
                WS3LightCatalogView(bleManager: bleManager)
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
                    let selectedMode = mode, selectedState = state
                    perform(operation: {
                        try await bleManager.readWS3SingleLightForEditing(mode: selectedMode, state: selectedState)
                    }) { actual in
                        guard mode == selectedMode, state == selectedState else { return }
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
                        preview(.light(effect: effect, brightness: pendingBrightness))
                    }.disabled(effectDraft == nil || effectDraft == 0 || !knownLight)
                    Button(NSLocalizedString("保存此灯效并核对", comment: "")) {
                        guard let light, let effect = effectDraft else { return }
                        save(.singleLight(mode: light.mode, state: light.state, effect: effect), baseline: light.effect, generation: light.generation)
                    }.disabled(effectDraft == nil || !knownLight)
                }.disabled(!ready)
                Text(NSLocalizedString("灯效保存只修改所选模式与状态，不会立即播放或切换工作模式。熄灭可以保存，不支持预览。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Button(NSLocalizedString("停止临时预览", comment: "")) {
                    preview(.stop)
                }.disabled(!ready)
                if let message { Text(message).font(.caption).textSelection(.enabled) }
                if feedback.unconfirmed[.brightness] != nil {
                    Text(NSLocalizedString("亮度保存尚未确认；已发出的更改可能生效。请重新读取，再明确保存核对。", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(AhaKeyModeSlot.allCases) { slot in
                    ForEach(IDEState.allCases) { item in
                        if feedback.unconfirmed[.singleLight(mode: UInt8(slot.rawValue), state: item.rawValue)] != nil {
                            Text(String(format: NSLocalizedString("%@ · %@：灯效保存尚未确认；请重新读取，再明确保存核对。", comment: ""), slot.name, item.label))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Text(NSLocalizedString("元数据不等于实际图像内容校验。保存失败或取消不代表回滚；重新连接后须重新读取。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString("旧版设备继续使用画布原有保存流程。", comment: ""))
            }.padding()
        }
        .onChange(of: mode) { _ in effectDraft = nil; message = nil }
        .onChange(of: state) { _ in effectDraft = nil; message = nil }
        .onChange(of: bleManager.configurationSnapshot.generation) { _ in
            if feedback.connectionChanged(to: bleManager.configurationSnapshot.generation) {
                operationTask?.cancel()
                operationTask = nil
                message = nil
            }
        }
        .onDisappear {
            feedback.invalidate()
            operationTask?.cancel()
            operationTask = nil
            message = nil
        }
    }

    private func preview(_ preview: WS3DisplayPreview) {
        perform(operation: { try await bleManager.previewWS3Display(preview) }) { _ in
            message = preview == .stop
                ? NSLocalizedString("停止预览请求已接受，未修改保存配置。", comment: "")
                : NSLocalizedString("临时预览请求已接受，未保存。固件预览时长约 10 秒，实际显示请在键盘上确认。", comment: "")
        }
    }

    private func save(_ target: WS3DisplaySetting, baseline: UInt8, generation: UInt64) {
        perform(save: target, generation: generation, operation: {
            try await bleManager.saveWS3DisplaySetting(target, baseline: baseline, expectedGeneration: generation)
        }) { _ in
            switch target {
            case .brightness:
                message = NSLocalizedString("亮度已保存并读回一致；断电保持性仍需验证。", comment: "")
            case .singleLight(let mode, let state, _):
                let name = AhaKeyModeSlot.allCases.first { UInt8($0.rawValue) == mode }?.name ?? String(mode)
                let label = IDEState.allCases.first { $0.rawValue == state }?.label ?? String(state)
                message = String(format: NSLocalizedString("%@ · %@：灯效已保存并读回一致；断电保持性仍需验证。", comment: ""), name, label)
            }
        }
    }

    private func perform<Result>(save: WS3DisplaySetting? = nil, generation: UInt64? = nil,
                                 operation: @escaping @MainActor () async throws -> Result,
                                 onSuccess: @escaping @MainActor (Result) -> Void) {
        let currentGeneration = bleManager.configurationSnapshot.generation
        guard generation == nil || generation == currentGeneration else { return }
        operationTask?.cancel()
        let ticket = feedback.begin(generation: currentGeneration, save: save)
        message = nil
        operationTask = Task { @MainActor in
            guard !Task.isCancelled,
                  feedback.start(ticket, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
            do {
                let result = try await operation()
                guard !Task.isCancelled,
                      feedback.succeed(ticket, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
                operationTask = nil
                onSuccess(result)
            } catch {
                let failure = error as? ConfirmedWS3DisplaySetting.Failure
                let mayHaveApplied = failure != .invalidValue && failure != .changedBaseline
                guard feedback.fail(ticket, currentGeneration: bleManager.configurationSnapshot.generation,
                                    mayHaveApplied: mayHaveApplied) else { return }
                operationTask = nil
                message = KeyboardSettingsFeedback.message(for: error)
            }
        }
    }
}
