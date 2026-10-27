import XCTest
@testable import AhaKeyConfigShared

final class KimiDesktopLeverStateTests: XCTestCase {
    private func withState(_ body: (KimiDesktopLeverState, URL, KimiDesktopLeverState.Target) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try KimiDesktopLeverState.Target(home: "/tmp/kimi-test-home", sessionID: "session-A")
        try body(.init(directory: root), root, target)
    }
    func testNoConsentCannotCreatePermissionLease() throws {
        try withState { state, _, target in
            XCTAssertThrowsError(try state.prepare(target, baseline: .yolo, intended: .auto))
            XCTAssertTrue(try state.snapshot().leases.isEmpty)
        }
    }
    func testRepeatedLeverChangesKeepOriginalModeAndRevocationKeepsRecovery() throws {
        try withState { state, _, target in
            try state.authorize(target, title: "A")
            let first = try state.prepare(target, baseline: .yolo, intended: .auto)
            XCTAssertTrue(try state.acknowledge(first))
            let second = try state.prepare(target, baseline: .auto, intended: .manual)
            XCTAssertEqual(second.baseline, .yolo)
            try state.revoke(target)
            XCTAssertTrue(try state.snapshot().grants.isEmpty)
            XCTAssertEqual(try state.snapshot().leases, [second])
            XCTAssertTrue(try state.hasPendingRecovery())
        }
    }
    func testLostReplyRetainsAllPossibleOwnedModesUntilAck() throws {
        try withState { state, _, target in
            try state.authorize(target, title: "A")
            _ = try state.prepare(target, baseline: .yolo, intended: .auto)
            let next = try state.prepare(target, baseline: .yolo, intended: .manual)
            XCTAssertEqual(Set(next.possibleOwnedModes), [.auto, .manual])
            XCTAssertFalse(try state.removeAfterExternalChange(next, observed: .auto))
            XCTAssertTrue(try state.acknowledge(next))
            let acknowledged = try XCTUnwrap(state.snapshot().leases.first)
            XCTAssertEqual(acknowledged.possibleOwnedModes, [.manual])
            XCTAssertTrue(try state.removeAfterExternalChange(acknowledged, observed: .auto))
        }
    }
    func testOlderCompletionCannotClearNewOperation() throws {
        try withState { state, _, target in
            try state.authorize(target, title: "A")
            let first = try state.prepare(target, baseline: .yolo, intended: .auto)
            let second = try state.prepare(target, baseline: .auto, intended: .manual)
            XCTAssertFalse(try state.acknowledge(first))
            XCTAssertFalse(try state.removeAfterVerifiedRestore(first))
            XCTAssertEqual(try state.snapshot().leases, [second])
        }
    }
    func testSameIDInAnotherHomeIsNotAuthorized() throws {
        try withState { state, _, target in
            try state.authorize(target, title: "A")
            let other = try KimiDesktopLeverState.Target(home: "/tmp/another-home", sessionID: target.sessionID)
            XCTAssertThrowsError(try state.prepare(other, baseline: .manual, intended: .auto))
            XCTAssertEqual(try state.snapshot().grants.map(\.target), [target])
        }
    }
    func testRestartKeepsOriginalBaselineWithoutRunningAnything() throws {
        try withState { state, root, target in
            try state.authorize(target, title: "A")
            let lease = try state.prepare(target, baseline: .auto, intended: .manual)
            let reopened = KimiDesktopLeverState(directory: root)
            XCTAssertEqual(try reopened.snapshot().leases, [lease])
            let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("kimi-desktop-lever-v1.json").path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(mode?.intValue, 0o600)
        }
    }
    func testMalformedJournalCannotBecomeEmptyRecovery() throws {
        try withState { state, root, target in
            try state.authorize(target, title: "A")
            let file = root.appendingPathComponent("kimi-desktop-lever-v1.json")
            try Data("corrupt".utf8).write(to: file)
            XCTAssertThrowsError(try state.hasPendingRecovery())
            XCTAssertThrowsError(try state.snapshot())
        }
    }
}
