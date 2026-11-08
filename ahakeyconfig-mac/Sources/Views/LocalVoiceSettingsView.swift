import AppKit
import SwiftUI

/// 语音设置：识别引擎（苹果原生 / SenseVoice / Whisper）+ 模型下载管理 + 文字整理方式（AhaType / 本地大模型 / 关闭）。
struct LocalVoiceSettingsView: View {
    @ObservedObject private var engine = LocalSpeechEngine.shared
    @ObservedObject private var store = LocalModelStore.shared
    @ObservedObject private var ahaType = AhaTypeTextOptimizer.shared

    @AppStorage(LocalLLMTextCleaner.Keys.baseURL) private var cleanupBaseURL = LocalLLMTextCleaner.Defaults.baseURL
    @AppStorage(LocalLLMTextCleaner.Keys.model) private var cleanupModel = LocalLLMTextCleaner.Defaults.model
    @AppStorage(LocalLLMTextCleaner.Keys.apiKey) private var cleanupAPIKey = LocalLLMTextCleaner.Defaults.apiKey

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(NSLocalizedString("识别引擎", comment: "")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $engine.engine) {
                        ForEach(LocalSpeechEngine.Engine.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if engine.engine == .whisper {
                        Picker(NSLocalizedString("Whisper 模型", comment: ""), selection: $engine.whisperSize) {
                            ForEach(LocalSpeechEngine.WhisperSize.allCases) { size in
                                Text("\(size.model.displayName) · \(Self.formatBytes(size.model.totalSize))").tag(size)
                            }
                        }
                    }

                    if let model = engine.selectedModel {
                        if LocalRecognizer.isEngineAvailable {
                            modelRow(model)
                            Toggle(NSLocalizedString("启动时自动下载所选模型", comment: ""), isOn: $engine.autoDownload)
                                .toggleStyle(.switch)
                                .font(.callout)
                            Text(NSLocalizedString("本地识别完全离线，只需麦克风权限。模型就绪前自动使用苹果原生转写。", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(NSLocalizedString("当前版本未包含本地识别引擎（构建前需运行 scripts/fetch-sherpa-onnx.sh），将使用苹果原生转写。", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if model.isWhisper {
                            Text(NSLocalizedString("Whisper 支持约 99 种语言，但无实时预览，松手后才开始识别。", comment: ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox(NSLocalizedString("文字整理", comment: "")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: Binding(
                        get: { ahaType.activeCleanupMode },
                        set: { ahaType.setCleanupMode($0) }
                    )) {
                        Text(NSLocalizedString("AhaType 云端", comment: "")).tag(LocalLLMTextCleaner.Mode.ahatype)
                        Text(NSLocalizedString("本地大模型", comment: "")).tag(LocalLLMTextCleaner.Mode.local)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(NSLocalizedString("是否整理由「触发方式」中的短按 / 长按开关决定。", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if ahaType.activeCleanupMode == .local {
                        TextField(NSLocalizedString("服务地址（OpenAI 兼容，如 Ollama）", comment: ""), text: $cleanupBaseURL)
                            .textFieldStyle(.roundedBorder)
                        TextField(NSLocalizedString("模型名称", comment: ""), text: $cleanupModel)
                            .textFieldStyle(.roundedBorder)
                        SecureField(NSLocalizedString("API Key（可选）", comment: ""), text: $cleanupAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Text(NSLocalizedString("例如安装 Ollama 后运行 `ollama pull qwen2.5:3b`。服务不可用或超时（30 秒）时直接写入原始文字。", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalSpeechModel) -> some View {
        let state = store.state(for: model)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.displayName) · \(Self.formatBytes(model.totalSize))")
                    .font(.callout)
                Text(statusText(state, model: model))
                    .font(.caption)
                    .foregroundStyle(isFailed(state) ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
            Spacer()
            switch state {
            case .downloading, .verifying:
                if case let .downloading(progress) = state {
                    ProgressView(value: progress).frame(width: 80)
                } else {
                    ProgressView().controlSize(.small)
                }
                Button(NSLocalizedString("取消", comment: "")) { store.cancel(model) }
                    .buttonStyle(.bordered)
            case .installed:
                Button(NSLocalizedString("删除", comment: "")) { engine.delete(model) }
                    .buttonStyle(.bordered)
            case .notInstalled, .failed:
                Button(NSLocalizedString("下载", comment: "")) { engine.download(model) }
                    .buttonStyle(.borderedProminent)
                Button(NSLocalizedString("从文件夹导入…", comment: "")) { importFromFolder(model) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func statusText(_ state: LocalModelState, model: LocalSpeechModel) -> String {
        switch state {
        case .notInstalled:
            return NSLocalizedString("未下载", comment: "")
        case let .downloading(progress):
            return String(format: NSLocalizedString("下载中 %d%%", comment: ""), Int(progress * 100))
        case .verifying:
            return NSLocalizedString("校验中…", comment: "")
        case .installed:
            if engine.loadedModel == model { return NSLocalizedString("已就绪", comment: "") }
            if let error = engine.loadError { return error }
            return NSLocalizedString("已下载，正在加载…", comment: "")
        case let .failed(message):
            return message
        }
    }

    private func isFailed(_ state: LocalModelState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func importFromFolder(_ model: LocalSpeechModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(format: NSLocalizedString("选择包含 %@ 模型文件的文件夹", comment: ""), model.displayName)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            try? await store.importFromFolder(model, from: url)
            engine.prepare()
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
