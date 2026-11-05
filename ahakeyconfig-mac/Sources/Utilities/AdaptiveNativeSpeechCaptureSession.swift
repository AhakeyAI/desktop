import AVFoundation
import Foundation
import Speech

/// Backend choice is made once, before opening the microphone. Missing models
/// preserve the existing recognizer; recording never triggers an asset download.
final class AdaptiveNativeSpeechCaptureSession: NativeSpeechCapturing, @unchecked Sendable {
    private let gate = NSLock()
    private var cancelled = false
    private var capture: NativeSpeechCapturing?
    private let selectBackend: () async -> NativeSpeechCapturing
    init(selectBackend: @escaping () async -> NativeSpeechCapturing = AdaptiveNativeSpeechCaptureSession.makeBackend) {
        self.selectBackend = selectBackend
    }
    static func makeBackend() async -> NativeSpeechCapturing {
        if #available(macOS 26.0, *), let locale = await SpeechAnalyzerCaptureSession.installedLocale() {
            return SpeechAnalyzerCaptureSession(locale: locale)
        }
        return NativeSpeechCaptureSession()
    }
    var finalizationTimeout: TimeInterval { selected()?.finalizationTimeout ?? 1 }
    var requiresConfirmedEnd: Bool { selected()?.requiresConfirmedEnd ?? false }
    private func selected() -> NativeSpeechCapturing? { gate.lock(); defer { gate.unlock() }; return capture }
    private func install(_ value: NativeSpeechCapturing) throws {
        gate.lock(); defer { gate.unlock() }
        guard !cancelled else { throw CancellationError() }
        capture = value
    }
    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String {
        let value = await selectBackend()
        try install(value)
        return try await value.start(onRecognition: onRecognition)
    }
    func finish() async { await selected()?.finish() }
    func cancel() {
        gate.lock(); cancelled = true; let value = capture; gate.unlock()
        value?.cancel()
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerCaptureSession: NativeSpeechCapturing, @unchecked Sendable {
    private let worker: Worker
    private let cancellation = CancellationGate()
    let finalizationTimeout: TimeInterval = 5
    let requiresConfirmedEnd = true
    init(locale: Locale) { worker = Worker(locale: locale) }
    static func installedLocale() async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        let requested = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(supported) ? supported : nil
    }
    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String {
        try await worker.start(cancellation: cancellation, onRecognition: onRecognition)
    }
    func finish() async { await worker.finish() }
    func cancel() {
        cancellation.cancel()
        Task { await worker.cancel() }
    }

    private final class CancellationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        func check() throws {
            lock.lock(); let value = cancelled; lock.unlock()
            if value { throw CancellationError() }
        }
    }

    /// Own a copy: the engine reuses its tap buffers after the callback returns.
    private final class AudioChunk: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init?(_ source: AVAudioPCMBuffer) {
            guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
            copy.frameLength = source.frameLength
            let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
            let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            guard src.count == dst.count else { return nil }
            for index in src.indices {
                guard src[index].mDataByteSize <= dst[index].mDataByteSize,
                      let from = src[index].mData, let to = dst[index].mData else { return nil }
                memcpy(to, from, Int(src[index].mDataByteSize))
            }
            buffer = copy
        }
    }

    private actor Worker {
        let locale: Locale
        var engine: AVAudioEngine?
        var tapped = false
        var analyzer: SpeechAnalyzer?
        var input: AsyncThrowingStream<AudioChunk, Error>.Continuation?
        var analysis: Task<Void, Error>?
        var reader: Task<Void, Never>?
        var finishing: Task<Void, Never>?
        var cancelled = false
        var callback: ((NativeSpeechRecognitionUpdate) -> Void)?
        init(locale: Locale) { self.locale = locale }

        func start(cancellation: CancellationGate, onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String {
            try cancellation.check()
            callback = onRecognition
            let module = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults], attributeOptions: [.audioTimeRange])
            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer
            do {
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                    throw CaptureError.audioFormat
                }
                try cancellation.check()
                try await analyzer.prepareToAnalyze(in: format)
                try cancellation.check()
                guard !cancelled else { throw CancellationError() }
                let engine = AVAudioEngine()
                self.engine = engine
                let source = engine.inputNode.outputFormat(forBus: 0)
                guard source.sampleRate > 0, source.channelCount > 0,
                      let converter = AVAudioConverter(from: source, to: format) else { throw CaptureError.audioFormat }
                let chunks = AsyncThrowingStream<AudioChunk, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
                input = chunks.continuation
                reader = Task { [weak self] in
                    do {
                        for try await result in module.results {
                            let span = SpeechTranscriptAccumulator.AudioSpan(start: result.range.start.seconds, duration: result.range.duration.seconds)
                            // Final here commits a segment, never the entire recording.
                            let completion = result.isFinal ? span.map { SpeechTranscriptAccumulator.Completion(audio: $0) } : nil
                            await self?.deliver(.init(text: String(result.text.characters), isFinal: false, completion: completion))
                        }
                    } catch { await self?.failed(error) }
                }
                let converted = ConvertedAudio(chunks: chunks.stream, converter: converter, format: format)
                analysis = Task { [weak self] in
                    do { try await analyzer.start(inputSequence: converted) }
                    catch { await self?.failed(error); throw error }
                }
                engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer, _ in
                    guard let chunk = AudioChunk(buffer) else {
                        chunks.continuation.finish(throwing: CaptureError.audioFormat); return
                    }
                    if case .dropped = chunks.continuation.yield(chunk) {
                        chunks.continuation.finish(throwing: CaptureError.backlog)
                    }
                }
                tapped = true
                engine.prepare()
                try cancellation.check()
                try engine.start()
                try cancellation.check()
                return locale.identifier
            } catch {
                await cancel()
                throw error
            }
        }
        func deliver(_ update: NativeSpeechRecognitionUpdate) { if !cancelled { callback?(update) } }
        func failed(_ error: Error) {
            guard !cancelled else { return }
            callback?(.init(text: nil, isFinal: false, requiresReview: true, errorDescription: error.localizedDescription))
        }
        func stopAudio() {
            engine?.stop()
            if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
            engine = nil
        }
        func finish() {
            guard finishing == nil, !cancelled, let analyzer else { return }
            stopAudio()
            input?.finish(); input = nil
            let analysis = analysis, reader = reader
            finishing = Task { [weak self] in
                do {
                    try await analysis?.value
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await reader?.value
                    await self?.deliver(.init(text: "", isFinal: true))
                } catch { await self?.failed(error) }
            }
        }
        func cancel() async {
            cancelled = true
            stopAudio()
            input?.finish(); input = nil
            analysis?.cancel(); reader?.cancel(); finishing?.cancel()
            callback = nil
            await analyzer?.cancelAndFinishNow()
            analyzer = nil
        }
    }
    private struct ConvertedAudio: AsyncSequence {
        typealias Element = AnalyzerInput
        let chunks: AsyncThrowingStream<AudioChunk, Error>
        let converter: AVAudioConverter
        let format: AVAudioFormat
        func makeAsyncIterator() -> Iterator { .init(chunks: chunks.makeAsyncIterator(), converter: converter, format: format) }
        struct Iterator: AsyncIteratorProtocol {
            var chunks: AsyncThrowingStream<AudioChunk, Error>.Iterator
            let converter: AVAudioConverter
            let format: AVAudioFormat
            var ended = false
            mutating func next() async throws -> AnalyzerInput? {
                guard !ended else { return nil }
                while let chunk = try await chunks.next() {
                    if let buffer = try PCMConversion.convert(chunk.buffer, using: converter, to: format) {
                        return AnalyzerInput(buffer: buffer)
                    }
                }
                // Flush resampler delay after the final tap buffer.
                if let tail = try PCMConversion.convert(nil, using: converter, to: format) {
                    return AnalyzerInput(buffer: tail)
                }
                ended = true
                return nil
            }
        }
    }
    private enum CaptureError: LocalizedError {
        case audioFormat, backlog
        var errorDescription: String? { NSLocalizedString("音频处理未能完整完成，请重试。", comment: "") }
    }
}

/// Conversion happens on the analyzer consumer, not the audio tap or UI actor.
@available(macOS 26.0, *)
enum PCMConversion {
    static func convert(_ input: AVAudioPCMBuffer?, using converter: AVAudioConverter, to format: AVAudioFormat) throws -> AVAudioPCMBuffer? {
        let capacity = input.map { AVAudioFrameCount(ceil(Double($0.frameLength) * format.sampleRate / $0.format.sampleRate) + 64) } ?? 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw ConversionError.failed }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard let input else { state.pointee = .endOfStream; return nil }
            if consumed { state.pointee = .noDataNow; return nil }
            consumed = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil else { throw error ?? ConversionError.failed }
        return output.frameLength > 0 ? output : nil
    }
    enum ConversionError: Error { case failed }
}
