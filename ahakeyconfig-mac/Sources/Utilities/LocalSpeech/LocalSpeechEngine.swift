import Foundation

/// 本地语音识别引擎的选择与生命周期：读取设置、按需自动下载模型、在后台加载识别器并常驻内存。
/// NativeSpeechTranscriptionService 只在 `isReady` 为 true 时走本地识别，否则继续使用苹果原生转写。
@MainActor
final class LocalSpeechEngine: ObservableObject {
    static let shared = LocalSpeechEngine()

    enum Engine: String, CaseIterable, Identifiable {
        case apple
        case senseVoice = "sensevoice"
        case whisper

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .apple: return NSLocalizedString("苹果原生转写", comment: "")
            case .senseVoice: return NSLocalizedString("SenseVoice（本地）", comment: "")
            case .whisper: return NSLocalizedString("Whisper（本地）", comment: "")
            }
        }
    }

    enum WhisperSize: String, CaseIterable, Identifiable {
        case tiny, base, small, turbo

        var id: String { rawValue }

        var model: LocalSpeechModel {
            switch self {
            case .tiny: return .whisperTiny
            case .base: return .whisperBase
            case .small: return .whisperSmall
            case .turbo: return .whisperTurbo
            }
        }
    }

    enum Keys {
        static let engine = "localVoice.engine"
        static let whisperSize = "localVoice.whisperSize"
        static let autoDownload = "localVoice.autoDownload"
    }

    /// 默认 SenseVoice；未编译本地引擎的构建默认苹果原生转写，避免界面显示一个用不了的选项。
    @Published var engine: Engine = Engine(rawValue: UserDefaults.standard.string(forKey: Keys.engine) ?? "")
        ?? (LocalRecognizer.isEngineAvailable ? .senseVoice : .apple) {
        didSet {
            UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine)
            prepare()
        }
    }

    @Published var whisperSize: WhisperSize = WhisperSize(rawValue: UserDefaults.standard.string(forKey: Keys.whisperSize) ?? "") ?? .base {
        didSet {
            UserDefaults.standard.set(whisperSize.rawValue, forKey: Keys.whisperSize)
            prepare()
        }
    }

    /// 关闭后不会在启动时自动下载模型（用户仍可在设置里手动下载）。
    @Published var autoDownload: Bool = UserDefaults.standard.object(forKey: Keys.autoDownload) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoDownload, forKey: Keys.autoDownload)
            if autoDownload { prepare() }
        }
    }

    /// 已加载、与当前所选模型一致的识别器。
    @Published private(set) var loadedModel: LocalSpeechModel?
    @Published private(set) var loadError: String?

    private var recognizer: LocalRecognizer?
    private var loadingModel: LocalSpeechModel?
    private let store = LocalModelStore.shared

    private init() { }

    /// 当前设置对应的本地模型；苹果原生转写时为 nil。
    var selectedModel: LocalSpeechModel? {
        switch engine {
        case .apple: return nil
        case .senseVoice: return .senseVoice
        case .whisper: return whisperSize.model
        }
    }

    /// 本地识别是否可以立即使用（模型已安装且识别器已加载）。
    var isReady: Bool {
        recognizer != nil && loadedModel != nil && loadedModel == selectedModel
    }

    /// 当前实际用于识别的引擎简短名称（用于 HUD 与状态提示，如 "SenseVoice"、"Whisper (base)"、"苹果原生转写"）。
    var activeHUDDisplayName: String {
        guard isReady, let model = loadedModel else {
            return NSLocalizedString("苹果原生转写", comment: "")
        }
        switch model {
        case .senseVoice:
            return "SenseVoice"
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperTurbo:
            return model.displayName
        #if DEBUG
        case .testFixture:
            return model.displayName
        #endif
        }
    }

    /// SenseVoice 解码足够快，可以录音中实时预览；Whisper 只在结束后识别。
    var supportsLivePreview: Bool { loadedModel == .senseVoice }

    /// 选择了本地引擎（且本构建包含引擎）——此时只需要麦克风权限。
    var usesLocalEngine: Bool { LocalRecognizer.isEngineAvailable && selectedModel != nil }

    /// 本地引擎尚未就绪时给用户的提示。
    var notReadyMessage: String {
        guard let model = selectedModel else { return "" }
        switch store.state(for: model) {
        case let .downloading(progress):
            return String(format: NSLocalizedString("本地语音模型下载中 %d%%，完成后即可使用。", comment: ""), Int(progress * 100))
        case .verifying:
            return NSLocalizedString("本地语音模型校验中，请稍候。", comment: "")
        case .installed:
            if let loadError { return loadError }
            return NSLocalizedString("本地语音模型加载中，请稍候。", comment: "")
        case .notInstalled, .failed:
            return NSLocalizedString("本地语音模型尚未下载，请在语音键设置中下载，或切换到苹果原生转写。", comment: "")
        }
    }

    /// 应用启动时调用；只做模型下载/加载，绝不启动录音。
    func start() {
        prepare()
    }

    /// 按当前设置准备识别器：已安装则后台加载；未安装且允许自动下载则后台下载后加载。
    func prepare() {
        guard LocalRecognizer.isEngineAvailable, let model = selectedModel else {
            unload()
            return
        }
        if loadedModel != model { unload() }
        if store.isInstalled(model) {
            load(model)
            return
        }
        guard autoDownload else { return }
        download(model)
    }

    /// 下载（如需要）并在成功后加载；设置界面的“下载”按钮也走这里。
    func download(_ model: LocalSpeechModel) {
        switch store.state(for: model) {
        case .downloading, .verifying: return
        default: break
        }
        Task { @MainActor in
            do {
                try await store.download(model)
                if model == self.selectedModel { self.load(model) }
            } catch {
                // 状态与错误信息由 LocalModelStore.states 展示；此时继续使用苹果原生转写。
                NSLog("[LocalSpeech] download \(model.id) failed: \(error.localizedDescription)")
            }
        }
    }

    /// 删除当前所选模型时切回苹果原生转写，否则自动下载会在下次启动时把刚删除的模型又下载回来。
    func delete(_ model: LocalSpeechModel) {
        if loadedModel == model || loadingModel == model { unload() }
        store.delete(model)
        if model == selectedModel { engine = .apple }
    }

    /// 在后台线程识别一段 16 kHz 单声道音频。
    func transcribe(_ samples: [Float]) async -> String {
        guard let recognizer else { return "" }
        return await Task.detached(priority: .userInitiated) {
            recognizer.transcribe(samples)
        }.value
    }

    private func load(_ model: LocalSpeechModel) {
        guard loadedModel != model, loadingModel != model else { return }
        let configuration: LocalRecognizer.Configuration
        if let paths = store.senseVoicePaths(for: model) {
            configuration = .init(model: .senseVoice(model: paths.model, tokens: paths.tokens))
        } else if let paths = store.whisperPaths(for: model) {
            configuration = .init(model: .whisper(encoder: paths.encoder, decoder: paths.decoder, tokens: paths.tokens))
        } else {
            return
        }

        loadingModel = model
        loadError = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                Result { try LocalRecognizer(configuration: configuration) }
            }.value
            guard self.loadingModel == model else { return }  // 加载期间设置已变更
            self.loadingModel = nil
            switch result {
            case let .success(recognizer):
                self.recognizer = recognizer
                self.loadedModel = model
                NSLog("[LocalSpeech] loaded \(model.id)")
            case let .failure(error):
                self.loadError = error.localizedDescription
                NSLog("[LocalSpeech] load \(model.id) failed: \(error.localizedDescription)")
            }
        }
    }

    private func unload() {
        recognizer = nil
        loadedModel = nil
        loadingModel = nil
    }
}
