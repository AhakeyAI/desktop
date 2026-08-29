import CryptoKit
import ImageIO
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
        modeCount: Int = 4, setCount: Int = 2, stateCount: Int = 4, userSlotLimit: Int = 288
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
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success(let plan) = result else { return XCTFail("应规划成功: \(result)") }
        XCTAssertEqual(plan.transactions.map(\.kind), [.resourceUpload, .baseConfiguration])
        XCTAssertEqual(plan.slotAssignments[resource("img-a")], 0)
        XCTAssertEqual(plan.transactions[1].modeSlots, [0])
    }

    func testBaseModeSlotsRunPictureModesBeforeEmptyOledModes() {
        let withPic = desired(modeSlot: 1, assets: [asset("img-a")])
        let emptyAssets: [AhaKeyDesiredConfiguration.TaskAsset] = [
            asset(nil, state: .idle, w: nil, h: nil, frames: nil),
            asset(nil, state: .working, w: nil, h: nil, frames: nil),
            asset(nil, state: .waiting, w: nil, h: nil, frames: nil),
            asset(nil, state: .done, w: nil, h: nil, frames: nil),
        ]
        let empty = desired(modeSlot: 0, assets: emptyAssets)
        let combined = try! AhaKeyDesiredConfiguration(modes: empty.modes + withPic.modes)
        let result = AhaKeyConfigurationPlanner.plan(
            desired: combined, resources: [meta("img-a")],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success(let plan) = result else { return XCTFail("应规划成功: \(result)") }
        XCTAssertEqual(plan.transactions[1].modeSlots, [1, 0])
    }

    func testDuplicateResourceReferenceGetsSingleSlot() {
        let d = desired(assets: [asset("img-a"), asset("img-a", state: .working)])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success(let plan) = result else { return XCTFail("应成功: \(result)") }
        XCTAssertEqual(plan.slotAssignments.count, 1)
        XCTAssertEqual(plan.transactions[0].uploads.count, 1)
    }

    // MARK: current-only

    func testRejectsNonCurrentProtocols() {
        for mode in [AhaKeyProtocolMode.legacy, .legacyBaseOnly, .negotiating, .restrictedUnknown] {
            let result = AhaKeyConfigurationPlanner.plan(
                desired: desired(), resources: [meta("img-a")],
                capabilities: capabilities(), protocolMode: mode, release: .picturesUnrestrictedForTests)
            XCTAssertEqual(result, .failure(.unsupportedProtocol), "\(mode) 应拒绝")
        }
    }

    // MARK: 结构对账

    func testRejectsModeSlotBeyondDevice() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(modeSlot: 3), resources: [meta("img-a")],
            capabilities: capabilities(modeCount: 2), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.modeSlotExceedsDevice(slot: 3, deviceModeCount: 2)))
    }

    func testRejectsTaskStateBeyondDevice() {
        // stateCount=2 的设备不认 done(3)
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", state: .done)]),
            resources: [meta("img-a")],
            capabilities: capabilities(stateCount: 2), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.taskStateUnsupported(state: 3, deviceStateCount: 2)))
    }

    // MARK: 资源校验

    func testRejectsMissingResource() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [], capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.missingResource(resource("img-a"))))
    }

    func testRejectsDisallowedMediaType() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [meta("img-a", mediaType: "png")],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.disallowedMediaType(resource("img-a"), "png")))
    }

    func testRejectsOversizedAsset() {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(), resources: [meta("img-a", bytes: 3 * 1024 * 1024)],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .failure(.assetTooLarge(let id, let bytes, _)) = result else {
            return XCTFail("应拒绝超大资源: \(result)")
        }
        XCTAssertEqual(id, resource("img-a"))
        XCTAssertEqual(bytes, 3 * 1024 * 1024)
    }

    func testRejectsTooManyFrames() {
        // 帧上限与上传/绑定同一口径（30）：声明 31 即拒绝，绝不静默截断
        let r30 = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", frames: 30)]),
            resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success = r30 else { return XCTFail("30 帧应通过: \(r30)") }
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", frames: 31)]),
            resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.tooManyFrames(resource("img-a"), frames: 31, limit: 30)))
    }

    func testRejectsDecodeMemoryOverflow() {
        // 512×512×4B×30帧 = 30 MiB > 16 MiB（帧数在上限内，专测解码内存维度）
        let result = AhaKeyConfigurationPlanner.plan(
            desired: desired(assets: [asset("img-a", w: 512, h: 512, frames: 30)]),
            resources: [meta("img-a")], capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
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
            capabilities: capabilities(userSlotLimit: 23), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.deviceCapacityExceeded(slotsNeeded: 90, slotLimit: 23)))
    }

    func testSlotAssignmentIsDeterministic() {
        let d = desired(assets: [asset("img-b"), asset("img-a", state: .working)])
        let resources = [meta("img-b"), meta("img-a")]
        let r1 = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: resources, capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        let r2 = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: resources.reversed(), capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success(let p1) = r1, case .success(let p2) = r2 else {
            return XCTFail("两次规划都应成功")
        }
        XCTAssertEqual(p1.slotAssignments, p2.slotAssignments)
        XCTAssertEqual(p1.slotAssignments[resource("img-a")], 0)
        XCTAssertEqual(p1.slotAssignments[resource("img-b")], 1)
    }

    // MARK: 容量按帧占用 + defaultAnimation（返工 R4/R6）

    private func desiredWithDefault(frames: Int, extraAssets: [AhaKeyDesiredConfiguration.TaskAsset] = []) -> AhaKeyDesiredConfiguration {
        var taskAssets = extraAssets
        if taskAssets.isEmpty { taskAssets = [asset(nil, state: .done, w: nil, h: nil, frames: nil)] }
        let setA = try! AhaKeyDesiredConfiguration.TaskSet(assets: taskAssets)
        let setB = try! AhaKeyDesiredConfiguration.TaskSet(assets: [asset(nil, state: .idle, w: nil, h: nil, frames: nil)])
        let oled = try! AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: resource("img-default"), defaultAnimationFrames: frames,
            statusLine: "", framesPerSecond: 12, taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try! AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try! AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        return try! AhaKeyDesiredConfiguration(modes: [mode])
    }

    func testCapacityCountsDefaultAnimationFrames() {
        // defaultAnimation(30帧) + task asset(30帧) = 60 帧 > 59 帧上限
        let d = desiredWithDefault(frames: 30, extraAssets: [asset("img-a", frames: 30)])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: [meta("img-default"), meta("img-a")],
            capabilities: capabilities(userSlotLimit: 59), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.deviceCapacityExceeded(slotsNeeded: 60, slotLimit: 59)))
    }

    func testDefaultAnimationResourceGetsProgramSlot() {
        let d = desiredWithDefault(frames: 30, extraAssets: [asset("img-a", frames: 30)])
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: [meta("img-a"), meta("img-default")],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        guard case .success(let plan) = result else { return XCTFail("应成功: \(result)") }
        // 两个资源各占一槽，槽位按标识符排序确定
        XCTAssertEqual(plan.slotAssignments[resource("img-a")], 0)
        XCTAssertEqual(plan.slotAssignments[resource("img-default")], 1)
    }

    func testRejectsDefaultAnimationOverFrameLimit() {
        let d = desiredWithDefault(frames: 31)
        let result = AhaKeyConfigurationPlanner.plan(
            desired: d, resources: [meta("img-default")],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.tooManyFrames(resource("img-default"), frames: 31, limit: 30)))
    }

    func testRejectsIdleAnimationMismatch() {
        // idle 任务素材带 resource 且与 defaultAnimation 不是同一 CAS 引用 → 拒绝
        let setA = try! AhaKeyDesiredConfiguration.TaskSet(assets: [
            asset("img-working", state: .working),
            asset("img-idle", state: .idle)
        ])
        let setB = try! AhaKeyDesiredConfiguration.TaskSet(assets: [asset(nil, state: .idle, w: nil, h: nil, frames: nil)])
        let oled = try! AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: resource("img-default"), defaultAnimationFrames: 8,
            statusLine: "", framesPerSecond: 12, taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try! AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try! AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        let d = try! AhaKeyDesiredConfiguration(modes: [mode])

        let result = AhaKeyConfigurationPlanner.plan(
            desired: d,
            resources: [meta("img-default"), meta("img-working"), meta("img-idle")],
            capabilities: capabilities(), protocolMode: .current, release: .picturesUnrestrictedForTests)
        XCTAssertEqual(result, .failure(.idleAnimationMismatch(
            idle: resource("img-idle"), defaultAnimation: resource("img-default"))))
    }

    // MARK: 受理校验以 CAS 实际数据为准（返工 R5）

    private func makeGIFData(width: Int = 128, height: Int = 128, frames: Int = 8) -> Data {
        let buffer = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            buffer, "com.compuserve.gif" as CFString, frames, nil
        )!
        for _ in 0 ..< frames {
            var rgba = [UInt8](repeating: 200, count: width * height * 4)
            let context = CGContext(
                data: &rgba, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        }
        CGImageDestinationFinalize(destination)
        return buffer as Data
    }

    private func packageAndInputs(
        declaredFrames: Int = 8, declaredWidth: Int = 128, declaredHeight: Int = 128,
        actualContents: Data? = nil
    ) throws -> (AhaKeyConfigurationPackage, [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput]) {
        let contents = actualContents ?? makeGIFData()
        let desiredConfig = desired(assets: [asset(
            "img-a", w: declaredWidth, h: declaredHeight, frames: declaredFrames
        )])
        let sha = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        let resourceMeta = try AhaKeyConfigurationResource(
            logicalIdentifier: "img-a", sha256: sha,
            byteCount: UInt64(contents.count), mediaType: "gif"
        )
        let package = try AhaKeyConfigurationPackage(
            targetDeviceID: .init("4F3E"), baseRevision: .init(0),
            desiredConfiguration: desiredConfig.canonicalData(),
            resources: [resourceMeta]
        )
        let inputs: [AhaKeyResourceIdentifier: AhaKeyRuntimeResourceValidationInput] = [
            resource("img-a"): AhaKeyRuntimeResourceValidationInput(resource: resourceMeta, contents: contents)
        ]
        return (package, inputs)
    }

    func testValidatorAcceptsMatchingCASMetadata() throws {
        let (package, inputs) = try packageAndInputs()
        XCTAssertNoThrow(
            try AhaKeyConfigurationPlanner.AcceptanceValidator().validate(package: package, resources: inputs)
        )
    }

    func testValidatorRejectsDeclaredFrameMismatch() throws {
        let (package, inputs) = try packageAndInputs(declaredFrames: 7)  // 实际 8 帧
        XCTAssertThrowsError(
            try AhaKeyConfigurationPlanner.AcceptanceValidator().validate(package: package, resources: inputs)
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .resourceMetadataMismatch("img-a"))
        }
    }

    func testValidatorRejectsDeclaredDimensionMismatch() throws {
        let (package, inputs) = try packageAndInputs(declaredWidth: 64)  // 实际 128
        XCTAssertThrowsError(
            try AhaKeyConfigurationPlanner.AcceptanceValidator().validate(package: package, resources: inputs)
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .resourceMetadataMismatch("img-a"))
        }
    }

    func testValidatorRejectsUndecodableContents() throws {
        let (package, inputs) = try packageAndInputs(actualContents: Data(repeating: 0xAB, count: 64))
        XCTAssertThrowsError(
            try AhaKeyConfigurationPlanner.AcceptanceValidator().validate(package: package, resources: inputs)
        ) { error in
            XCTAssertEqual(error as? AhaKeyRuntimePersistenceError, .resourceMetadataMismatch("img-a"))
        }
    }
}
