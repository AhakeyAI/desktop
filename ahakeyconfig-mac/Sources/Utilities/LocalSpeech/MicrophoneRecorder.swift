import AVFoundation
import Foundation

/// 本地识别用的录音器：AVAudioEngine 采集 → 16 kHz 单声道 Float32，最长 120 秒。
/// 样本在音频线程追加，通过锁保护；`snapshot`/`stop` 可在任意线程调用。
final class MicrophoneRecorder {
    static let maxDurationSeconds = 120

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(LocalRecognizer.sampleRate),
        channels: 1,
        interleaved: false
    )!
    private var maxSamples: Int { Self.maxDurationSeconds * LocalRecognizer.sampleRate }

    /// 达到最长录音时长时回调一次（任意线程）。
    var onReachedMaxDuration: (() -> Void)?
    private var reportedMax = false

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        try prepareConverter(from: inputFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// 停止采集并返回全部样本。
    func stop() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        return recordedSamples
    }

    /// 为给定输入格式准备重采样器并清空缓冲（start 内部调用；测试可直接调用以绕过麦克风）。
    func prepareConverter(from inputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "MicrophoneRecorder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported input format \(inputFormat)",
            ])
        }
        self.converter = converter
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        reportedMax = false
        lock.unlock()
    }

    var recordedSamples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// 返回最近 `seconds` 秒的样本（用于 SenseVoice 实时预览）。
    func snapshot(lastSeconds seconds: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let count = seconds * LocalRecognizer.sampleRate
        return samples.count > count ? Array(samples.suffix(count)) : samples
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }

        var hitMax = false
        lock.lock()
        let room = maxSamples - samples.count
        if room > 0 {
            let n = min(room, Int(out.frameLength))
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: n))
        }
        if samples.count >= maxSamples, !reportedMax {
            reportedMax = true
            hitMax = true
        }
        lock.unlock()
        if hitMax { onReachedMaxDuration?() }
    }
}
