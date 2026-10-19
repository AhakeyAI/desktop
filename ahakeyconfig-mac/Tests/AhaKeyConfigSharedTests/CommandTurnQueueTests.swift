import XCTest
@testable import AhaKeyConfigShared

final class CommandTurnQueueTests: XCTestCase {
    @MainActor
    private func waitForQueue(_ queue: CommandTurnQueue, count: Int) async {
        for _ in 0..<1000 {
            if queue.waitingCount == count { return }
            await Task.yield()
        }
        XCTFail("queue did not reach expected count \(count)")
    }
    @MainActor
    func testCancelledWaiterIsRemovedWithoutReleasingTheActiveCommand() async throws {
        let queue = CommandTurnQueue()
        let first = try await queue.acquire()
        let cancelled = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 1)
        let next = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 2)
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("cancelled waiter acquired a turn") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(queue.waitingCount, 1)
        XCTAssertTrue(queue.isOccupied)
        XCTAssertFalse(queue.isInvalidated)
        queue.release(first)
        let ticket = try await next.value
        queue.release(ticket)
        XCTAssertFalse(queue.isOccupied)
    }
    @MainActor
    func testFIFOAndDuplicateOldReleaseCannotReleaseNextOwner() async throws {
        let queue = CommandTurnQueue()
        let first = try await queue.acquire()
        let second = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 1)
        let third = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 2)
        queue.release(first)
        let middle = try await second.value
        queue.release(first)
        XCTAssertEqual(queue.waitingCount, 1)
        queue.release(middle)
        let last = try await third.value
        queue.release(last)
        XCTAssertFalse(queue.isOccupied)
    }
    @MainActor
    func testInvalidationDrainsQueuedRequestsAndRequiresReset() async throws {
        let queue = CommandTurnQueue()
        let first = try await queue.acquire()
        let waiting = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 1)
        queue.invalidate()
        XCTAssertFalse(queue.isCurrent(first))
        do { _ = try await waiting.value; XCTFail("invalidated waiter resumed successfully") }
        catch { XCTAssertEqual(error as? CommandTurnQueue.Failure, .invalidated) }
        queue.release(first)
        do { _ = try await queue.acquire(); XCTFail("late ACK/release reopened the channel") }
        catch { XCTAssertEqual(error as? CommandTurnQueue.Failure, .invalidated) }
        queue.reset(generation: 4)
        let fresh = try await queue.acquire()
        XCTAssertEqual(fresh.generation, 4)
        queue.release(fresh)
    }
    @MainActor
    func testDisconnectResetsWaitersAndOldOwnerCannotReleaseNewConnection() async throws {
        let queue = CommandTurnQueue()
        let old = try await queue.acquire()
        let waiting = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 1)
        queue.reset(generation: 9)
        do { _ = try await waiting.value; XCTFail("old generation survived reset") }
        catch { XCTAssertEqual(error as? CommandTurnQueue.Failure, .reset) }
        let fresh = try await queue.acquire()
        queue.release(old)
        XCTAssertFalse(queue.isCurrent(old))
        XCTAssertTrue(queue.isCurrent(fresh))
        XCTAssertTrue(queue.isOccupied)
        XCTAssertEqual(fresh.generation, 9)
        queue.release(fresh)
    }
    @MainActor
    func testCancelledBeforeAcquireNeverOccupiesTheChannel() async throws {
        let queue = CommandTurnQueue()
        let task = Task { try await queue.acquire() }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled caller acquired") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(queue.isOccupied)
        XCTAssertEqual(queue.waitingCount, 0)
    }
    @MainActor
    func testCancellationRacingWithHandoffReturnsUnconsumedTurn() async throws {
        let queue = CommandTurnQueue()
        let first = try await queue.acquire()
        let waiting = Task { try await queue.acquire() }
        await waitForQueue(queue, count: 1)
        // Both calls happen before the newly resumed task can run on MainActor.
        queue.release(first)
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("cancelled handoff returned a ticket") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(queue.isOccupied)
        let next = try await queue.acquire()
        queue.release(next)
    }
}
