import Foundation
#if canImport(SherpaOnnxC)
import SherpaOnnxC
#endif

/// sherpa-onnx 离线识别器的薄封装（SenseVoice / Whisper）。
/// 与 ahakey-studio-tauri/crates/speech/src/recognizer.rs 使用同一版本与同样的参数。
/// 线程安全：`transcribe` 内部加锁串行执行，可在任意后台线程调用。
final class LocalRecognizer: @unchecked Sendable {
    enum Model: Equatable {
        case senseVoice(model: URL, tokens: URL)
        case whisper(encoder: URL, decoder: URL, tokens: URL)
    }

    struct Configuration: Equatable {
        var model: Model
        /// "cpu"（默认）或 "coreml"
        var provider: String = "cpu"
        var threads: Int = LocalRecognizer.defaultThreadCount
    }

    enum RecognizerError: LocalizedError {
        case engineUnavailable
        case loadFailed

        var errorDescription: String? {
            switch self {
            case .engineUnavailable:
                return NSLocalizedString("本地识别引擎未编译进当前版本。", comment: "")
            case .loadFailed:
                return NSLocalizedString("本地识别模型加载失败。", comment: "")
            }
        }
    }

    static let sampleRate = 16_000

    static var defaultThreadCount: Int {
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    /// 当前构建是否链接了 sherpa-onnx（见 scripts/fetch-sherpa-onnx.sh）。
    static var isEngineAvailable: Bool {
        #if canImport(SherpaOnnxC)
        return true
        #else
        return false
        #endif
    }

    let configuration: Configuration
    private let lock = NSLock()

    #if canImport(SherpaOnnxC)
    private let recognizer: OpaquePointer

    init(configuration: Configuration) throws {
        self.configuration = configuration

        // C 字符串需在 Create 调用期间保持有效；sherpa-onnx 会自行拷贝配置。
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func c(_ s: String) -> UnsafePointer<CChar> {
            let p = strdup(s)!
            owned.append(p)
            return UnsafePointer(p)
        }

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = Int32(Self.sampleRate)
        config.feat_config.feature_dim = 80
        config.decoding_method = c("greedy_search")
        config.model_config.num_threads = Int32(max(1, min(8, configuration.threads)))
        config.model_config.provider = c(configuration.provider)
        config.model_config.debug = 0

        switch configuration.model {
        case let .senseVoice(model, tokens):
            config.model_config.sense_voice.model = c(model.path)
            config.model_config.sense_voice.language = c("auto")
            config.model_config.sense_voice.use_itn = 1
            config.model_config.tokens = c(tokens.path)
        case let .whisper(encoder, decoder, tokens):
            config.model_config.whisper.encoder = c(encoder.path)
            config.model_config.whisper.decoder = c(decoder.path)
            config.model_config.whisper.language = c("")  // 自动检测语言
            config.model_config.whisper.task = c("transcribe")
            config.model_config.tokens = c(tokens.path)
        }

        guard let handle = SherpaOnnxCreateOfflineRecognizer(&config) else {
            throw RecognizerError.loadFailed
        }
        recognizer = handle
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    /// 识别一段 16 kHz 单声道 Float32 音频（取值范围 -1...1）。
    func transcribe(_ samples: [Float]) -> String {
        guard !samples.isEmpty else { return "" }
        lock.lock()
        defer { lock.unlock() }

        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, Int32(Self.sampleRate), buffer.baseAddress, Int32(buffer.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #else
    init(configuration: Configuration) throws {
        self.configuration = configuration
        throw RecognizerError.engineUnavailable
    }

    func transcribe(_ samples: [Float]) -> String { "" }
    #endif
}
