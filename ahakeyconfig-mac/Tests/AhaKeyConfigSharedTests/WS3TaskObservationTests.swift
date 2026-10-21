import XCTest
@testable import AhaKeyConfigShared

final class WS3TaskObservationTests: XCTestCase {
    private func metadata(_ session: String, client: WS3TaskClient = .codex, event: String = "CodexPreToolUse") -> WS3TaskMetadata {
        WS3TaskMetadata(client: client, session: session, event: event)!
    }

    func testMetadataRequiresRealBoundedSessionAndDoesNotTransportToolInput() throws {
        let base: [String: Any] = ["cmd": "permission", "value": 1, "delayMs": 12000]
        let raw = Data(#"{"session_id":"real-session","cwd":"/private/project","command":"secret"}"#.utf8)
        let enriched = WS3TaskMetadata.enrich(base, client: .codex, event: "PermissionRequest", stdin: raw)
        XCTAssertEqual(enriched["cmd"] as? String, "permission")
        XCTAssertEqual(enriched["delayMs"] as? Int, 12000)
        let task = try XCTUnwrap(enriched["task"] as? [String: String])
        XCTAssertEqual(Set(task.keys), ["client", "session", "event"])
        XCTAssertEqual(task["session"], "real-session")
        for raw in [#"{}"#, #"{"cwd":"project"}"#, #"{"session_id":123}"#, #"{"session_id":""}"#] {
            XCTAssertNil(WS3TaskMetadata.enrich(base, client: .claude, event: "Stop", stdin: Data(raw.utf8))["task"])
        }
        XCTAssertNil(WS3TaskMetadata(client: .codex, session: String(repeating: "a", count: 257), event: "Stop"))
        XCTAssertNil(WS3TaskMetadata(client: .codex, session: "bad\nidentifier", event: "Stop"))
        XCTAssertNotNil(WS3TaskMetadata.enrich(base, client: .cursor, event: "stop",
            stdin: Data(#"{"conversation_id":"cursor-session"}"#.utf8))["task"])
        XCTAssertNil(WS3TaskMetadata.enrich(base, client: .claude, event: "SubagentStop", stdin: raw)["task"])
        let oversized = Data(("{\"session_id\":\"real\",\"tool_result\":\"" + String(repeating: "x", count: 65_536) + "\"}").utf8)
        XCTAssertNil(WS3TaskMetadata.enrich(base, client: .codex, event: "Stop", stdin: oversized)["task"])
    }

    func testRoutingKeepsKnownClientFamiliesAndRejectsUnknownEvents() {
        XCTAssertEqual(WS3TaskMetadata.client(for: "Stop"), .claude)
        XCTAssertEqual(WS3TaskMetadata.client(for: "stop"), .cursor)
        XCTAssertEqual(WS3TaskMetadata.client(for: "KimiStop"), .kimi)
        XCTAssertNil(WS3TaskMetadata.client(for: "arbitrary"))
    }

    func testSourceAndSessionSeparateTasksAndUpdateStableSlots() {
        var registry = WS3TaskRegistry()
        registry.observe(metadata("same", client: .claude), state: 3, at: 1)
        registry.observe(metadata("same"), state: 1, at: 2)
        registry.observe(metadata("same", client: .claude), state: 2, at: 3)
        let report = registry.overview(connected: true, at: 3)
        XCTAssertEqual(report.tasks.map(\.slot), [0, 1])
        XCTAssertEqual(report.tasks.map(\.state), [.running, .waiting])
        XCTAssertNotEqual(report.tasks[0].reference, report.tasks[1].reference)
        XCTAssertFalse(report.tasks.contains { $0.reference.contains("same") })
    }

    func testLifecycleDoesNotInventTasksForIdleOrEndAndDoesNotGuessForeground() {
        var registry = WS3TaskRegistry()
        registry.observe(metadata("idle"), state: 4, at: 0)
        registry.observe(metadata("gone"), state: 8, at: 0)
        XCTAssertTrue(registry.overview(connected: true, at: 0).tasks.isEmpty)
        registry.observe(metadata("a"), state: 7, at: 1)
        registry.observe(metadata("a"), state: 2, at: 2)
        XCTAssertEqual(registry.snapshot(at: 2).slots[0], WS3TaskSlot(state: .running))
        registry.observe(metadata("a"), state: 5, at: 3)
        XCTAssertEqual(registry.snapshot(at: 3).slots[0]?.state, .done)
        registry.observe(metadata("a"), state: 8, at: 4)
        XCTAssertTrue(registry.overview(connected: true, at: 4).tasks.isEmpty)
        registry.observe(metadata("b", client: .claude, event: "PreCompact"), state: 0, at: 5)
        XCTAssertEqual(registry.snapshot(at: 5).slots[0]?.state, .running)
    }

    func testCapacityNeverEvictsActiveTasksAndReportsUnrepresentedEvents() {
        var registry = WS3TaskRegistry()
        for i in 0..<4 { registry.observe(metadata("s\(i)"), state: 3, at: 1) }
        let before = registry.overview(connected: true, at: 1)
        registry.observe(metadata("overflow"), state: 3, at: 2)
        XCTAssertEqual(registry.overview(connected: true, at: 2).tasks, before.tasks)
        XCTAssertEqual(registry.overview(connected: true, at: 2).unrepresentedEvents, 1)
        registry.observe(metadata("s1"), state: 5, at: 3)
        registry.observe(metadata("new"), state: 3, at: 4)
        XCTAssertEqual(registry.overview(connected: true, at: 4).tasks.count, 4)
        XCTAssertEqual(registry.snapshot(at: 4).slots[1]?.state, .running)
    }

    func testExpiryAndDisconnectClearAllFactsWithoutReplay() {
        var registry = WS3TaskRegistry()
        registry.observe(metadata("a"), state: 3, at: 1)
        XCTAssertEqual(registry.overview(connected: true, at: 300).tasks.count, 1)
        XCTAssertTrue(registry.overview(connected: true, at: 301).tasks.isEmpty)
        registry.observe(metadata("b"), state: 3, at: 302)
        XCTAssertTrue(registry.overview(connected: false, at: 302).tasks.isEmpty)
        XCTAssertTrue(registry.overview(connected: true, at: 303).tasks.isEmpty)
        XCTAssertEqual(registry.snapshot(at: 303).slots, [nil, nil, nil, nil])
    }

    func testReportCodecRejectsOversizedDuplicateOrOfflineTaskLists() throws {
        var registry = WS3TaskRegistry()
        registry.observe(metadata("a"), state: 3, at: 0)
        let report = registry.overview(connected: true, at: 0)
        XCTAssertEqual(WS3TaskOverview.decode(try JSONEncoder().encode(report)), report)
        let bad = WS3TaskOverview(connected: true, tasks: report.tasks + report.tasks, unrepresentedEvents: 0)
        XCTAssertNil(WS3TaskOverview.decode(try JSONEncoder().encode(bad)))
        XCTAssertNil(WS3TaskOverview.decode(try JSONEncoder().encode(WS3TaskOverview(connected: false, tasks: report.tasks, unrepresentedEvents: 0))))
        XCTAssertNil(WS3TaskOverview.decode(Data(#"{"error":"unknown cmd"}"#.utf8)))
    }
}
