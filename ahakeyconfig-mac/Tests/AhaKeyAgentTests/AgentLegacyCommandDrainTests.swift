import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

@MainActor
final class AgentLegacyCommandDrainTests: XCTestCase {
    private let stateAck = Data([0xAA, 0xBB, 0x90, 0, 0xCC, 0xDD])
    private let status = Data([0xAA, 0xBB, 0, 75, 0, 1, 0, 3, 0, 1, 0, 0xCC, 0xDD])

    func testBackToBackDefaultAndHookWaitForSeparateAcknowledgements() async throws {
        let drain = AgentLegacyCommandDrain()
        var wire: [UInt8] = []
        drain.submit(0x90) { _ in wire.append(8) }
        drain.submit(0x90) { _ in wire.append(7) }
        var probe = false
        let next = Task { try await drain.waitUntilIdle(); probe = true }
        await Task.yield()
        XCTAssertEqual(wire, [8])
        drain.received(stateAck)
        await Task.yield()
        XCTAssertEqual(wire, [8, 7])
        XCTAssertFalse(probe)
        drain.received(stateAck)
        try await next.value
        XCTAssertTrue(probe)
    }

    func testQueuedStatusDisconnectCompletesExactlyOnceWithoutSending() {
        let drain = AgentLegacyCommandDrain()
        var statusSent = 0, statusCanceled = 0
        drain.submit(0x90) { _ in }
        drain.submit(0, onAbandon: { statusCanceled += 1 }) { _ in statusSent += 1 }
        XCTAssertEqual(statusSent, 0)
        drain.reset()
        XCTAssertEqual(statusCanceled, 1)
        drain.reset()
        drain.received(stateAck)
        XCTAssertEqual(statusCanceled, 1)
        XCTAssertEqual(statusSent, 0)
    }

    func testLegacyTwelveByteStatusReleasesNextWrite() async throws {
        let drain = AgentLegacyCommandDrain()
        var writes = 0
        drain.submit(0) { _ in writes += 1 }
        drain.submit(0x90) { _ in writes += 1 }
        let legacy = Data([0xAA, 0xBB, 0, 75, 0, 1, 0, 3, 0, 1, 0xCC, 0xDD])
        XCTAssertNotNil(AhaKeyAgent.parseDeviceStatus(legacy))
        drain.received(legacy)
        XCTAssertEqual(writes, 2)
        drain.received(stateAck)
        try await drain.waitUntilIdle()
    }

    func testModeProbeCannotOvertakeLegacyStateOrStatusReply() async throws {
        let drain = AgentLegacyCommandDrain()
        _ = drain.sent(0x90); _ = drain.sent(0)
        var probeSent = false
        let task = Task { try await drain.waitUntilIdle(); probeSent = true }
        await Task.yield()
        XCTAssertFalse(probeSent)
        drain.received(Data([0xAA, 0xBB, 0x90, 0xCC, 0xDD])) // not a valid ACK
        drain.received(Data([0xAA, 0xBB, 0x98, 0, 0xCC, 0xDD])) // wrong command
        await Task.yield()
        XCTAssertFalse(probeSent)
        drain.received(stateAck)
        await Task.yield()
        XCTAssertFalse(probeSent)
        drain.received(status)
        try await task.value
        XCTAssertTrue(probeSent)
    }

    func testMultipleLegacyWritesRequireAllReplies() async throws {
        let drain = AgentLegacyCommandDrain()
        _ = drain.sent(0x90); _ = drain.sent(0x90)
        var ready = false
        let task = Task { try await drain.waitUntilIdle(); ready = true }
        await Task.yield()
        drain.received(stateAck)
        await Task.yield()
        XCTAssertFalse(ready)
        drain.received(stateAck)
        try await task.value
        XCTAssertTrue(ready)
    }

    func testLostReplyPreventsAdvancedTrafficUntilReconnect() async {
        let drain = AgentLegacyCommandDrain(), token = drain.sent(0x90)
        let pending = Task { try await drain.waitUntilIdle() }
        await Task.yield()
        drain.expired(token)
        do { try await pending.value; XCTFail("lost reply must not permit a probe") }
        catch { XCTAssertEqual(error as? WS3PresentationError, .timedOut) }
        drain.received(stateAck) // late reply cannot repair the ambiguous channel
        do { try await drain.waitUntilIdle(); XCTFail("must remain invalid") }
        catch { XCTAssertEqual(error as? WS3PresentationError, .timedOut) }
        drain.reset()
        do { try await drain.waitUntilIdle() } catch { XCTFail("new connection should be usable") }
    }

    func testResetAndOldDeadlineCannotReleaseNewConnection() async throws {
        let drain = AgentLegacyCommandDrain(), old = drain.sent(0x90)
        let pending = Task { try await drain.waitUntilIdle() }
        await Task.yield()
        drain.reset()
        do { try await pending.value; XCTFail("old probe must fail") }
        catch { XCTAssertEqual(error as? WS3PresentationError, .connectionChanged) }
        _ = drain.sent(0x90)
        drain.expired(old)
        let fresh = Task { try await drain.waitUntilIdle() }
        drain.received(stateAck)
        try await fresh.value
    }

    func testCancellationDoesNotConsumeTheLegacyReply() async throws {
        let drain = AgentLegacyCommandDrain()
        _ = drain.sent(0x90)
        let canceled = Task { try await drain.waitUntilIdle() }
        await Task.yield()
        canceled.cancel()
        do { try await canceled.value; XCTFail("must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let next = Task { try await drain.waitUntilIdle() }
        drain.received(stateAck)
        try await next.value
    }
}
