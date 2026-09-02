import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

/// 记录 probe 调度；cancel 后仍保留 fire，用于 shutdown 竞态。
private final class RecordingProbeScheduler: AhaKeyBLEProbeScheduling {
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0
    private(set) var lastAfter: TimeInterval?
    private var pending: (() -> Void)?
    private var stale: (() -> Void)?

    func scheduleProbe(after: TimeInterval, token: UInt64, fire: @escaping () -> Void) {
        scheduleCount += 1
        lastAfter = after
        pending = fire
        stale = nil
    }

    func cancelProbe() {
        cancelCount += 1
        stale = pending
        pending = nil
    }

    func firePending() {
        pending?()
    }

    func fireStale() {
        stale?()
    }
}

private final class RecordingBLEHost: AhaKeyBLELifecycleAdapter.Host {
    var attached: [AhaKeySystemAttachedProbe.PeripheralRef] = []
    var connectSucceeds = true
    private(set) var retrieveCount = 0
    private(set) var connectUUIDs: [String] = []
    private(set) var emits: [String] = []
    private(set) var scanStarts = 0
    private(set) var scanStops = 0

    func retrieveSystemAttached() -> [AhaKeySystemAttachedProbe.PeripheralRef] {
        retrieveCount += 1
        return attached
    }

    func connectRetrieved(uuid: String) -> Bool {
        connectUUIDs.append(uuid)
        return connectSucceeds
    }

    func connectKnown(uuid: String) {}
    func startScan() { scanStarts += 1 }
    func stopScan() { scanStops += 1 }
    func acquireConnectionLock() -> Bool { true }
    func discoverServices(uuid: String) {}
    func sendCapabilityNegotiation(uuid: String) {}
    func disconnect(uuid: String) {}
    func emit(_ message: String) { emits.append(message) }
    func scheduleReconnect(after: TimeInterval) {}
}

final class AhaKeyBLELifecycleAdapterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let uuid = "UUID-X1"

    private func makeScanningAdapter(
        host: RecordingBLEHost,
        scheduler: RecordingProbeScheduler
    ) -> AhaKeyBLELifecycleAdapter {
        let adapter = AhaKeyBLELifecycleAdapter(namePrefix: "AhaKey", scheduler: scheduler)
        adapter.host = host
        adapter.handle(.bluetoothPoweredOn, now: now)
        adapter.handle(.lockAcquired, now: now)
        return adapter
    }

    func testEmptyProbe_zeroEmit_zeroConnect_rearmsOnce() {
        let host = RecordingBLEHost()
        let scheduler = RecordingProbeScheduler()
        let adapter = makeScanningAdapter(host: host, scheduler: scheduler)

        XCTAssertEqual(host.retrieveCount, 1, "初始 scan 只 retrieve 一次")
        XCTAssertEqual(host.connectUUIDs, [])
        XCTAssertEqual(host.emits, [NSLocalizedString("开始扫描…", comment: "")])
        XCTAssertEqual(host.scanStarts, 1)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.lastAfter, DeviceTransportCore.systemAttachedProbeInterval)

        let emitsAfterScan = host.emits
        scheduler.firePending()

        XCTAssertEqual(host.retrieveCount, 2, "空 probe 再 retrieve 一次")
        XCTAssertEqual(host.connectUUIDs, [])
        XCTAssertEqual(host.emits, emitsAfterScan, "空 probe 零常规日志/零 UI")
        XCTAssertEqual(scheduler.scheduleCount, 2, "空结果只重排一次")
        guard case .scanning = adapter.core.phase else { return XCTFail() }
    }

    func testHit_singleRetrieve_singleConnect() {
        let host = RecordingBLEHost()
        host.attached = [.init(name: "AhaKey X1", uuid: uuid)]
        let scheduler = RecordingProbeScheduler()
        let adapter = makeScanningAdapter(host: host, scheduler: scheduler)

        XCTAssertEqual(host.retrieveCount, 1)
        XCTAssertEqual(host.connectUUIDs, [uuid], "命中只 connect 一次")
        XCTAssertEqual(host.emits, ["系统已连接: AhaKey X1"])
        XCTAssertEqual(host.scanStops, 1)
        guard case .connecting(let connectingUUID) = adapter.core.phase else {
            return XCTFail("命中后应 connecting，实际 \(adapter.core.phase)")
        }
        XCTAssertEqual(connectingUUID, uuid)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testShutdown_thenStaleTimer_doesNotRetrieveOrConnectOrRearm() {
        let host = RecordingBLEHost()
        let scheduler = RecordingProbeScheduler()
        let adapter = makeScanningAdapter(host: host, scheduler: scheduler)

        let retrieves = host.retrieveCount
        let connects = host.connectUUIDs.count
        let schedules = scheduler.scheduleCount
        adapter.shutdown(now: now)
        XCTAssertEqual(scheduler.cancelCount, 1)
        guard case .idle = adapter.core.phase else { return XCTFail() }

        scheduler.fireStale()
        XCTAssertEqual(host.retrieveCount, retrieves)
        XCTAssertEqual(host.connectUUIDs.count, connects)
        XCTAssertEqual(scheduler.scheduleCount, schedules)
        guard case .idle = adapter.core.phase else { return XCTFail("stale fire 不得复活") }
    }

    func testConnectStartFails_returnsToScanning_doesNotStick() {
        let host = RecordingBLEHost()
        host.attached = [.init(name: "AhaKey X1", uuid: uuid)]
        host.connectSucceeds = false
        let scheduler = RecordingProbeScheduler()
        let adapter = makeScanningAdapter(host: host, scheduler: scheduler)

        XCTAssertEqual(host.connectUUIDs, [uuid])
        XCTAssertEqual(host.retrieveCount, 1, "失败回退不得立刻再 retrieve")
        XCTAssertFalse(host.emits.contains(where: { $0.hasPrefix("系统已连接") }))
        guard case .scanning = adapter.core.phase else {
            return XCTFail("connect 失败必须回 scanning，实际 \(adapter.core.phase)")
        }
        XCTAssertGreaterThanOrEqual(scheduler.scheduleCount, 1, "失败后恰重排 probe")
    }

    func testDidFailToConnect_returnsToScanning() {
        let host = RecordingBLEHost()
        host.attached = [.init(name: "AhaKey X1", uuid: uuid)]
        let scheduler = RecordingProbeScheduler()
        let adapter = makeScanningAdapter(host: host, scheduler: scheduler)
        guard case .connecting = adapter.core.phase else { return XCTFail() }

        host.attached = []
        adapter.handle(.lookupOrConnectFailed, now: now)
        guard case .scanning = adapter.core.phase else {
            return XCTFail("didFailToConnect 不得留在 connecting")
        }
    }
}
