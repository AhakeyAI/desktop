import XCTest
@testable import AhaKeyConfig

@MainActor
final class VoiceTranscriptCompletionTests: XCTestCase {
    func testDelayedCloudResultIsRetainedInsteadOfDeliveredToNewRecording() async throws {
        var current = UUID()
        let ticket = current
        let started = expectation(description: "optimizer suspended")
        var finish: CheckedContinuation<String, Never>?
        let completion = Task {
            await VoiceTranscriptCompletion.run(text: "original", ticket: ticket,
                currentTicket: { current }, process: { _ in
                    await withCheckedContinuation { continuation in
                        finish = continuation
                        started.fulfill()
                    }
                })
        }
        await fulfillment(of: [started], timeout: 1)
        current = UUID()
        try XCTUnwrap(finish).resume(returning: "processed")
        let result = await completion.value
        XCTAssertEqual(result, .deferred("processed"))
    }

    func testAlreadyStaleCompletionDoesNotStartCloudProcessing() async {
        let result = await VoiceTranscriptCompletion.run(text: "original", ticket: UUID(),
            currentTicket: { UUID() }, process: { _ in
                XCTFail("old completion must not start a cloud request")
                return "processed"
            })
        XCTAssertEqual(result, .deferred("original"))
    }

    func testCurrentCompletionDeliversItsProcessedText() async {
        let ticket = UUID()
        let result = await VoiceTranscriptCompletion.run(text: "original", ticket: ticket,
            currentTicket: { ticket }, process: { _ in "processed" })
        XCTAssertEqual(result, .ready("processed"))
    }
}
