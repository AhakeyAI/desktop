import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class AhaKeySystemAttachedProbeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let prefix = "AhaKey"

    func testEmptyProbe_producesNoLog_andReschedulesViaCore() {
        let decision = AhaKeySystemAttachedProbe.decide(
            attached: [
                .init(name: "Keyboard K380", uuid: "OTHER"),
            ],
            namePrefix: prefix
        )
        XCTAssertEqual(decision, .miss)
        XCTAssertNil(AhaKeySystemAttachedProbe.logMessage(for: decision), "空 probe 零常规日志")

        var core = DeviceTransportCore(sessionGeneration: 1)
        _ = core.handle(.bluetoothPoweredOn, now: now)
        _ = core.handle(.lockAcquired, now: now)
        _ = core.handle(.systemAttachedProbeFired(token: core.systemAttachedProbeToken), now: now)
        let actions = core.handle(.systemAttachedProbeEmpty, now: now)
        XCTAssertEqual(
            actions,
            [
                .scheduleSystemAttachedProbe(
                    after: DeviceTransportCore.systemAttachedProbeInterval,
                    token: core.systemAttachedProbeToken
                ),
            ]
        )
        guard case .scanning = core.phase else { return XCTFail() }
    }

    func testSystemAttachedHit_entersProductionConnectChainOnce() {
        let uuid = "UUID-X1"
        let decision = AhaKeySystemAttachedProbe.decide(
            attached: [
                .init(name: "AhaKey X1", uuid: uuid),
            ],
            namePrefix: prefix
        )
        XCTAssertEqual(decision, .hit(name: "AhaKey X1", uuid: uuid))
        XCTAssertEqual(
            AhaKeySystemAttachedProbe.logMessage(for: decision),
            "系统已连接: AhaKey X1"
        )

        var core = DeviceTransportCore(sessionGeneration: 1)
        _ = core.handle(.bluetoothPoweredOn, now: now)
        _ = core.handle(.lockAcquired, now: now)
        XCTAssertEqual(
            core.handle(.systemAttachedDeviceFound(uuid: uuid), now: now),
            [.cancelSystemAttachedProbe, .connectSystemAttached(uuid: uuid)]
        )
        XCTAssertEqual(
            core.handle(.systemAttachedDeviceFound(uuid: uuid), now: now),
            [],
            "命中后必须走同一条 connectSystemAttached 链且只连接一次"
        )
    }
}
