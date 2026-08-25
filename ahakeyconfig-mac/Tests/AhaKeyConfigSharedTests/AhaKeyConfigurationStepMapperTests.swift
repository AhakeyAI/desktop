import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 4：步骤 → 线协议程序映射测试。
final class AhaKeyConfigurationStepMapperTests: XCTestCase {

    private typealias Mapper = AhaKeyConfigurationStepMapper

    private func resource(_ id: String) -> AhaKeyResourceIdentifier { try! .init(id) }
    private func digest() -> AhaKeySHA256Digest { try! .init(String(repeating: "a", count: 64)) }

    private func capabilities(sessionUpload: Bool = true, factorySlotBase: Int = 10) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: 2, stateCount: 4,
            flags: sessionUpload ? AhaKeyFirmwareCapabilities.sessionUploadFlag : 0,
            maxPacketSize: 200, userSlotLimit: 8, factorySlotBase: factorySlotBase,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    // MARK: 槽位布局

    func testSlotLayoutDeterministic() {
        let layout = AhaKeyDeviceLayoutPolicy()
        XCTAssertEqual(layout.startFrameIndex(slot: 0, factorySlotBase: 10), 10)
        XCTAssertEqual(layout.startFrameIndex(slot: 1, factorySlotBase: 10), 40)
        XCTAssertEqual(layout.startFrameIndex(slot: 2, factorySlotBase: 10), 70)
    }

    // MARK: 资源上传程序

    func testResourceUploadProgramAddressesAndChunks() {
        // 2 帧 × 编码 25600B → 每帧 7 块（⌈25600/4096⌉=7，末块 1024），共 14 对 prepare+chunk
        let steps = Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 2,
            usesSessionUpload: true, capabilities: capabilities()
        )
        XCTAssertEqual(steps.count, 28)
        guard case .prepareWrite(let session, let len, let addr) = steps.first else {
            return XCTFail("首步应为 prepareWrite")
        }
        XCTAssertNotNil(session)          // 会话式
        XCTAssertEqual(len, 4096)
        XCTAssertEqual(addr, 10 * 28_672) // slot0 首帧地址（flash 槽 28672B 步长）
        XCTAssertEqual(addr % 4096, 0, "地址必须扇区对齐")
        // session 按 chunk 轮换（对齐 Studio 生产路径）
        guard case .prepareWrite(let session2, _, _) = steps[2] else {
            return XCTFail("第二块应为 prepareWrite")
        }
        XCTAssertNotNil(session2)
        XCTAssertNotEqual(session, session2, "每块独立会话，失败可精确回滚当前块")
        // 第二帧地址 = (10+1)*28672
        let secondFramePrepare = steps[14]
        guard case .prepareWrite(_, _, let addr2) = secondFramePrepare else {
            return XCTFail("第二帧首步应为 prepareWrite")
        }
        XCTAssertEqual(addr2, 11 * 28_672)
        // 帧内末块 = 25600 % 4096 = 1024，且 chunk offset 索引编码流
        guard case .writeResourceChunk(_, let chunkOffset, let chunkLen) = steps[13] else {
            return XCTFail("chunk 步类型错误")
        }
        XCTAssertEqual(chunkOffset, 6 * 4096)
        XCTAssertEqual(chunkLen, 1024)
    }

    func testResourceUploadProgramLegacyPrepareWithoutSession() {
        let steps = Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 1,
            usesSessionUpload: false, capabilities: capabilities(sessionUpload: false)
        )
        guard case .prepareWrite(let session, _, _) = steps.first else {
            return XCTFail("首步应为 prepareWrite")
        }
        XCTAssertNil(session)
    }

    func testResourceUploadProgramCapsFramesAtSlotLimit() {
        // 声明 70 帧但槽位上限 30：程序只排 30 帧（声明超限由 planner 拒绝兜底）
        let steps = Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 70,
            usesSessionUpload: false, capabilities: capabilities(sessionUpload: false)
        )
        let prepares = steps.filter { if case .prepareWrite = $0 { return true }; return false }
        XCTAssertEqual(prepares.count, 30 * 7)
    }

    // MARK: base 配置程序

    private func modeWithEverything() throws -> (AhaKeyDesiredConfiguration, AhaKeyConfigurationPlanner.Plan) {
        let keys: [AhaKeyDesiredConfiguration.Key] = [
            .init(role: .approve, action: .shortcut(try! .init(modifiers: ["command"], keyCode: 0x28)),
                  description: "Accept"),
            .init(role: .reject, action: .macro([try! .init(action: 1, param: 0x51)]),
                  description: ""),
        ]
        let done = try AhaKeyDesiredConfiguration.TaskAsset(
            state: .done, resource: resource("img-a"),
            framesPerSecond: 10, pixelWidth: 160, pixelHeight: 80, declaredFrameCount: 12
        )
        let working = try AhaKeyDesiredConfiguration.TaskAsset(
            state: .working, resource: resource("img-b"),
            framesPerSecond: 20, pixelWidth: 160, pixelHeight: 80, declaredFrameCount: 30
        )
        // idle 无资源 → 应回退 working
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            done, working, try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 1
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(
            stateMappings: [try! .init(state: 1, effect: "approvalWait")], brightness: 55
        )
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 2, keys: keys, oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        let plan = AhaKeyConfigurationPlanner.Plan(
            transactions: [],
            slotAssignments: [resource("img-a"): 0, resource("img-b"): 1]
        )
        return (desired, plan)
    }

    func testBaseProgramContainsKeyLightBindActivateFinishSave() throws {
        let (desired, plan) = try modeWithEverything()
        let steps = Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan, capabilities: capabilities()
        )
        // 键位：approve shortcut（⌘+Enter = E3 28）、reject macro、approve description
        XCTAssertTrue(steps.contains(.setKeyShortcut(mode: 2, keyIndex: 1, hidCodes: [0xE3, 0x28])))
        XCTAssertTrue(steps.contains(.setKeyMacro(mode: 2, keyIndex: 2, pairs: [1, 0x51])))
        XCTAssertTrue(steps.contains(.setKeyDescription(mode: 2, keyIndex: 1, text: "Accept")))
        XCTAssertFalse(steps.contains(.setKeyDescription(mode: 2, keyIndex: 2, text: "")))
        // 灯效：state1=approvalWait(4)，其余 off；亮度 55
        XCTAssertTrue(steps.contains(.setLightMapping(mode: 2, effects: [0, 4, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertTrue(steps.contains(.setBrightness(55)))
        // 绑定：done→slot0(帧10起,12帧,100ms)，working→slot1(帧40起,30帧,50ms 下限 33→50)，idle 回退 working
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 2,
                                                      startIndex: 10, frameCount: 12, intervalMs: 100)))
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 1,
                                                      startIndex: 40, frameCount: 30, intervalMs: 50)))
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 0,
                                                      startIndex: 40, frameCount: 30, intervalMs: 50)))
        // 激活套图 1 + finish + save 收尾
        XCTAssertTrue(steps.contains(.setActiveTaskPictureSet(mode: 2, set: 1)))
        XCTAssertEqual(steps.dropLast(2).last, .setActiveTaskPictureSet(mode: 2, set: 1))
        XCTAssertEqual(steps.dropLast(1).last, .finishTaskPictureWrite)
        XCTAssertEqual(steps.last, .saveConfig)
    }

    // MARK: 步骤分发

    func testProgramDispatchForResourceAndBaseSteps() throws {
        let (desired, plan) = try modeWithEverything()
        let metas = [
            try! AhaKeyConfigurationResource(logicalIdentifier: "img-a",
                sha256: String(repeating: "a", count: 64), byteCount: 12 * 25_600, mediaType: "gif"),
            try! AhaKeyConfigurationResource(logicalIdentifier: "img-b",
                sha256: String(repeating: "b", count: 64), byteCount: 30 * 25_600, mediaType: "gif"),
        ]
        let resourceProgram = Mapper.program(
            for: try! .init("resource:img-a"), desired: desired, plan: plan,
            resources: metas, capabilities: capabilities()
        )
        XCTAssertNotNil(resourceProgram)
        XCTAssertFalse(resourceProgram!.isEmpty)
        // 分块由声明帧数（12）× 固定编码长度决定，与 CAS 源 byteCount 无关
        let prepares = resourceProgram!.filter { if case .prepareWrite = $0 { return true }; return false }
        XCTAssertEqual(prepares.count, 12 * 7)
        let baseProgram = Mapper.program(
            for: try! .init("base:mode:2"), desired: desired, plan: plan,
            resources: metas, capabilities: capabilities()
        )
        XCTAssertNotNil(baseProgram)
        XCTAssertNil(Mapper.program(
            for: try! .init("base:mode:9"), desired: desired, plan: plan,
            resources: metas, capabilities: capabilities()
        ))
        XCTAssertNil(Mapper.program(
            for: try! .init("bogus"), desired: desired, plan: plan,
            resources: metas, capabilities: capabilities()
        ))
    }

    // MARK: 修饰键顺序

    func testShortcutModifierOrderIsCanonical() {
        let shortcut = try! AhaKeyDesiredConfiguration.Shortcut(
            modifiers: ["command", "control", "shift"], keyCode: 0x04
        )
        XCTAssertEqual(Mapper.shortcutHidCodes(shortcut), [0xE0, 0xE1, 0xE3, 0x04])
    }
}
