import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CursorHookHealthStoreTests: XCTestCase {
    func testRecordContainsOnlyBoundedHealthFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-health-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logURL = root.appendingPathComponent("cursor-hook-health.jsonl")
        let store = CursorHookHealthStore(fileURL: logURL)

        try store.record(
            eventCategory: .toolPermission,
            decision: .unavailable,
            latency: 0.25,
            failure: .timeout,
            hookVersion: "cursor-1.2.3",
            runtimeProtocolVersion: "1.1"
        )

        let line = try String(contentsOf: logURL, encoding: .utf8)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            [
                "eventCategory", "decision", "latencyBucket", "timeoutCount",
                "offlineCount", "hookVersion", "runtimeProtocolVersion",
            ]
        )
        XCTAssertEqual(object["eventCategory"] as? String, "tool_permission")
        XCTAssertEqual(object["decision"] as? String, "unavailable")
        XCTAssertEqual(object["latencyBucket"] as? String, "200_999ms")
        XCTAssertEqual(object["timeoutCount"] as? Int, 1)
        XCTAssertEqual(object["offlineCount"] as? Int, 0)
        XCTAssertEqual(object["runtimeProtocolVersion"] as? String, "1.1")
        XCTAssertFalse(line.contains("/Users/"))
        XCTAssertFalse(line.contains("command"))
        XCTAssertFalse(line.contains("prompt"))
        XCTAssertFalse(line.contains("cwd"))
        XCTAssertFalse(line.contains("environment"))
    }

    func testDefaultsEnforceFiveMegabytesAndThreeTotalFiles() {
        let store = CursorHookHealthStore(fileURL: URL(fileURLWithPath: "/tmp/health.jsonl"))

        XCTAssertEqual(store.maxFileSize, 5 * 1024 * 1024)
        XCTAssertEqual(store.maxArchiveCount, 2)
    }

    func testHealthLogRotationKeepsCurrentFileAndTwoArchives() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-health-rotation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logURL = root.appendingPathComponent("cursor-hook-health.jsonl")
        let store = CursorHookHealthStore(
            fileURL: logURL,
            maxFileSize: 220,
            maxArchiveCount: 2
        )

        for _ in 0..<8 {
            try store.record(
                eventCategory: .toolPermission,
                decision: .allow,
                latency: 0.01,
                failure: nil,
                hookVersion: "cursor-1.2.3",
                runtimeProtocolVersion: "1.1"
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.appendingPathExtension("1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.appendingPathExtension("2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.appendingPathExtension("3").path))
    }

    func testLatencyBucketsHaveBoundedCardinality() {
        XCTAssertEqual(CursorHookLatencyBucket.classify(seconds: 0.01), .under50ms)
        XCTAssertEqual(CursorHookLatencyBucket.classify(seconds: 0.05), .from50To199ms)
        XCTAssertEqual(CursorHookLatencyBucket.classify(seconds: 0.20), .from200To999ms)
        XCTAssertEqual(CursorHookLatencyBucket.classify(seconds: 1.00), .atLeast1000ms)
    }

    func testDetailedDiagnosticSessionAutomaticallyStopsAfter15Minutes() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var session = CursorHookDetailedDiagnosticSession()

        session.start(now: startedAt)
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.advance(to: startedAt.addingTimeInterval(15 * 60 - 1)))
        XCTAssertTrue(session.advance(to: startedAt.addingTimeInterval(15 * 60)))
        XCTAssertFalse(session.isActive)
    }
}
