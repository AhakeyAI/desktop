import Foundation
import Speech
import XCTest
@testable import AhaKeyConfig

private final class SuspendedSpeechCapture: NativeSpeechCapturing {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var cancellations = 0
    private var finishes = 0
    let entered: XCTestExpectation

    init(_ entered: XCTestExpectation) { self.entered = entered }
    func start(onRecognition: @escaping (SFSpeechRecognitionResult?, Error?) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
            entered.fulfill()
        }
    }
    func finish() async { recordFinish() }
    private func recordFinish() { lock.lock(); finishes += 1; lock.unlock() }
    func cancel() { lock.lock(); cancellations += 1; lock.unlock() }
    var finishCount: Int { lock.lock(); defer { lock.unlock() }; return finishes }
    var cancelCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    func complete() {
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(returning: "zh-CN")
    }
    func fail() {
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(throwing: NativeSpeechCaptureSession.StartError.microphoneUnavailable)
    }
}

@MainActor
final class NativeSpeechStartupTests: XCTestCase {
    private let policy = VoiceProcessingPolicy(shortPressAhaType: false, longPressAhaType: false, longPressThresholdMs: 200)
    private func shortPress(_ service: NativeSpeechTranscriptionService) {
        service.handleVoiceKeyDown(trigger: 79, policy: policy)
        service.handleVoiceKeyUp(trigger: 79)
    }

    func testColdStartupShowsFeedbackBeforeReadyAndRetryCancelsWithoutQueuedRecording() async {
        let entered = expectation(description: "cold capture suspended")
        let discarded = expectation(description: "obsolete start discarded")
        let capture = SuspendedSpeechCapture(entered)
        var hud: [VoiceStatusHUDState] = []
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { state, _ in hud.append(state) }, diagnosticSink: { if $0 == "discarded stale audio startup" { discarded.fulfill() } })
        shortPress(service)
        XCTAssertTrue(service.isStartingRecording)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(hud.last, .starting)
        await fulfillment(of: [entered], timeout: 1)
        shortPress(service)
        XCTAssertFalse(service.isStartingRecording)
        XCTAssertFalse(service.isRecording)
        XCTAssertGreaterThan(capture.cancelCount, 0)
        XCTAssertEqual(capture.finishCount, 0)
        capture.complete()
        await fulfillment(of: [discarded], timeout: 1)
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(hud.contains(.recording))
    }

    func testOldColdStartCannotReviveOrReplaceNextRecording() async {
        let oldEntered = expectation(description: "old start")
        let nextEntered = expectation(description: "next start")
        let discarded = expectation(description: "old discarded")
        let ready = expectation(description: "new recording ready")
        let old = SuspendedSpeechCapture(oldEntered), next = SuspendedSpeechCapture(nextEntered)
        var captures = [old, next]
        let service = NativeSpeechTranscriptionService(captureFactory: { captures.removeFirst() }, authorizationCheck: { true },
            hud: { state, _ in if state == .recording { ready.fulfill() } },
            diagnosticSink: { if $0 == "discarded stale audio startup" { discarded.fulfill() } })
        shortPress(service)
        await fulfillment(of: [oldEntered], timeout: 1)
        shortPress(service) // cancel the pending first gesture
        shortPress(service) // an explicit new recording
        await fulfillment(of: [nextEntered], timeout: 1)
        old.complete()
        await fulfillment(of: [discarded], timeout: 1)
        XCTAssertTrue(service.isStartingRecording)
        XCTAssertFalse(service.isRecording)
        next.complete()
        await fulfillment(of: [ready], timeout: 1)
        XCTAssertTrue(service.isRecording)
        XCTAssertFalse(service.isStartingRecording)
        service.stopRecording(bypassAhaType: true)
    }

    func testLongPressReleasedBeforeColdStartCancelsInsteadOfStartingAfterRelease() async {
        let entered = expectation(description: "long startup")
        let discarded = expectation(description: "released before ready")
        let capture = SuspendedSpeechCapture(entered)
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { _, _ in }, diagnosticSink: { if $0 == "discarded stale audio startup" { discarded.fulfill() } })
        service.handleVoiceKeyDown(trigger: 79, policy: policy)
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertTrue(service.isLongPressRecording)
        service.handleVoiceKeyUp(trigger: 79)
        XCTAssertFalse(service.isLongPressRecording)
        XCTAssertFalse(service.isStartingRecording)
        capture.complete()
        await fulfillment(of: [discarded], timeout: 1)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(capture.finishCount, 0)
    }

    func testCancelledNativeCaptureDoesNotInitializeMicrophone() async {
        let capture = NativeSpeechCaptureSession()
        capture.cancel()
        do {
            _ = try await capture.start { _, _ in XCTFail("cancelled before startup") }
            XCTFail("cancelled capture started")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStoppingListenerAlsoCancelsPendingShortPressStartup() async {
        let entered = expectation(description: "pending short capture")
        let discarded = expectation(description: "no revival after listener stop")
        let capture = SuspendedSpeechCapture(entered)
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { _, _ in }, diagnosticSink: { if $0 == "discarded stale audio startup" { discarded.fulfill() } })
        shortPress(service)
        await fulfillment(of: [entered], timeout: 1)
        service.cancelPendingVoiceKeyPress()
        XCTAssertFalse(service.isStartingRecording)
        capture.complete()
        await fulfillment(of: [discarded], timeout: 1)
        XCTAssertFalse(service.isRecording)
    }

    func testFailedStartupReleasesGestureAndAllowsExplicitRetry() async {
        let failedEntered = expectation(description: "unavailable device")
        let retryEntered = expectation(description: "retry device")
        let warning = expectation(description: "startup failure visible")
        let ready = expectation(description: "retry ready")
        let failed = SuspendedSpeechCapture(failedEntered), retry = SuspendedSpeechCapture(retryEntered)
        var captures = [failed, retry]
        let service = NativeSpeechTranscriptionService(captureFactory: { captures.removeFirst() }, authorizationCheck: { true },
            hud: { state, _ in
                if state.kind == .warning { warning.fulfill() }
                if state == .recording { ready.fulfill() }
            }, diagnosticSink: { _ in })
        shortPress(service)
        await fulfillment(of: [failedEntered], timeout: 1)
        failed.fail()
        await fulfillment(of: [warning], timeout: 1)
        XCTAssertFalse(service.isStartingRecording)
        XCTAssertFalse(service.isRecording)
        shortPress(service)
        await fulfillment(of: [retryEntered], timeout: 1)
        retry.complete()
        await fulfillment(of: [ready], timeout: 1)
        XCTAssertTrue(service.isRecording)
        service.stopRecording(bypassAhaType: true)
    }
}
