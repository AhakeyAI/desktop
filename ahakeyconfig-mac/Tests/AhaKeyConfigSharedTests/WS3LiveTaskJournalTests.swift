import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class WS3LiveTaskJournalTests: XCTestCase {
    func testDelayedDeliveryCannotRenewTemporarySingleState() throws {
        let metadata = try XCTUnwrap(WS3TaskMetadata(client: .codex, session: "reset", event: "CodexStop"))
        let event = WS3LiveTaskEvent(metadata: metadata, state: 5, uptime: 100, resetValue: 4, resetDelayMilliseconds: 1200)
        XCTAssertEqual(event.singleDisplay(at: 100.5)?.state, 5)
        XCTAssertEqual(try XCTUnwrap(event.singleDisplay(at: 100.5)).remaining, 0.7, accuracy: 0.001)
        XCTAssertEqual(event.singleDisplay(at: 102)?.state, 4)
        XCTAssertEqual(event.singleDisplay(at: 102)?.remaining, 0)
        XCTAssertNil(event.singleDisplay(at: 106))
    }
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func request(_ state: Int = 2) -> [String: Any] {
        ["cmd": "state", "value": state, "task": ["client": "codex", "session": "private-session-test", "event": "CodexPostToolUse"]]
    }
    func testOnlyLiveLeaseReceivesRealEventsWithoutRawSessionOrPrompt() throws {
        let dir = directory()
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 100))
        let lease = try WS3LiveTaskJournal.begin(directory: dir, now: 100)
        XCTAssertTrue(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 101))
        let batch = try XCTUnwrap(WS3LiveTaskJournal.read(lease, directory: dir))
        XCTAssertEqual(batch.sequence, 1); XCTAssertEqual(batch.events.count, 1)
        XCTAssertEqual(batch.events[0].reference.count, 64)
        let raw = try String(contentsOf: dir.appendingPathComponent("events.json"))
        XCTAssertFalse(raw.contains("private-session-test"))
        var registry = WS3TaskRegistry()
        XCTAssertTrue(registry.observe(batch.events[0], at: 102))
        XCTAssertEqual(registry.overview(connected: true, at: 102).tasks.count, 1)
        XCTAssertFalse(registry.observe(batch.events[0], at: 107))
        WS3LiveTaskJournal.end(lease, directory: dir)
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 103))
    }
    func testNewConnectionCannotReplayOrBeEndedByAnOldLease() throws {
        let dir = directory(), first = try WS3LiveTaskJournal.begin(directory: dir, now: 100)
        XCTAssertTrue(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 101))
        let second = try WS3LiveTaskJournal.begin(directory: dir, now: 102)
        XCTAssertNil(WS3LiveTaskJournal.read(first, directory: dir))
        WS3LiveTaskJournal.end(first, directory: dir)
        XCTAssertEqual(WS3LiveTaskJournal.read(second, directory: dir)?.events.count, 0)
        XCTAssertTrue(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 103))
    }
    func testBufferIsBoundedAndUnidentifiedOrInvalidEventsAreRejected() throws {
        let dir = directory(), lease = try WS3LiveTaskJournal.begin(directory: dir, now: 100)
        for _ in 0..<100 { XCTAssertTrue(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 101)) }
        let batch = try XCTUnwrap(WS3LiveTaskJournal.read(lease, directory: dir))
        XCTAssertEqual(batch.sequence, 100); XCTAssertEqual(batch.events.count, 64)
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: ["cmd": "state", "value": 2], directory: dir, now: 101))
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(255), directory: dir, now: 101))
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 99))
    }
    func testConcurrentPublisherNeverWaitsForReaderLock() throws {
        let dir = directory()
        let lease = try WS3LiveTaskJournal.begin(directory: dir, now: 100)
        let fd = open(dir.appendingPathComponent("journal.lock").path, O_RDWR)
        defer { flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 101))
        WS3LiveTaskJournal.end(lease, directory: dir)
        flock(fd, LOCK_UN)
        XCTAssertFalse(WS3LiveTaskJournal.publish(request: request(), directory: dir, now: 102))
    }
}
