import Foundation
import Speech
import XCTest
@testable import AhaKeyConfig

private final class SuspendedSpeechCapture: NativeSpeechCapturing {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var cancellations = 0
    private var finishes = 0
    private var recognition: ((NativeSpeechRecognitionUpdate) -> Void)?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    var requiresConfirmedEnd = false
    var finalizationTimeout: TimeInterval = 1
    var finishEntered: XCTestExpectation?
    let entered: XCTestExpectation

    init(_ entered: XCTestExpectation) { self.entered = entered }
    func start(onRecognition: @escaping (NativeSpeechRecognitionUpdate) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock(); self.continuation = continuation; recognition = onRecognition; lock.unlock()
            entered.fulfill()
        }
    }
    func finish() async {
        recordFinish()
        if let finishEntered {
            await withCheckedContinuation { continuation in
                lock.lock(); finishContinuation = continuation; lock.unlock()
                finishEntered.fulfill()
            }
        }
    }
    func completeFinish() {
        lock.lock(); let continuation = finishContinuation; finishContinuation = nil; lock.unlock()
        continuation?.resume()
    }
    func emit(_ text: String, isFinal: Bool = false, requiresReview: Bool = false, completion: SpeechTranscriptAccumulator.Completion? = nil,
              audioObservation: NativeSpeechRecognitionUpdate.AudioObservation? = nil) {
        lock.lock(); let recognition = recognition; lock.unlock()
        recognition?(.init(text: text, isFinal: isFinal, completion: completion, requiresReview: requiresReview,
                           audioObservation: audioObservation))
    }
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

    func testBoundaryDiagnosticsPreserveReviewProtectionWithoutLoggingUtterances() async {
        let entered = expectation(description: "capture entered")
        let ready = expectation(description: "capture ready")
        let prefix = expectation(description: "committed prefix received")
        let tail = expectation(description: "unconfirmed tail received")
        let review = expectation(description: "text retained")
        let capture = SuspendedSpeechCapture(entered)
        capture.requiresConfirmedEnd = true
        var diagnostics: [String] = [], injected: [String] = []
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { state, _ in if state == .recording { ready.fulfill() } }, diagnosticSink: { message in
                diagnostics.append(message)
                if message.hasPrefix("partial result=private-prefix ") { prefix.fulfill() }
                if message.hasPrefix("partial result=private-tail ") { tail.fulfill() }
                if message.hasPrefix("finalize retained for review") { review.fulfill() }
            }, textInjector: { injected.append($0); return true })
        shortPress(service); await fulfillment(of: [entered], timeout: 1)
        capture.complete(); await fulfillment(of: [ready], timeout: 1)
        capture.emit("private-prefix", completion: .init(audio: .init(start: 0, duration: 1)!),
                     audioObservation: .init(isFinal: true, start: 0, duration: 1))
        await fulfillment(of: [prefix], timeout: 1)
        capture.emit("private-tail", audioObservation: .init(isFinal: false, start: 2, duration: 1))
        await fulfillment(of: [tail], timeout: 1)
        shortPress(service); capture.emit("", isFinal: true)
        await fulfillment(of: [review], timeout: 1)
        let metadata = diagnostics.filter { $0.hasPrefix("speech boundary ") || $0.hasPrefix("finalize boundary ") }
        XCTAssertEqual(metadata.count, 3)
        XCTAssertTrue(metadata.contains { $0.contains("sourceFinal=true") && $0.contains("completionValid=true") })
        XCTAssertTrue(metadata.contains { $0.contains("sourceFinal=false") && $0.contains("completionValid=false") })
        XCTAssertTrue(metadata.contains { $0.contains("committed=[0.0..1.0]") && $0.contains("pendingChars=12") })
        XCTAssertFalse(metadata.joined().contains("private-prefix"))
        XCTAssertFalse(metadata.joined().contains("private-tail"))
        XCTAssertTrue(injected.isEmpty)
        XCTAssertEqual(service.deferredTranscripts.first?.previousText, "private-prefix")
        XCTAssertEqual(service.deferredTranscripts.first?.text, "private-tail")
    }

    func testSegmentCommitDoesNotPasteBeforeWholeRecordingEnds() async {
        let entered = expectation(description: "capture entered")
        let ready = expectation(description: "ready")
        let prefix = expectation(description: "prefix")
        let suffix = expectation(description: "suffix")
        let pasted = expectation(description: "single paste")
        let capture = SuspendedSpeechCapture(entered)
        var injected: [String] = []
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { state, _ in if state == .recording { ready.fulfill() } }, diagnosticSink: { message in
                if message.hasPrefix("partial result=前句 ") { prefix.fulfill() }
                if message.hasPrefix("partial result=后句 ") { suffix.fulfill() }
            }, textInjector: { injected.append($0); pasted.fulfill(); return true })
        shortPress(service); await fulfillment(of: [entered], timeout: 1)
        capture.complete(); await fulfillment(of: [ready], timeout: 1)
        capture.emit("前句", completion: .init(audio: .init(start: 0, duration: 1)!))
        await fulfillment(of: [prefix], timeout: 1)
        XCTAssertTrue(service.isRecording); XCTAssertTrue(injected.isEmpty)
        capture.emit("后句", completion: .init(audio: .init(start: 3, duration: 1)!))
        await fulfillment(of: [suffix], timeout: 1)
        XCTAssertTrue(injected.isEmpty)
        shortPress(service)
        capture.emit("", isFinal: true)
        await fulfillment(of: [pasted], timeout: 1)
        XCTAssertEqual(injected.count, 1)
        XCTAssertTrue(injected[0].contains("前句")); XCTAssertTrue(injected[0].contains("后句"))
    }

    func testUnconfirmedModernEndRetainsTextInsteadOfPasting() async {
        let entered = expectation(description: "capture entered")
        let ready = expectation(description: "ready")
        let preview = expectation(description: "preview")
        let review = expectation(description: "review")
        let capture = SuspendedSpeechCapture(entered)
        capture.requiresConfirmedEnd = true; capture.finalizationTimeout = 0.01
        var injected: [String] = []
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { state, _ in if state == .recording { ready.fulfill() } }, diagnosticSink: { message in
                if message.hasPrefix("partial result=尚未完整 ") { preview.fulfill() }
                if message.hasPrefix("finalize retained for review") { review.fulfill() }
            }, textInjector: { injected.append($0); return true })
        shortPress(service); await fulfillment(of: [entered], timeout: 1)
        capture.complete(); await fulfillment(of: [ready], timeout: 1)
        capture.emit("尚未完整"); await fulfillment(of: [preview], timeout: 1)
        shortPress(service); await fulfillment(of: [review], timeout: 1)
        XCTAssertTrue(injected.isEmpty)
        XCTAssertEqual(service.deferredTranscripts.first?.text, "尚未完整")
        XCTAssertEqual(service.deferredTranscripts.first?.requiresReview, true)
    }

    func testPartialTranscriptStreamsToHUDWithoutPastingUntilStop() async {
        let entered = expectation(description: "capture entered")
        let ready = expectation(description: "recording ready")
        let preview = expectation(description: "partial visible in capsule")
        let pasted = expectation(description: "final pasted once")
        let capture = SuspendedSpeechCapture(entered)
        var injected: [String] = []
        var states: [VoiceStatusHUDState] = []
        let service = NativeSpeechTranscriptionService(captureFactory: { capture }, authorizationCheck: { true },
            hud: { state, _ in
                states.append(state)
                if state == .recording { ready.fulfill() }
                if state.kind == .recording && state.transcript == "first phrase" { preview.fulfill() }
            }, diagnosticSink: { _ in }, textInjector: { text in
                injected.append(text); pasted.fulfill(); return true
            })
        shortPress(service)
        await fulfillment(of: [entered], timeout: 1)
        capture.complete()
        await fulfillment(of: [ready], timeout: 1)
        capture.emit("first phrase")
        await fulfillment(of: [preview], timeout: 1)
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(service.transcriptPreview, "first phrase")
        XCTAssertTrue(injected.isEmpty, "Interim recognition must never write into the target input")
        shortPress(service)
        XCTAssertEqual(states.last?.kind, .processing)
        XCTAssertEqual(states.last?.transcript, "first phrase")
        capture.emit("first phrase complete", isFinal: true)
        await fulfillment(of: [pasted], timeout: 2)
        XCTAssertEqual(injected, ["first phrase complete"])
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
            _ = try await capture.start { _ in XCTFail("cancelled before startup") }
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

    func testFinishingRecordingKeepsItsFinalTextWhenNextRecordingStarts() async {
        let oldEntered = expectation(description: "first recording")
        let nextEntered = expectation(description: "next recording")
        let firstReady = expectation(description: "first ready"), nextReady = expectation(description: "next ready")
        let partial = expectation(description: "first partial processed")
        let newPartial = expectation(description: "new partial processed")
        let finishEntered = expectation(description: "old teardown suspended")
        let retained = expectation(description: "old full result preserved")
        let old = SuspendedSpeechCapture(oldEntered), next = SuspendedSpeechCapture(nextEntered)
        old.finishEntered = finishEntered
        var captures = [old, next], readyCount = 0
        let service = NativeSpeechTranscriptionService(captureFactory: { captures.removeFirst() }, authorizationCheck: { true },
            hud: { state, _ in
                if state == .recording { readyCount += 1; (readyCount == 1 ? firstReady : nextReady).fulfill() }
            }, diagnosticSink: { message in
                if message.hasPrefix("partial result=first partial ") { partial.fulfill() }
                if message.hasPrefix("partial result=next speech ") { newPartial.fulfill() }
                if message == "late completion retained for explicit copy" { retained.fulfill() }
            }, textInjector: { _ in false })
        shortPress(service)
        await fulfillment(of: [oldEntered], timeout: 1)
        old.complete()
        await fulfillment(of: [firstReady], timeout: 1)
        old.emit("first partial")
        await fulfillment(of: [partial], timeout: 1)
        service.stopRecording(bypassAhaType: true)
        await fulfillment(of: [finishEntered], timeout: 1)
        shortPress(service)
        await fulfillment(of: [nextEntered], timeout: 1)
        next.complete()
        await fulfillment(of: [nextReady], timeout: 1)
        next.emit("next speech")
        await fulfillment(of: [newPartial], timeout: 1)
        old.emit("first complete sentence", isFinal: true)
        await fulfillment(of: [retained], timeout: 1)
        XCTAssertEqual(service.deferredTranscripts.map(\.text), ["first complete sentence"])
        XCTAssertEqual(service.transcriptPreview, "next speech")
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(service.lastCommittedText, "")
        old.completeFinish()
        service.stopRecording(bypassAhaType: true)
    }
}
