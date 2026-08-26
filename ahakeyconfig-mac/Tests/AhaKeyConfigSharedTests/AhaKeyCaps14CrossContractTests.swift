import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.7 R2 caps14 交叉契约（固件证据：WBS-1-UNIFIED-FIRMWARE 22:51，
/// `tp_write_caps14` 精确 payload `03 04 02 04 33 00 c8 00 20 01 00 00 00 00`）：
/// factory flag 关闭的 14 字节能力帧 → factorySlotBase=0、userSlotLimit=288；
/// factory flag 打开但仅 14 字节 → parse fail-closed；
/// planner 首个/末个合法槽位不越界，288 帧上限越界必须拒绝。
final class AhaKeyCaps14CrossContractTests: XCTestCase {

    /// 固件 1.3 `tp_write_caps14` 精确 fixture：protocol=3 mode=4 set=2 state=4，
    /// flags=0x0033（idle=bit0 开；factory=bit2 关；session=bit3 关），
    /// maxPacket=200，userSlotLimit=288，无扩展字段。
    private let caps14Payload = Data([
        0x03, 0x04, 0x02, 0x04,
        0x33, 0x00,
        0xC8, 0x00,
        0x20, 0x01,
        0x00, 0x00, 0x00, 0x00,
    ])

    // MARK: - 解析

    func testCaps14FixtureParsesFactoryOffWithZeroBase() {
        let capabilities = AhaKeyFirmwareCapabilities.parse(caps14Payload)

        XCTAssertEqual(capabilities?.protocolVersion, 3)
        XCTAssertEqual(capabilities?.modeCount, 4)
        XCTAssertEqual(capabilities?.setCount, 2)
        XCTAssertEqual(capabilities?.stateCount, 4)
        XCTAssertEqual(capabilities?.flags, 0x0033)
        XCTAssertEqual(capabilities?.maxPacketSize, 200)
        XCTAssertEqual(capabilities?.userSlotLimit, 288)
        // 交叉契约核心：factory flag 关闭 → factorySlotBase=0（用户槽位从 0 起编），
        // 不得回退为 userSlotLimit（否则 planner 从容量末端分配，0x95 全部被固件越界拒绝）。
        XCTAssertEqual(capabilities?.factorySlotBase, 0)
        XCTAssertEqual(capabilities?.factoryBundleVersion, 0)
        XCTAssertEqual(capabilities?.factoryManifestCRC, 0)
        XCTAssertEqual(capabilities?.factoryStatus, 0)
        XCTAssertEqual(capabilities?.factoryError, 0)
        XCTAssertTrue(capabilities?.supportsIdleTaskPicture == true)
        XCTAssertFalse(capabilities?.supportsSessionUpload ?? true)
    }

    func testCaps14WithFactoryFlagOnFailsClosed() {
        // factory flag 打开（0x33 | 0x04 = 0x37）但帧仅 14 字节：parse 必须 fail-closed。
        var payload = caps14Payload
        payload[4] = 0x37
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(payload))
    }

    // MARK: - planner 交叉：槽位范围与越界拒绝

    private func resource(_ id: String) -> AhaKeyResourceIdentifier {
        try! AhaKeyResourceIdentifier(id)
    }

    private func meta(_ id: String) -> AhaKeyConfigurationResource {
        try! AhaKeyConfigurationResource(
            logicalIdentifier: id,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1024,
            mediaType: "gif"
        )
    }

    private func asset(_ id: String, state: AhaKeyDesiredConfiguration.TaskDisplayState, frames: Int = 30) -> AhaKeyDesiredConfiguration.TaskAsset {
        try! .init(state: state, resource: resource(id), framesPerSecond: 12,
                   pixelWidth: 128, pixelHeight: 128, declaredFrameCount: frames)
    }

    /// 每个模式最多 8 个独立资源（套图 A/B 各 4 状态）；defaultAnimation 有镜像约束，本测试不用。
    private func desired(modeSlot: UInt8, ids: [String]) throws -> AhaKeyDesiredConfiguration.Mode {
        var remaining = ids
        func take() -> String? { remaining.isEmpty ? nil : remaining.removeFirst() }
        let states: [AhaKeyDesiredConfiguration.TaskDisplayState] = [.idle, .working, .waiting, .done]
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: states.map { state in
            if let id = take() { return asset(id, state: state) }
            return try! .init(state: state, resource: nil, framesPerSecond: 12,
                              pixelWidth: nil, pixelHeight: nil, declaredFrameCount: nil)
        })
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: states.map { state in
            if let id = take() { return asset(id, state: state) }
            return try! .init(state: state, resource: nil, framesPerSecond: 12,
                              pixelWidth: nil, pixelHeight: nil, declaredFrameCount: nil)
        })
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil,
            statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 0
        )
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        return try AhaKeyDesiredConfiguration.Mode(slot: modeSlot, keys: [key], oled: oled, lightBar: lightBar)
    }

    /// caps14 解析结果直接作为 planner 输入（生产同路径）。
    private func caps14() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities.parse(caps14Payload)!
    }

    func testPlannerSlotRangeWithinUserSlotLimit() throws {
        // 9 个资源 × 30 帧（= framesPerSlot）→ 占 9 槽 = 270 帧 ≤ 288。
        let ids = (1 ... 9).map { String(format: "r%02d", $0) }
        let mode0 = try desired(modeSlot: 0, ids: Array(ids.prefix(8)))
        let mode1 = try desired(modeSlot: 1, ids: ["r09"])
        let desiredConfig = try AhaKeyDesiredConfiguration(modes: [mode0, mode1])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desiredConfig, resources: ids.map(meta),
            capabilities: caps14(), protocolMode: .current
        )
        guard case .success(let plan) = result else {
            return XCTFail("caps14 下 9 槽必须规划成功: \(result)")
        }
        // 首个合法槽位：slot 0 → 设备帧 0（factorySlotBase=0 起编）。
        XCTAssertEqual(plan.slotAssignments[resource("r01")], 0)
        let layout = AhaKeyDeviceLayoutPolicy()
        XCTAssertEqual(layout.startFrameIndex(slot: 0, factorySlotBase: caps14().factorySlotBase), 0)
        // 末个合法槽位：slot 8 → 起始帧 240，结束帧 270 ≤ userSlotLimit 288。
        XCTAssertEqual(plan.slotAssignments[resource("r09")], 8)
        let lastStart = Int(layout.startFrameIndex(slot: 8, factorySlotBase: caps14().factorySlotBase))
        XCTAssertEqual(lastStart, 240)
        XCTAssertLessThanOrEqual(lastStart + layout.framesPerSlot, caps14().userSlotLimit)
    }

    func testPlannerRejectsBeyondUserSlotLimit288() throws {
        // 10 槽 × 30 帧 = 300 帧 > 288：必须 deviceCapacityExceeded 拒绝（越界 0x95 不被固件接受）。
        let ids = (1 ... 10).map { String(format: "r%02d", $0) }
        let mode0 = try desired(modeSlot: 0, ids: Array(ids.prefix(8)))
        let mode1 = try desired(modeSlot: 1, ids: ["r09", "r10"])
        let desiredConfig = try AhaKeyDesiredConfiguration(modes: [mode0, mode1])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desiredConfig, resources: ids.map(meta),
            capabilities: caps14(), protocolMode: .current
        )
        XCTAssertEqual(
            result,
            .failure(.deviceCapacityExceeded(slotsNeeded: 300, slotLimit: 288)),
            "占用 300 帧必须越过 userSlotLimit=288 被拒绝"
        )
    }

    func testPlannerWithLegacyFallbackBaseWouldOverflow() throws {
        // 回归对照：旧行为把 14 字节帧的 factorySlotBase 回退为 userSlotLimit(288)，
        // 末槽起始帧将是 288 + 240 = 528，必然被固件越界拒绝——证明本修复是必要条件。
        XCTAssertEqual(caps14().factorySlotBase, 0, "caps14 必须解析为 0，不得回退 288")
        let layout = AhaKeyDeviceLayoutPolicy()
        let legacyLastStart = Int(layout.startFrameIndex(slot: 8, factorySlotBase: 288))
        XCTAssertGreaterThan(legacyLastStart, caps14().userSlotLimit)
    }
}
