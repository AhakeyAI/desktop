import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 1：planner 纯函数边界测试。
final class AhaKeyConfigurationPlannerTests: XCTestCase {

    private func resource(_ id: String) -> AhaKeyResourceIdentifier { try! AhaKeyResourceIdentifier(id) }

    private func meta(_ id: String, bytes: UInt64 = 1024, mediaType: String = "gif") -> AhaKeyConfigurationResource {
        try! AhaKeyConfigurationResource(
            logicalIdentifier: id,
            sha256: String(repeating: "a", count: 64),
            byteCount: bytes,
            mediaType: mediaType
        )
    }

    private func capabilities(
        modeCount: Int = 4, setCount: Int = 2, stateCount: Int = 4, userSlotLimit: Int = 8
    ) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: modeCount, setCount: setCount, stateCount: stateCount,
            flags: 0, maxPacketSize: 200, userSlotLimit: userSlotLimit, factorySlotBase: 8,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private func asset(
        _ id: String?, state: AhaKeyDesiredConfiguration.TaskDisplayState = .done,
        w: Int? = 128, h: Int? = 128, frames: Int? = 8
    ) -> AhaKeyDesiredConfiguration.TaskAsset {
        try! .init(state: state, resource: id.map(resource), framesPerSecond: 12,
                   pixelWidth: w, pixelHeight: h, declaredFrameCount: frames)
    }

    private func desired(
        modeSlot: UInt8 = 0,
        assets: [AhaKeyDesiredConfiguration.TaskAsset]? = nil
    ) -> AhaKeyDesiredConfiguration {
        let taskAssets = assets ?? [asset("img-a")]
        let setA = try! AhaKeyDesiredConfiguration.TaskSet(assets: taskAssets)
        let setB = try! AhaKeyDesiredConfiguration.TaskSet(assets: [asset(nil, state: .idle, w: nil, h: nil, frames: nil)])
        let oled = try! AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try! AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try! AhaKeyDesiredConfiguration.Mode(slot: modeSlot, keys: [key], oled: oled, lightBar: lightBar)
        return try! AhaKeyDesiredConfiguration(modes: [mode])
    }

    // MARK: 通过路径

    func testValidConfigurationProducesResourceThenBaseTransactions() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [meta("img-a")],
            capabilities: capabilities(), protocolMode: .current
        )
        guard case .success(let plan) = result else { return XCTFail("应规划成功: \(result)") }
        XCTAssertEqual(plan.transactions.map(\.kind), [.resourceUpload, .baseConfiguration])
        XCTAssertEqual(plan.slotAssignments[resource("img-a")], 0)
        XCTAssertEqual(plan.transactions[1].modeSlots, [0])
    }

    func testDuplicateResourceReferenceGetsSingleSlot() {
        let d = desired(assets: [asset("img-a"), asset("img-a", state: .working)])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current
        )
        guard case .success(let plan) = result else { return XCTFail("应成功: \(result)") }
        XCTAssertEqual(plan.slotAssignments.count, 1)
        XCTAssertEqual(plan.transactions[0].uploads.count, 1)
    }

    // MARK: current-only

    func testRejectsNonCurrentProtocols() {
        for mode in [AhaKeyProtocolMode.legacy, .legacyBaseOnly, .negotiating, .restrictedUnknown] {
            let result = AhaKeyConfigurationPlanner.plan(
                desired: desired(), resources: [meta("img-a")],
                capabilities: capabilities(), protocolMode: mode
            )
            XCTAssertEqual(result, .failure(.unsupportedProtocol), "\(mode) 应拒绝")
        }
    }

    // MARK: 结构对账

    func testRejectsModeSlotBeyondDevice() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(modeSlot: 3), resources: [meta("img-a")],
            capabilities: capabilities(modeCount: 2), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.modeSlotExceedsDevice(slot: 3, deviceModeCount: 2)))
    }

    func testRejectsTaskStateBeyondDevice() {
        // stateCount=2 的设备不认 done(2)
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", state: .done)]),
            resources: [meta("img-a")],
            capabilities: capabilities(stateCount: 2), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.taskStateUnsupported(state: 2, deviceStateCount: 2)))
    }

    // MARK: 资源校验

    func testRejectsMissingResource() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [], capabilities: capabilities(), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.missingResource(resource("img-a"))))
    }

    func testRejectsDisallowedMediaType() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [meta("img-a", mediaType: "png")],
            capabilities: capabilities(), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.disallowedMediaType(resource("img-a"), "png")))
    }

    func testRejectsOversizedAsset() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [meta("img-a", bytes: 3 * 1024 * 1024)],
            capabilities: capabilities(), protocolMode: .current
        )
        guard case .failure(.assetTooLarge(let id, let bytes, _)) = result else {
            return XCTFail("应拒绝超大资源: \(result)")
        }
        XCTAssertEqual(id, resource("img-a"))
        XCTAssertEqual(bytes, 3 * 1024 * 1024)
    }

    func testRejectsTooManyFrames() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", frames: 200)]),
            resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.tooManyFrames(resource("img-a"), frames: 200, limit: 120)))
    }

    func testRejectsDecodeMemoryOverflow() {
        // 512×512×4B×100帧 = 100 MiB > 16 MiB
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", w: 512, h: 512, frames: 100)]),
            resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current
        )
        guard case .failure(.decodeMemoryExceeded(let id, _, _)) = result else {
            return XCTFail("应拒绝解码内存超限: \(result)")
        }
        XCTAssertEqual(id, resource("img-a"))
    }

    // MARK: 设备容量

    func testRejectsCapacityOverflow() {
        let d = desired(assets: [
            asset("img-a"), asset("img-b", state: .working), asset("img-c", state: .idle),
        ])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d,
            resources: [meta("img-a"), meta("img-b"), meta("img-c")],
            capabilities: capabilities(userSlotLimit: 2), protocolMode: .current
        )
        XCTAssertEqual(result, .failure(.deviceCapacityExceeded(resources: 3, slots: 2)))
    }

    func testSlotAssignmentIsDeterministic() {
        let d = desired(assets: [asset("img-b"), asset("img-a", state: .working)])
        let resources = [meta("img-b"), meta("img-a")]
        let r1 = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: resources, capabilities: capabilities(), protocolMode: .current)
        let r2 = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: resources.reversed(), capabilities: capabilities(), protocolMode: .current)
        guard case .success(let p1) = r1, case .success(let p2) = r2 else {
            return XCTFail("两次规划都应成功")
        }
        XCTAssertEqual(p1.slotAssignments, p2.slotAssignments)
        XCTAssertEqual(p1.slotAssignments[resource("img-a")], 0)
        XCTAssertEqual(p1.slotAssignments[resource("img-b")], 1)
    }
}
