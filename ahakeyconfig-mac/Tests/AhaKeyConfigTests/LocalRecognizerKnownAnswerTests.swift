import AVFoundation
import XCTest
@testable import AhaKeyConfig

/// 与 Tauri 客户端 crates/speech/tests/known_answer.rs 相同的门槛：
/// 官方 zh.wav 必须逐字识别为固定句子。它能发现模型/引擎/参数（采样率、ITN、语言）任何一处接错，
/// 这些错误不会导致崩溃，只会悄悄输出错字。
/// 需要环境变量 AHAKEY_TEST_MODEL_DIR（含 model.int8.onnx、tokens.txt）与 AHAKEY_TEST_ZH_WAV，未设置时跳过（会显示为 skipped）。
final class LocalRecognizerKnownAnswerTests: XCTestCase {
    func testSenseVoiceTranscribesOfficialChineseSampleExactly() throws {
        guard LocalRecognizer.isEngineAvailable else {
            throw XCTSkip("sherpa-onnx not vendored; run scripts/fetch-sherpa-onnx.sh")
        }
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["AHAKEY_TEST_MODEL_DIR"], let wav = env["AHAKEY_TEST_ZH_WAV"] else {
            throw XCTSkip("AHAKEY_TEST_MODEL_DIR / AHAKEY_TEST_ZH_WAV not set")
        }
        let modelDir = URL(fileURLWithPath: dir)
        let recognizer = try LocalRecognizer(configuration: .init(model: .senseVoice(
            model: modelDir.appendingPathComponent("model.int8.onnx"),
            tokens: modelDir.appendingPathComponent("tokens.txt")
        )))

        let samples = try Self.readMono16k(URL(fileURLWithPath: wav))
        let start = Date()
        let text = recognizer.transcribe(samples)
        let elapsed = Date().timeIntervalSince(start)
        print("[KnownAnswer] provider=cpu audio=\(Double(samples.count) / 16000)s decode=\(String(format: "%.3f", elapsed))s text=\(text)")

        XCTAssertEqual(text, "开饭时间早上9点至下午5点。")
    }

    /// Whisper 配置（encoder/decoder/tokens 文件名、自动语言、transcribe 任务）接错时 sherpa-onnx 往往
    /// 只返回空串或乱码而不报错，所以用官方英文样本检验能识别出关键词。
    /// 需要 AHAKEY_TEST_WHISPER_DIR（含 base-*.int8.onnx、base-tokens.txt）与 AHAKEY_TEST_EN_WAV。
    func testWhisperBaseTranscribesEnglishSample() throws {
        guard LocalRecognizer.isEngineAvailable else {
            throw XCTSkip("sherpa-onnx not vendored; run scripts/fetch-sherpa-onnx.sh")
        }
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["AHAKEY_TEST_WHISPER_DIR"], let wav = env["AHAKEY_TEST_EN_WAV"] else {
            throw XCTSkip("AHAKEY_TEST_WHISPER_DIR / AHAKEY_TEST_EN_WAV not set")
        }
        let paths = try XCTUnwrap(LocalSpeechModel.whisperBase.whisperPaths(in: URL(fileURLWithPath: dir)))
        let recognizer = try LocalRecognizer(configuration: .init(model: .whisper(
            encoder: paths.encoder, decoder: paths.decoder, tokens: paths.tokens
        )))
        let samples = try Self.readMono16k(URL(fileURLWithPath: wav))
        let start = Date()
        let text = recognizer.transcribe(samples)
        print("[KnownAnswer] whisper-base audio=\(Double(samples.count) / 16000)s decode=\(String(format: "%.3f", Date().timeIntervalSince(start)))s text=\(text)")
        XCTAssertTrue(text.lowercased().contains("tribal"), "unexpected whisper output: \(text)")
    }

    /// 真实麦克风多为 44.1/48 kHz、可能是双声道；录音器必须正确重采样到 16 kHz 单声道。
    /// 重采样出错（速率、声道、跨缓冲状态丢失）不会崩溃，只会悄悄降低识别率，所以用同一句已知答案检验整条链路。
    func testRecorderResamplingFromTypicalMicFormatsKeepsKnownAnswer() throws {
        guard LocalRecognizer.isEngineAvailable else {
            throw XCTSkip("sherpa-onnx not vendored; run scripts/fetch-sherpa-onnx.sh")
        }
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["AHAKEY_TEST_MODEL_DIR"], let wav = env["AHAKEY_TEST_ZH_WAV"] else {
            throw XCTSkip("AHAKEY_TEST_MODEL_DIR / AHAKEY_TEST_ZH_WAV not set")
        }
        let modelDir = URL(fileURLWithPath: dir)
        let recognizer = try LocalRecognizer(configuration: .init(model: .senseVoice(
            model: modelDir.appendingPathComponent("model.int8.onnx"),
            tokens: modelDir.appendingPathComponent("tokens.txt")
        )))
        let source = try Self.readMono16k(URL(fileURLWithPath: wav))

        for (rate, channels) in [(48_000.0, AVAudioChannelCount(1)), (44_100.0, AVAudioChannelCount(2))] {
            let micFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
            let micBuffers = try Self.upsample(source, to: micFormat, chunkFrames: 4096)

            let recorder = MicrophoneRecorder()
            try recorder.prepareConverter(from: micFormat)
            micBuffers.forEach(recorder.append)
            let samples = recorder.recordedSamples

            XCTAssertEqual(Double(samples.count), Double(source.count), accuracy: Double(source.count) * 0.02, "rate=\(rate)")
            XCTAssertEqual(recognizer.transcribe(samples), "开饭时间早上9点至下午5点。", "rate=\(rate) channels=\(channels)")
        }
    }

    /// 把 16 kHz 单声道样本转换成指定麦克风格式，并切成与 tap 回调相同大小的块。
    private static func upsample(_ samples: [Float], to format: AVAudioFormat, chunkFrames: AVAudioFrameCount) throws -> [AVAudioPCMBuffer] {
        let srcFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let converter = AVAudioConverter(from: srcFormat, to: format)!
        let outCapacity = AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16_000) + 1024
        let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity)!
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return src
        }
        if let error { throw error }

        var chunks: [AVAudioPCMBuffer] = []
        var offset: AVAudioFrameCount = 0
        while offset < out.frameLength {
            let n = min(chunkFrames, out.frameLength - offset)
            let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
            chunk.frameLength = n
            for ch in 0..<Int(format.channelCount) {
                chunk.floatChannelData![ch].update(from: out.floatChannelData![ch] + Int(offset), count: Int(n))
            }
            chunks.append(chunk)
            offset += n
        }
        return chunks
    }

    /// 读取 16 kHz 单声道 WAV 为 Float32；格式不符直接失败，避免测试在错误采样率下“碰巧”通过。
    static func readMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        XCTAssertEqual(format.sampleRate, 16000)
        XCTAssertEqual(format.channelCount, 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
