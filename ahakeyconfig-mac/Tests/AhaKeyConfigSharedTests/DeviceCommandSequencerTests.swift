import XCTest
@testable import AhaKeyConfigShared

final class DeviceCommandSequencerTests: XCTestCase {
    private let gen1 = DeviceGenerations(session: 1, transport: 1)
    private let gen1t2 = DeviceGenerations(session: 1, transport: 2)
    private let gen2 = DeviceGenerations(session: 2, transport: 1)

    private func cmd(_ op: UInt64, gen: DeviceGenerations? = nil, dev: String = "507C") -> DeviceCommand {
        DeviceCommand(operationID: op, deviceID: dev, generations: gen ?? gen1, opcode: 0x00, payload: Data([0x01]))
    }

    // MARK: - 串行队列

    func testQueueIsSerial_headBlocksNext() {
        var q = DeviceCommandQueue()
        let first = q.enqueue(cmd(1))
        XCTAssertEqual(first?.operationID, 1, "空闲时首条应立即放行")
        XCTAssertNil(q.enqueue(cmd(2)), "head 在途时不得放行第二条")
        XCTAssertEqual(q.inFlight?.operationID, 1)
    }

    func testCompleteHead_promotesNext() {
        var q = DeviceCommandQueue()
        _ = q.enqueue(cmd(1)); _ = q.enqueue(cmd(2)); _ = q.enqueue(cmd(3))
        XCTAssertEqual(q.completeHead()?.operationID, 2)
        XCTAssertEqual(q.completeHead()?.operationID, 3)
        XCTAssertNil(q.completeHead())
        XCTAssertNil(q.inFlight)
    }

    func testInvalidateAll_clearsPendingAndInFlight() {
        var q = DeviceCommandQueue()
        _ = q.enqueue(cmd(1)); _ = q.enqueue(cmd(2))
        q.invalidateAll()
        XCTAssertNil(q.inFlight)
        XCTAssertTrue(q.pending.isEmpty)
    }

    // MARK: - waiter 五元绑定

    func testResolve_matchingTuple_completesWithPayload() {
        var r = DeviceWaiterRegistry()
        let now = Date()
        let id = r.register(operationID: 7, deviceID: "507C", generations: gen1, now: now, timeout: 5)
        let outcome = r.resolve(requestID: id, fromOperation: 7, device: "507C", generations: gen1, payload: Data([0xAA]))
        XCTAssertEqual(outcome, .response(Data([0xAA])))
        XCTAssertTrue(r.isEmpty)
    }

    func testResolve_staleTransportGeneration_doesNotComplete() {
        var r = DeviceWaiterRegistry()
        let now = Date()
        // 旧 transport 上注册的 waiter
        let oldID = r.register(operationID: 7, deviceID: "507C", generations: gen1, now: now, timeout: 50)
        // 断连重连后旧 waiter 被强败
        _ = r.invalidateGenerations(notMatching: gen1t2)
        // 新 transport 上注册了「相同业务语义」的新 waiter（新 requestID）
        let newID = r.register(operationID: 8, deviceID: "507C", generations: gen1t2, now: now, timeout: 50)
        // 迟到回包：它属于旧 waiter 的 requestID，但 generation 已是旧值 → 不得完成新 waiter
        XCTAssertNil(r.resolve(requestID: oldID, fromOperation: 7, device: "507C", generations: gen1, payload: Data([0xAA])))
        XCTAssertNil(r.resolve(requestID: newID, fromOperation: 8, device: "507C", generations: gen1, payload: Data([0xAA])),
                     "旧 transport generation 的回包绝不能完成新 waiter")
        // 正确回包才能完成
        XCTAssertEqual(r.resolve(requestID: newID, fromOperation: 8, device: "507C", generations: gen1t2, payload: Data([0xBB])), .response(Data([0xBB])))
    }

    func testResolve_wrongDeviceOrSession_rejected() {
        var r = DeviceWaiterRegistry()
        let now = Date()
        let id = r.register(operationID: 7, deviceID: "507C", generations: gen1, now: now, timeout: 50)
        XCTAssertNil(r.resolve(requestID: id, fromOperation: 7, device: "515C", generations: gen1, payload: Data()))
        XCTAssertNil(r.resolve(requestID: id, fromOperation: 7, device: "507C", generations: gen2, payload: Data()))
        XCTAssertNil(r.resolve(requestID: id, fromOperation: 9, device: "507C", generations: gen1, payload: Data()))
        XCTAssertFalse(r.isEmpty, "不匹配的回包不得删除 waiter")
    }

    func testResolve_unknownRequestID_returnsNil() {
        var r = DeviceWaiterRegistry()
        XCTAssertNil(r.resolve(requestID: 999, fromOperation: 1, device: "507C", generations: gen1, payload: Data()))
    }

    func testTimeouts_onlyExpiredCollected() {
        var r = DeviceWaiterRegistry()
        let t0 = Date()
        let a = r.register(operationID: 1, deviceID: "507C", generations: gen1, now: t0, timeout: 1)
        _ = r.register(operationID: 2, deviceID: "507C", generations: gen1, now: t0, timeout: 100)
        let expired = r.collectTimeouts(now: t0.addingTimeInterval(2))
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(expired.first?.requestID, a)
        XCTAssertEqual(expired.first?.outcome, .timedOut)
        XCTAssertEqual(r.waiters.count, 1)
    }

    func testInvalidateGenerations_failsOnlyStaleWaiters() {
        var r = DeviceWaiterRegistry()
        let now = Date()
        let stale = r.register(operationID: 1, deviceID: "507C", generations: gen1, now: now, timeout: 50)
        let fresh = r.register(operationID: 2, deviceID: "507C", generations: gen1t2, now: now, timeout: 50)
        let failed = r.invalidateGenerations(notMatching: gen1t2)
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(failed.first?.requestID, stale)
        XCTAssertEqual(failed.first?.outcome, .generationInvalidated)
        XCTAssertEqual(r.waiters[fresh]?.operationID, 2, "新代际 waiter 必须存活")
    }

    func testRequestIDs_monotonic() {
        var r = DeviceWaiterRegistry()
        let now = Date()
        let a = r.register(operationID: 1, deviceID: "507C", generations: gen1, now: now, timeout: 5)
        let b = r.register(operationID: 2, deviceID: "507C", generations: gen1, now: now, timeout: 5)
        XCTAssertLessThan(a, b)
    }
}
