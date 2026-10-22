import Foundation
import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioLiveTaskSourceTests: XCTestCase {
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private var request: [String: Any] {
        ["cmd": "state", "value": 2, "task": ["client": "codex", "session": "source-test", "event": "CodexPostToolUse"]]
    }
    func testCoalescedEventsAreConsumedOnceAndNewLeaseStartsEmpty() throws {
        let dir = directory(), source = StudioLiveTaskSource(directory: dir)
        var events = 0
        try source.start(consume: { items, gap in events += items.count; XCTAssertFalse(gap) }, fault: { XCTFail() })
        XCTAssertTrue(WS3LiveTaskJournal.publish(request: request, directory: dir))
        XCTAssertTrue(source.refresh()); XCTAssertEqual(events, 1)
        XCTAssertTrue(source.refresh()); XCTAssertEqual(events, 1)
        source.stop()
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request, directory: dir))
        try source.start(consume: { items, _ in events += items.count }, fault: { XCTFail() })
        XCTAssertTrue(source.refresh()); XCTAssertEqual(events, 1)
        source.stop()
    }
    func testContinuousProducerDoesNotPostponeDeliveryUntilItStops() async throws {
        let dir = directory(), source = StudioLiveTaskSource(directory: dir)
        let first = expectation(description: "live event delivered while producer is still active")
        var received = false
        try source.start(consume: { items, _ in
            if !items.isEmpty && !received { received = true; first.fulfill() }
        }, fault: { XCTFail() })
        let request = self.request
        let producer = Task.detached {
            for _ in 0..<200 {
                if Task.isCancelled { return }
                _ = WS3LiveTaskJournal.publish(request: request, directory: dir)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        await fulfillment(of: [first], timeout: 1.5)
        producer.cancel(); await producer.value
        source.stop()
    }
    func testOverflowIsReportedRatherThanMergingIntoOldFacts() throws {
        let dir = directory(), source = StudioLiveTaskSource(directory: dir)
        var seenGap = false, count = 0
        try source.start(consume: { items, gap in seenGap = gap; count = items.count }, fault: { XCTFail() })
        for _ in 0..<70 { XCTAssertTrue(WS3LiveTaskJournal.publish(request: request, directory: dir)) }
        XCTAssertTrue(source.refresh()); XCTAssertTrue(seenGap); XCTAssertEqual(count, 64)
        source.stop()
    }
}
