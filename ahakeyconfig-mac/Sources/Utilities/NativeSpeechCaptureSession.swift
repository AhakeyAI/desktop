import AVFoundation
import Foundation
import Speech

protocol NativeSpeechCapturing: AnyObject {
    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String
    func finish() async
    func cancel()
}

/// AVAudioEngine cold-start and teardown may block for Bluetooth microphones.
/// All audio objects belong to this queue, never the UI/event-delivery thread.
final class NativeSpeechCaptureSession: NativeSpeechCapturing, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.speech-audio", qos: .userInitiated)
    private let cancellationLock = NSLock()
    private var cancelled = false
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    enum StartError: LocalizedError {
        case recognizerUnavailable, microphoneUnavailable
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return NSLocalizedString("当前系统语言暂不支持苹果原生转写。", comment: "")
            case .microphoneUnavailable: return NSLocalizedString("当前麦克风不可用，请检查输入设备。", comment: "")
            }
        }
    }

    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    try self.checkCancellation()
                    guard let recognizer = Self.makeRecognizer() else { throw StartError.recognizerUnavailable }
                    try self.checkCancellation()
                    let request = SFSpeechAudioBufferRecognitionRequest()
                    request.shouldReportPartialResults = true
                    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
                    self.request = request
                    let engine = AVAudioEngine()
                    self.engine = engine
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else { throw StartError.microphoneUnavailable }
                    try self.checkCancellation()
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
                    self.tapInstalled = true
                    engine.prepare()
                    try self.checkCancellation()
                    try engine.start()
                    try self.checkCancellation()
                    self.task = recognizer.recognitionTask(with: request) { result, error in
                        onRecognition(.capture(result, error: error))
                    }
                    continuation.resume(returning: recognizer.locale.identifier)
                } catch {
                    self.cleanup()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                self.stopAudio()
                self.request?.endAudio()
                continuation.resume()
            }
        }
    }

    func cancel() {
        // Mark immediately, including while prepare() is blocked. The worker
        // checks before starting audio, so a cancelled startup cannot revive.
        cancellationLock.lock(); cancelled = true; cancellationLock.unlock()
        Self.queue.async { self.cleanup() }
    }

    private func checkCancellation() throws {
        cancellationLock.lock(); let cancelled = cancelled; cancellationLock.unlock()
        if cancelled { throw CancellationError() }
    }

    private func stopAudio() {
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func cleanup() {
        stopAudio()
        request?.endAudio(); task?.cancel()
        engine = nil; request = nil; task = nil
    }

    private static func makeRecognizer() -> SFSpeechRecognizer? {
        if let identifier = Locale.preferredLanguages.first,
           let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable {
            return recognizer
        }
        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable { return recognizer }
        return nil
    }
}
