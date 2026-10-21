import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

@MainActor
final class AgentPresentationSessionTests: XCTestCase {
    private final class Fixture {
        var requests: [Data] = []
        var clock: TimeInterval = 0
        var defaults = 0
        var faults = 0
        var intercept: ((Data) async throws -> Data?)?
        var didFault: (() -> Void)?
        func response(_ request: Data) -> Data {
            let b = [UInt8](request)
            if b[2] == 0x9F { return Data([0xAA, 0xBB, 0x9F, 0] + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD]) }
            if b[2] == 0x88 {
                if b[3] == 0 { return Data([0xAA, 0xBB, 0x88, 0, 0, 35, 0xCC, 0xDD]) }
                if b[3] == 2 { return Data([0xAA, 0xBB, 0x88, 0, 2, b[4], 0, 0, 0xCC, 0xDD]) }
                return Data([0xAA, 0xBB, 0x88, 0, 3, b[4]] + Array(repeating: 0, count: 10) + [0xCC, 0xDD])
            }
            return Data([0xAA, 0xBB, b[2], 0, 0xCC, 0xDD])
        }
        func session() -> AgentPresentationSession {
            AgentPresentationSession(exchange: { data in
                self.requests.append(data)
                if let result = try await self.intercept?(data) { return result }
                return self.response(data)
            }, sendSingleDefault: { self.defaults += 1; return true }, onFault: {
                self.faults += 1; self.didFault?()
            }, now: { self.clock })
        }
    }
    private func task(_ id: String) -> WS3TaskMetadata { WS3TaskMetadata(client: .codex, session: id, event: "CodexPreToolUse")! }
    private let ack = Data([0xAA, 0xBB, 0x99, 0, 0xCC, 0xDD])

    func testSocketModeDoesNotCoerceBooleanStringOrOutOfRangeValues() {
        XCTAssertEqual(AhaKeyAgent.parsePresentationMode(0), .single)
        XCTAssertEqual(AhaKeyAgent.parsePresentationMode(1), .multi)
        for invalid: Any in [true, "1", 1.5, 2, -1, NSNull()] {
            XCTAssertNil(AhaKeyAgent.parsePresentationMode(invalid))
        }
        XCTAssertNil(AhaKeyAgent.parsePresentationMode(nil))
    }

    func testExplicitModesClearFactsAndRepeatsHaveNoWrites() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        session.observe(task("old"), state: 7)
        XCTAssertTrue(io.requests.isEmpty)
        _ = try await session.activate(.multi)
        XCTAssertTrue(session.overview().tasks.isEmpty)
        XCTAssertFalse(session.allowsLegacySingle)
        let count = io.requests.count
        _ = try await session.activate(.multi)
        XCTAssertEqual(io.requests.count, count)
        _ = try await session.activate(.single)
        XCTAssertTrue(session.allowsLegacySingle)
        XCTAssertEqual(io.defaults, 1)
        let singleCount = io.requests.count
        _ = try await session.activate(.single)
        XCTAssertEqual(io.requests.count, singleCount)
        XCTAssertEqual(io.defaults, 1)
    }

    func testGracefulHandoffClearsBothRuntimesOnlyAfterConnectionProof() async throws {
        for mode in [WS3PresentationMode.single, .multi] {
            let io = Fixture(), session = io.session()
            session.updateConnection(connected: true, generation: 1)
            _ = try await session.activate(mode)
            let count = io.requests.count
            await session.quiesce()
            let cleanup = Array(io.requests.dropFirst(count))
            let expected = mode == .single ? [UInt8(0x98), 0x99, 0x98] : [UInt8(0x99), 0x98]
            XCTAssertEqual(cleanup.map { $0[2] }, expected)
            XCTAssertEqual(cleanup.last, WS3PresentationCommand.setMode(.single).request)
            XCTAssertNil(session.requestedMode)
            XCTAssertFalse(session.overview().connected)
        }
        let io = Fixture(), unproven = io.session()
        unproven.updateConnection(connected: true, generation: 1)
        await unproven.quiesce()
        XCTAssertTrue(io.requests.isEmpty)
    }

    func testConcurrentModeChangeIsRejectedAndBusyHooksDoNotReplay() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        let started = expectation(description: "probe entered")
        var release: CheckedContinuation<Data?, Error>?
        io.intercept = { data in
            if io.requests.count == 1 {
                started.fulfill()
                return try await withCheckedThrowingContinuation { release = $0 }
            }
            return nil
        }
        let pending = Task { try await session.activate(.multi) }
        await fulfillment(of: [started], timeout: 2)
        session.observe(task("during-switch"), state: 7)
        do { _ = try await session.activate(.single); XCTFail("must serialize modes") }
        catch { XCTAssertEqual(error as? WS3PresentationError, .busy) }
        release?.resume(returning: io.response(io.requests[0]))
        _ = try await pending.value
        XCTAssertTrue(session.overview().tasks.isEmpty)
    }

    func testOldProbeCannotMutateReconnectedMode() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        let started = expectation(description: "old probe entered")
        var release: CheckedContinuation<Data?, Error>?
        io.intercept = { data in
            if io.requests.count == 1 {
                started.fulfill()
                return try await withCheckedThrowingContinuation { release = $0 }
            }
            return nil
        }
        let old = Task { try await session.activate(.multi) }
        await fulfillment(of: [started], timeout: 2)
        session.updateConnection(connected: false, generation: 1)
        session.updateConnection(connected: true, generation: 2)
        XCTAssertNil(session.requestedMode)
        _ = try await session.activate(.single)
        release?.resume(returning: io.response(io.requests[0]))
        do { _ = try await old.value; XCTFail("old connection must fail") } catch {}
        XCTAssertEqual(session.requestedMode, .single)
        XCTAssertFalse(io.requests.contains(WS3PresentationCommand.setMode(.multi).request!))
    }

    func testSnapshotWritesAreSingleFlightAndCoalesceNewestFacts() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        _ = try await session.activate(.multi)
        let first = expectation(description: "first state submitted"), second = expectation(description: "latest state submitted")
        var release: CheckedContinuation<Data?, Error>?
        var snapshots: [WS3TaskSnapshot] = []
        io.intercept = { data in
            if let snapshot = WS3TaskSnapshot(request: data) {
                snapshots.append(snapshot)
                if snapshots.count == 1 {
                    first.fulfill()
                    return try await withCheckedThrowingContinuation { release = $0 }
                }
                second.fulfill()
            }
            return nil
        }
        session.observe(task("a"), state: 7)
        await fulfillment(of: [first], timeout: 2)
        session.observe(task("a"), state: 1)
        session.observe(task("b"), state: 7)
        XCTAssertEqual(snapshots.count, 1)
        release?.resume(returning: ack)
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(snapshots[1].slots[0]?.state, .waiting)
        XCTAssertEqual(snapshots[1].slots[1]?.state, .running)
        XCTAssertFalse(io.requests.contains { $0[2] == 0x9A })
        session.updateConnection(connected: false, generation: 1)
    }

    func testExpiredTasksSendOneCleanupSnapshotNotKeepalive() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        _ = try await session.activate(.multi)
        let live = expectation(description: "live task"), empty = expectation(description: "expiry clears device")
        io.intercept = { data in
            if let snapshot = WS3TaskSnapshot(request: data) {
                if snapshot.slots.allSatisfy({ $0 == nil }) { empty.fulfill() } else { live.fulfill() }
            }
            return nil
        }
        session.observe(task("a"), state: 7)
        await fulfillment(of: [live], timeout: 2)
        io.clock = 300
        session.expireTasks()
        await fulfillment(of: [empty], timeout: 2)
        XCTAssertTrue(session.overview().tasks.isEmpty)
        session.updateConnection(connected: false, generation: 1)
    }

    func testSnapshotFailureDisablesRoutingUntilNewConnectionAndExplicitSelection() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        _ = try await session.activate(.multi)
        let failed = expectation(description: "runtime fault")
        io.didFault = { failed.fulfill() }
        io.intercept = { data in data[2] == 0x99 ? Data([0xAA, 0xBB, 0x99, 1, 0xCC, 0xDD]) : nil }
        session.observe(task("a"), state: 7)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertNil(session.requestedMode)
        XCTAssertFalse(session.overview().connected)
        let count = io.requests.count
        session.observe(task("b"), state: 7)
        XCTAssertEqual(io.requests.count, count)
        session.updateConnection(connected: true, generation: 2)
        XCTAssertNil(session.requestedMode)
        XCTAssertTrue(session.overview().tasks.isEmpty)
    }

    func testKeyboardModeBoundaryDrainsOldWriteThenClearsInsteadOfReplaying() async throws {
        let io = Fixture(), session = io.session()
        session.updateConnection(connected: true, generation: 1)
        _ = try await session.activate(.multi)
        let submitted = expectation(description: "old write"), cleared = expectation(description: "clear after mode boundary")
        var release: CheckedContinuation<Data?, Error>?
        var snapshots: [WS3TaskSnapshot] = []
        io.intercept = { data in
            if let snapshot = WS3TaskSnapshot(request: data) {
                snapshots.append(snapshot)
                if snapshots.count == 1 {
                    submitted.fulfill()
                    return try await withCheckedThrowingContinuation { release = $0 }
                }
                cleared.fulfill()
            }
            return nil
        }
        session.observe(task("old"), state: 7)
        await fulfillment(of: [submitted], timeout: 2)
        session.keyboardWorkModeChanged()
        release?.resume(returning: ack)
        await fulfillment(of: [cleared], timeout: 2)
        XCTAssertTrue(snapshots[1].slots.allSatisfy { $0 == nil })
        XCTAssertTrue(session.overview().tasks.isEmpty)
        session.updateConnection(connected: false, generation: 1)
    }
}
