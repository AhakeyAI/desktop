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
    /// 自动按自然语音停顿（静音间断）与模型窗口上限（20 秒）切分片段逐段解码，
    /// 使长语音断句与标点更自然，且避免超过 Whisper 30 秒 / SenseVoice 20 秒最佳窗口。
    func transcribe(_ samples: [Float]) -> String {
        let ranges = Self.segmentRanges(for: samples)
        guard !ranges.isEmpty else { return "" }

        var combined = ""
        for range in ranges {
            let chunk = Array(samples[range])
            let text = decodeSegment(chunk)
            if !text.isEmpty {
                combined = Self.joinSegmentText(combined, text)
            }
        }
        return combined
    }

    private func decodeSegment(_ samples: [Float]) -> String {
        guard samples.count >= Self.minSegmentSamples else { return "" }
        // 全静音或极微弱底噪直接跳过，避免 Whisper 产生幻觉文本
        var maxAbs: Float = 0
        for s in samples {
            if !s.isFinite { return "" }
            let a = abs(s)
            if a > maxAbs { maxAbs = a }
        }
        guard maxAbs >= 0.001 else { return "" }

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

    // MARK: - 静音感知的语音分段（Silence-Aware Utterance Segmentation）

    /// 最短有效语音片段（50 ms = 800 样本）。
    static let minSegmentSamples = sampleRate / 20
    /// 单段最大长度（20 秒 = 320,000 样本），保证在 SenseVoice / Whisper 最佳注意力窗口内。
    static let maxSegmentSamples = 20 * sampleRate
    /// 至少已积累 3.5 秒语音后，遇到 ≥ 0.6 秒的自然停顿且后续仍有语音才切分，避免把句尾静音单独切成一段。
    static let minUtteranceBeforePauseSplitSamples = (7 * sampleRate) / 2
    /// 切分点之后至少还需要保留的样本数（1.5 秒 = 24,000 样本）。
    static let minRemainingAfterPauseSplitSamples = (3 * sampleRate) / 2
    /// 判定为自然语句停顿的连续静音时长（600 ms = 6 个 100 ms 窗口）。
    static let pauseSilenceWindows = 6
    /// 能量检测窗口大小（100 ms = 1,600 样本）。
    static let energyWindowSamples = sampleRate / 10
    /// 静音能量阈值（均方能量 mean-square < 0.0004，与 Tauri crates/speech 一致）。
    static let silenceMeanSquareThreshold: Float = 0.0004

    /// 将完整音频按自然停顿（≥ 600 ms 静音）和最大窗口（20 秒）切分为若干半开区间 `Range<Int>`。
    /// 不丢弃任何非空样本。
    static func segmentRanges(for samples: [Float]) -> [Range<Int>] {
        guard !samples.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var offset = 0
        while offset < samples.count {
            let cut = nextBoundary(in: samples, from: offset)
            if cut > offset {
                ranges.append(offset..<cut)
            }
            offset = max(offset + 1, cut)
        }
        return ranges
    }

    /// 计算从 `start` 开始的下一处切分点（绝对下标）。
    private static func nextBoundary(in samples: [Float], from start: Int) -> Int {
        let remaining = samples.count - start
        if remaining <= minUtteranceBeforePauseSplitSamples + minRemainingAfterPauseSplitSamples {
            return samples.count
        }

        let hardCap = min(samples.count, start + maxSegmentSamples)
        let window = energyWindowSamples
        let pauseNeed = pauseSilenceWindows

        // 1. 在 [start + 3.5s, hardCap] 之间寻找 ≥ 600ms 的自然静音停顿，
        //    要求停顿前已有有声语音，且停顿后仍有有声语音（避免把录音末尾静音切成碎片）
        var seenActiveSpeech = false
        var quietRun = 0
        var cursor = start
        while cursor + window <= hardCap {
            let ms = meanSquare(samples, from: cursor, count: window)
            if ms >= silenceMeanSquareThreshold {
                seenActiveSpeech = true
                quietRun = 0
            } else if seenActiveSpeech {
                quietRun += 1
                if quietRun >= pauseNeed, (cursor + window - start) >= minUtteranceBeforePauseSplitSamples {
                    let silenceStart = cursor - (quietRun - 1) * window
                    let silenceEnd = cursor + window
                    let mid = (silenceStart + silenceEnd) / 2
                    if samples.count - mid >= minRemainingAfterPauseSplitSamples,
                       hasActiveSpeech(in: samples, from: silenceEnd, to: samples.count) {
                        return mid
                    }
                }
            }
            cursor += window
        }

        // 2. 若整段未超过 20 秒且没有明显长停顿，直接返回末尾
        if samples.count <= hardCap {
            return samples.count
        }

        // 3. 超过 20 秒仍无长停顿时，在最后 3 秒（[hardCap - 3s, hardCap]）内找最安静的 100ms 窗口切分
        let searchStart = max(start + window, hardCap - 3 * sampleRate)
        var bestCut = hardCap
        var minEnergy = Float.greatestFiniteMagnitude
        var pos = searchStart
        while pos + window <= hardCap {
            let ms = meanSquare(samples, from: pos, count: window)
            if ms <= minEnergy {
                minEnergy = ms
                bestCut = pos + window / 2
            }
            pos += window
        }
        if minEnergy < silenceMeanSquareThreshold {
            return bestCut
        }
        return hardCap
    }

    private static func hasActiveSpeech(in samples: [Float], from start: Int, to end: Int) -> Bool {
        let window = energyWindowSamples
        var pos = start
        while pos + window <= end {
            if meanSquare(samples, from: pos, count: window) >= silenceMeanSquareThreshold {
                return true
            }
            pos += window
        }
        return false
    }

    private static func meanSquare(_ samples: [Float], from start: Int, count: Int) -> Float {
        var sum: Float = 0
        let end = start + count
        var i = start
        while i < end {
            let s = samples[i]
            sum += s * s
            i += 1
        }
        return sum / Float(count)
    }

    /// 拼接相邻两段识别结果：
    /// - 若两段之间都是中文/日文/韩文且前一段末尾没有标点，自动补全中文逗号 `，` 以体现语音停顿；
    /// - 若两段交界为英文/数字，自动补空格。
    static func joinSegmentText(_ prior: String, _ next: String) -> String {
        let a = prior.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        guard let lastChar = a.last, let firstChar = b.first else {
            return a + b
        }
        if isASCIIAlphanumeric(lastChar) && isASCIIAlphanumeric(firstChar) {
            return a + " " + b
        }
        if !isTrailingPunctuation(lastChar) && (isCJK(lastChar) || isCJK(firstChar)) {
            return a + "，" + b
        }
        return a + b
    }

    private static func isASCIIAlphanumeric(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        return CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
    }

    private static func isTrailingPunctuation(_ ch: Character) -> Bool {
        let punct: Set<Character> = [
            "，", "。", "！", "？", "；", "：", "、", "…",
            ",", ".", "!", "?", ";", ":", "-", "—"
        ]
        return punct.contains(ch)
    }

    private static func isCJK(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                return true
            }
        }
        return false
    }
}
