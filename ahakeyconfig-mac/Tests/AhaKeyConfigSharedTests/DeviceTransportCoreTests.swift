import XCTest
@testable import AhaKeyConfigShared

final class DeviceTransportCoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeCore() -> DeviceTransportCore {
        DeviceTransportCore(sessionGeneration: 1, backoff: BackoffSchedule(intervals: [2, 4, 8]))
    }

    /// 走完 poweredOn → lock → 直连已知 → 协商 current → ready 的完整链。
    private func driveToReady(_ core: inout DeviceTransportCore, uuid: String = "UUID-A", deviceID: String = "507C") {
        XCTAssertEqual(core.handle(.bluetoothPoweredOn, now: now), [.acquireConnectionLock])
        _ = core.handle(.lockAcquired, now: now)   // 无 lastUUID → scan
        _ = core.handle(.discovered(uuid: uuid, deviceID: deviceID), now: now)
        _ = core.handle(.connected(uuid: uuid), now: now)
        _ = core.handle(.servicesReady(uuid: uuid), now: now)
        _ = core.handle(.negotiationFinished(uuid: uuid, mode: .current), now: now)
    }

    func testFullChain_reachesReady_withCurrentOnly() {
        var c = makeCore()
        driveToReady(&c)
        guard case .ready(let uuid, let deviceID) = c.phase else { return XCTFail("应进入 ready") }
        XCTAssertEqual(uuid, "UUID-A")
        XCTAssertEqual(deviceID, "507C")
        XCTAssertTrue(c.isReady)
    }

    func testPoweredOn_firstConnect_scansWhenNoLastUUID() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        let actions = c.handle(.lockAcquired, now: now)
        XCTAssertEqual(
            actions,
            [
                .scan,
                .scheduleSystemAttachedProbe(
                    after: DeviceTransportCore.systemAttachedProbeInterval,
                    token: 1
                ),
            ]
        )
        guard case .scanning = c.phase else { return XCTFail() }
    }

    func testReconnect_prefersKnownUUID() {
        var c = makeCore()
        driveToReady(&c)
        _ = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        _ = c.handle(.reconnectTimerFired, now: now)
        let actions = c.handle(.lockAcquired, now: now)
        XCTAssertEqual(actions, [.connectKnown(uuid: "UUID-A")], "断连后应直连已知 UUID 而非扫描")
    }

    func testSystemAttachedPreferred_overScanWhenNoLastUUID() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        // 扫描期间发现系统已连接设备
        let actions = c.handle(.systemAttachedDeviceFound(uuid: "UUID-S"), now: now)
        XCTAssertEqual(actions, [.cancelSystemAttachedProbe, .connectSystemAttached(uuid: "UUID-S")])
        let second = c.handle(.systemAttachedDeviceFound(uuid: "UUID-S"), now: now)
        XCTAssertEqual(second, [], "已离开 scanning 后不得再 connectSystemAttached")
    }

    func testCurrentOnly_legacyDoesNotBecomeReady() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.discovered(uuid: "U", deviceID: nil), now: now)
        _ = c.handle(.connected(uuid: "U"), now: now)
        _ = c.handle(.servicesReady(uuid: "U"), now: now)
        let actions = c.handle(.negotiationFinished(uuid: "U", mode: .legacy), now: now)
        XCTAssertEqual(actions, [])
        XCTAssertFalse(c.isReady, "legacy 协商结果不得进入 ready（current-only）")
    }

    func testDisconnect_bumpsTransportGeneration_onNextConnect() {
        var c = makeCore()
        driveToReady(&c)
        let genBefore = c.currentGenerations
        _ = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        _ = c.handle(.reconnectTimerFired, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.connected(uuid: "UUID-A"), now: now)
        XCTAssertEqual(c.currentGenerations.session, genBefore.session)
        XCTAssertEqual(c.currentGenerations.transport, genBefore.transport + 1, "重连必须推进 transport generation")
    }

    func testDisconnect_failsCurrentGenerationWaiters() {
        var c = makeCore()
        driveToReady(&c)
        let id = c.registerWaiter(operationID: 1, now: now, timeout: 60)
        XCTAssertNotNil(id)
        _ = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        XCTAssertTrue(c.waiters.isEmpty, "断连必须强败当前代际 waiter（transport 已消失）")
    }

    func testReady_requiresStableDeviceID_noUUIDFallback() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.discovered(uuid: "U", deviceID: nil), now: now)  // 广播无编号
        _ = c.handle(.connected(uuid: "U"), now: now)
        _ = c.handle(.servicesReady(uuid: "U"), now: now)
        _ = c.handle(.negotiationFinished(uuid: "U", mode: .current), now: now)
        XCTAssertFalse(c.isReady, "未识别稳定 device ID 不得 ready（禁止 UUID 兜底）")
        XCTAssertNil(c.registerWaiter(operationID: 1, now: now, timeout: 10), "未识别设备不得注册 waiter")
    }

    func testDisconnect_backoffSequence_progresses() {
        var c = makeCore()
        driveToReady(&c)
        let a1 = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        XCTAssertEqual(a1, [.scheduleReconnectTimer(after: 2)])
        guard case .backoffReconnect(let until) = c.phase else { return XCTFail() }
        XCTAssertEqual(until, now.addingTimeInterval(2))
        // 第二次断连退避升级
        _ = c.handle(.reconnectTimerFired, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.connected(uuid: "UUID-A"), now: now)
        _ = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        guard case .backoffReconnect(let until2) = c.phase else { return XCTFail() }
        XCTAssertEqual(until2, now.addingTimeInterval(4), "退避应进入第二级")
    }

    func testBluetoothUnavailable_resetsToIdle() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.bluetoothUnavailable, now: now)
        guard case .idle = c.phase else { return XCTFail() }
    }

    func testLockBusy_staysAwaitingLock() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        let actions = c.handle(.lockBusy, now: now)
        XCTAssertEqual(actions, [])
        guard case .awaitingLock = c.phase else { return XCTFail() }
    }

    func testPoweredOn_resetsBackoff() {
        var c = makeCore()
        driveToReady(&c)
        _ = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        _ = c.handle(.bluetoothUnavailable, now: now)
        _ = c.handle(.bluetoothPoweredOn, now: now)
        // 重新断连后应回到第一级退避
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.connected(uuid: "UUID-A"), now: now)
        let actions = c.handle(.disconnected(uuid: "UUID-A"), now: now)
        XCTAssertEqual(actions, [.scheduleReconnectTimer(after: 2)])
    }
}

extension DeviceTransportCoreTests {
    func testIdentityRace_negotiationWaitsForDeviceID_thenReady() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.discovered(uuid: "U", deviceID: nil), now: now)
        _ = c.handle(.connected(uuid: "U"), now: now)
        _ = c.handle(.servicesReady(uuid: "U"), now: now)
        _ = c.handle(.negotiationFinished(uuid: "U", mode: .current), now: now)
        XCTAssertFalse(c.isReady)
        // 序列号回读补齐身份 → 立即 ready
        _ = c.handle(.deviceIdentified(deviceID: "507C"), now: now)
        XCTAssertTrue(c.isReady)
        XCTAssertEqual(c.stableDeviceID, "507C")
    }

    func testIdentityRace_legacyMode_notUnlockedByIdentity() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.discovered(uuid: "U", deviceID: nil), now: now)
        _ = c.handle(.connected(uuid: "U"), now: now)
        _ = c.handle(.servicesReady(uuid: "U"), now: now)
        _ = c.handle(.negotiationFinished(uuid: "U", mode: .legacy), now: now)
        _ = c.handle(.deviceIdentified(deviceID: "507C"), now: now)
        XCTAssertFalse(c.isReady, "legacy 协商结果不因身份补齐而放行")
    }
}

extension DeviceTransportCoreTests {
    func testScanning_emptyProbe_reschedulesOnce() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        XCTAssertEqual(
            c.handle(.systemAttachedProbeFired(token: 1), now: now),
            [.probeSystemAttached]
        )
        XCTAssertEqual(
            c.handle(.systemAttachedProbeEmpty, now: now),
            [
                .scheduleSystemAttachedProbe(
                    after: DeviceTransportCore.systemAttachedProbeInterval,
                    token: 2
                ),
            ]
        )
        guard case .scanning = c.phase else { return XCTFail("空 probe 必须留在 scanning") }
    }

    func testScanning_staleProbe_isNoOp() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.systemAttachedDeviceFound(uuid: "UUID-S"), now: now)
        XCTAssertEqual(
            c.handle(.systemAttachedProbeFired(token: 1), now: now),
            [],
            "过期 probe 在非 scanning 必须 no-op"
        )
        XCTAssertEqual(c.handle(.systemAttachedProbeEmpty, now: now), [])
    }

    func testBluetoothUnavailable_invalidatesProbe() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        let actions = c.handle(.bluetoothUnavailable, now: now)
        XCTAssertTrue(actions.contains(.cancelSystemAttachedProbe))
        guard case .idle = c.phase else { return XCTFail() }
        XCTAssertEqual(
            c.handle(.systemAttachedProbeFired(token: 1), now: now),
            [],
            "蓝牙不可用后过期 probe 不得再连"
        )
    }

    func testShutdown_invalidatesProbeAndIdles() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        let token = c.systemAttachedProbeToken
        let actions = c.handle(.shutdown, now: now)
        XCTAssertTrue(actions.contains(.cancelSystemAttachedProbe))
        guard case .idle = c.phase else { return XCTFail("shutdown 必须 idle") }
        XCTAssertNotEqual(c.systemAttachedProbeToken, token)
        XCTAssertEqual(
            c.handle(.systemAttachedProbeFired(token: token), now: now),
            [],
            "shutdown 后过期 probe 不得 retrieve/connect"
        )
        XCTAssertEqual(c.handle(.systemAttachedProbeEmpty, now: now), [])
        XCTAssertEqual(c.handle(.lookupOrConnectFailed, now: now), [])
    }

    func testLookupOrConnectFailed_returnsToScanning_andRearmsOnce() {
        var c = makeCore()
        _ = c.handle(.bluetoothPoweredOn, now: now)
        _ = c.handle(.lockAcquired, now: now)
        _ = c.handle(.systemAttachedDeviceFound(uuid: "UUID-S"), now: now)
        guard case .connecting = c.phase else { return XCTFail() }
        let actions = c.handle(.lookupOrConnectFailed, now: now)
        XCTAssertEqual(
            actions,
            [
                .resumeScanning,
                .scheduleSystemAttachedProbe(
                    after: DeviceTransportCore.systemAttachedProbeInterval,
                    token: c.systemAttachedProbeToken
                ),
            ]
        )
        guard case .scanning = c.phase else { return XCTFail("失败必须回 scanning，不得留在 connecting") }
    }
}
