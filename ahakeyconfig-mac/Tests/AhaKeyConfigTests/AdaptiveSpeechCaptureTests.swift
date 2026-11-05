import AVFoundation
import XCTest
@testable import AhaKeyConfig

private final class BackendSpy: NativeSpeechCapturing {
    var starts = 0, finishes = 0, cancellations = 0
    let finalizationTimeout: TimeInterval = 5
    let requiresConfirmedEnd = true
    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String { starts += 1; return "zh_CN" }
    func finish() async { finishes += 1 }
    func cancel() { cancellations += 1 }
}

final class AdaptiveSpeechCaptureTests: XCTestCase {
    func testCancelledBeforeBackendSelectionNeverStartsMicrophone() async {
        let spy = BackendSpy()
        let session = AdaptiveNativeSpeechCaptureSession(selectBackend: { spy })
        session.cancel()
        do { _ = try await session.start { _ in }; XCTFail("Cancelled startup must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(spy.starts, 0)
    }
    func testBackendRemainsPinnedThroughFinishAndCancel() async throws {
        let spy = BackendSpy()
        let session = AdaptiveNativeSpeechCaptureSession(selectBackend: { spy })
        let locale = try await session.start { _ in }
        XCTAssertEqual(locale, "zh_CN")
        XCTAssertEqual(session.finalizationTimeout, 5)
        XCTAssertTrue(session.requiresConfirmedEnd)
        await session.finish(); session.cancel()
        XCTAssertEqual(spy.starts, 1); XCTAssertEqual(spy.finishes, 1); XCTAssertEqual(spy.cancellations, 1)
    }
    func testMicrophoneFloat48kConvertsAndFlushesToModelPCM() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("New backend requires macOS26") }
        let source = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = try XCTUnwrap(AVAudioConverter(from: source, to: target))
        var count = 0
        for _ in 0..<48 {
            let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1000))
            chunk.frameLength = 1000
            chunk.floatChannelData![0].initialize(repeating: 0.1, count: 1000)
            if let result = try PCMConversion.convert(chunk, using: converter, to: target) {
                XCTAssertEqual(result.format, target)
                count += Int(result.frameLength)
            }
        }
        for _ in 0..<4 {
            guard let result = try PCMConversion.convert(nil, using: converter, to: target) else { break }
            count += Int(result.frameLength)
        }
        XCTAssertEqual(count, 16_000, accuracy: 2)
    }
}
