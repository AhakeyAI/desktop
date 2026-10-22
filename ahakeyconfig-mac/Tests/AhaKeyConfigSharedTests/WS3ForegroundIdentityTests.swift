import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class WS3ForegroundIdentityTests: XCTestCase {
    private let terminal = WS3TerminalTaskIdentity(device: 123, processGroup: 100, leaderStartedSeconds: 100, leaderStartedMicroseconds: 0)!
    private func task(_ id: String, terminal: WS3TerminalTaskIdentity? = nil) -> WS3TaskMetadata {
        WS3TaskMetadata(client: .codex, session: id, event: "CodexPostToolUse", terminal: terminal)!
    }
    func testOnlyAnExactUniqueSessionGetsForegroundAndNoFocusCreatesTasks() {
        var registry = WS3TaskRegistry()
        XCTAssertTrue(registry.setForegroundTerminal(terminal))
        XCTAssertTrue(registry.overview(connected: true, at: 0).tasks.isEmpty)
        registry.observe(task("one", terminal: terminal), state: 2, at: 0)
        registry.observe(task("unknown"), state: 2, at: 0)
        XCTAssertEqual(registry.snapshot(at: 0).slots.compactMap { $0 }.filter(\.foreground).count, 1)
        registry.observe(task("ambiguous", terminal: terminal), state: 2, at: 1)
        XCTAssertFalse(registry.snapshot(at: 1).slots.compactMap { $0 }.contains(where: \.foreground))
        registry.observe(task("ambiguous", terminal: terminal), state: 8, at: 2)
        XCTAssertEqual(registry.overview(connected: true, at: 2).tasks.filter { $0.foreground == true }.count, 1)
    }
    func testForegroundCannotRenewTaskLifetimeOrSurviveDisconnect() {
        var registry = WS3TaskRegistry()
        registry.observe(task("one", terminal: terminal), state: 2, at: 0)
        registry.setForegroundTerminal(terminal)
        XCTAssertFalse(registry.setForegroundTerminal(terminal))
        XCTAssertTrue(registry.snapshot(at: 301).slots.allSatisfy { $0 == nil })
        registry.observe(task("fresh", terminal: terminal), state: 2, at: 302)
        _ = registry.overview(connected: false, at: 303)
        registry.observe(task("new", terminal: terminal), state: 2, at: 304)
        XCTAssertFalse(registry.snapshot(at: 304).slots.compactMap { $0 }.contains(where: \.foreground))
    }
    func testReusedProcessGroupBirthAndMissingProvenanceDoNotMatch() {
        var registry = WS3TaskRegistry()
        let reused = WS3TerminalTaskIdentity(device: 123, processGroup: 100, leaderStartedSeconds: 200, leaderStartedMicroseconds: 0)!
        registry.observe(task("one", terminal: terminal), state: 2, at: 0)
        registry.setForegroundTerminal(reused)
        XCTAssertFalse(registry.snapshot(at: 0).slots.compactMap { $0 }.contains(where: \.foreground))
        registry.setForegroundTerminal(terminal)
        registry.observe(task("one"), state: 2, at: 1)
        XCTAssertFalse(registry.snapshot(at: 1).slots.compactMap { $0 }.contains(where: \.foreground))
    }
    func testIdentityCodecPreservesNativeFieldsAndRejectsUnrelatedPaths() {
        XCTAssertEqual(WS3TerminalTaskIdentity(dictionary: terminal.dictionary), terminal)
        XCTAssertNil(WS3TerminalTaskIdentity(device: UInt32.max, processGroup: 1, leaderStartedSeconds: 0, leaderStartedMicroseconds: 0))
        XCTAssertNil(WS3TerminalTaskIdentity.captureTTY("/etc/passwd"))
        XCTAssertNil(WS3TerminalTaskIdentity.captureTTY("/dev/ttys/../passwd"))
        XCTAssertNil(WS3TerminalTaskIdentity.captureTTY("/dev/ttys000;open"))
        XCTAssertThrowsError(try JSONDecoder().decode(WS3TerminalTaskIdentity.self,
            from: Data("{\"device\":123,\"processGroup\":-1,\"leaderStartedSeconds\":100,\"leaderStartedMicroseconds\":0}".utf8)))
    }
}
