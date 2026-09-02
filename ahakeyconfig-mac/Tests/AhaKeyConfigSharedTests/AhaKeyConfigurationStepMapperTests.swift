import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 4：步骤 → 线协议程序映射测试。
final class AhaKeyConfigurationStepMapperTests: XCTestCase {

    private typealias Mapper = AhaKeyConfigurationStepMapper

    private func resource(_ id: String) -> AhaKeyResourceIdentifier { try! .init(id) }
    private func digest() -> AhaKeySHA256Digest { try! .init(String(repeating: "a", count: 64)) }

    private func capabilities(
        sessionUpload: Bool = true,
        factorySlotBase: Int = 10,
        setCount: Int = 2
    ) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: setCount, stateCount: 4,
            flags: sessionUpload ? AhaKeyFirmwareCapabilities.sessionUploadFlag : 0,
            maxPacketSize: 200, userSlotLimit: 288, factorySlotBase: factorySlotBase,
            factoryBundleVersion: 0, factoryManifestCRC: 0, factoryStatus: 0, factoryError: 0,
            reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    // MARK: 槽位布局

    func testSlotLayoutDeterministic() {
        let layout = AhaKeyDeviceLayoutPolicy()
        XCTAssertEqual(layout.startFrameIndex(slot: 0, userRegionBase: 0), 0)
        XCTAssertEqual(layout.startFrameIndex(slot: 1, userRegionBase: 0), 30)
        XCTAssertEqual(layout.startFrameIndex(slot: 2, userRegionBase: 0), 60)
    }

    // MARK: 资源上传程序

    func testResourceUploadProgramAddressesAndChunks() throws {
        // 2 帧 × 编码 25600B → 每帧 7 块（⌈25600/4096⌉=7，末块 1024），共 14 对 prepare+chunk
        let steps = try XCTUnwrap(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 2,
            usesSessionUpload: true, userSlotLimit: capabilities().userSlotLimit
        ))
        XCTAssertEqual(steps.count, 28)
        guard case .prepareWrite(let session, let len, let addr) = steps.first else {
            return XCTFail("首步应为 prepareWrite")
        }
        XCTAssertNotNil(session)          // 会话式
        XCTAssertEqual(len, 4096)
        XCTAssertEqual(addr, 0 * 28_672) // 用户区从 0 起编，不得用 factorySlotBase
        XCTAssertEqual(addr % 4096, 0, "地址必须扇区对齐")
        // session 按 chunk 轮换（对齐 Studio 生产路径）
        guard case .prepareWrite(let session2, _, _) = steps[2] else {
            return XCTFail("第二块应为 prepareWrite")
        }
        XCTAssertNotNil(session2)
        XCTAssertNotEqual(session, session2, "每块独立会话，失败可精确回滚当前块")
        // 第二帧地址 = (0+1)*28672
        let secondFramePrepare = steps[14]
        guard case .prepareWrite(_, _, let addr2) = secondFramePrepare else {
            return XCTFail("第二帧首步应为 prepareWrite")
        }
        XCTAssertEqual(addr2, 1 * 28_672)
        // 帧内末块 = 25600 % 4096 = 1024，且 chunk offset 索引编码流
        guard case .writeResourceChunk(_, let chunkOffset, let chunkLen) = steps[13] else {
            return XCTFail("chunk 步类型错误")
        }
        XCTAssertEqual(chunkOffset, 6 * 4096)
        XCTAssertEqual(chunkLen, 1024)
    }

    func testResourceUploadProgramLegacyPrepareWithoutSession() throws {
        let steps = try XCTUnwrap(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 1,
            usesSessionUpload: false, userSlotLimit: capabilities(sessionUpload: false).userSlotLimit
        ))
        guard case .prepareWrite(let session, _, _) = steps.first else {
            return XCTFail("首步应为 prepareWrite")
        }
        XCTAssertNil(session)
    }

    func testResourceUploadProgramCapsFramesAtSlotLimit() throws {
        // 声明 70 帧但槽位上限 30：程序只排 30 帧（声明超限由 planner 拒绝兜底）
        let steps = try XCTUnwrap(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 70,
            usesSessionUpload: false, userSlotLimit: capabilities(sessionUpload: false).userSlotLimit
        ))
        let prepares = steps.filter { if case .prepareWrite = $0 { return true }; return false }
        XCTAssertEqual(prepares.count, 30 * 7)
    }

    // MARK: base 配置程序

    private func modeWithEverything(
        activeSet: Int = 1
    ) throws -> (AhaKeyDesiredConfiguration, AhaKeyConfigurationPlanner.Plan) {
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
            taskSets: [setA, setB], activeSet: activeSet
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
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        // 键位：approve shortcut（⌘+Enter = E3 28）、reject macro、approve description
        XCTAssertTrue(steps.contains(.setKeyShortcut(mode: 2, keyIndex: 1, hidCodes: [0xE3, 0x28])))
        XCTAssertTrue(steps.contains(.setKeyMacro(mode: 2, keyIndex: 2, pairs: [1, 0x51])))
        XCTAssertTrue(steps.contains(.setKeyDescription(mode: 2, keyIndex: 1, text: "Accept")))
        XCTAssertFalse(steps.contains(.setKeyDescription(mode: 2, keyIndex: 2, text: "")))
        // 灯效：state1=approvalWait(4)，其余 off；亮度 55
        XCTAssertTrue(steps.contains(.setLightMapping(mode: 2, effects: [0, 4, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertTrue(steps.contains(.setBrightness(55)))
        // 绑定：done→slot0(帧0起,12帧,100ms)，working→slot1(帧30起,30帧,50ms 下限 33→50)，idle 回退 working
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 3,
                                                      startIndex: 0, frameCount: 12, intervalMs: 100)))
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 1,
                                                      startIndex: 30, frameCount: 30, intervalMs: 50)))
        XCTAssertTrue(steps.contains(.bindTaskPicture(mode: 2, set: 0, state: 0,
                                                      startIndex: 30, frameCount: 30, intervalMs: 50)))
        // save 先落盘，0x97 激活套图排最后。current 不在 base 步发 0x98。
        XCTAssertEqual(steps.dropLast(1).last, .saveConfig)
        XCTAssertEqual(steps.last, .setActiveTaskPictureSet(mode: 2, set: 1))
        XCTAssertFalse(steps.contains { if case .finishTaskPictureWrite = $0 { return true }; return false })
    }

    /// 0x97 写的是独立 EEPROM journal 环，被拒时不得回滚已落盘配置：save 必须严格早于 0x97。
    func testBaseProgramSavesBeforeActivatingTaskPictureSet() throws {
        let (desired, plan) = try modeWithEverything()
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        let saveIndex = try XCTUnwrap(steps.firstIndex(of: .saveConfig))
        let activateIndex = try XCTUnwrap(steps.firstIndex(of: .setActiveTaskPictureSet(mode: 2, set: 1)))
        XCTAssertLessThan(saveIndex, activateIndex)
        // 绑定必须早于 save，否则落盘的 key_bund 不含本次绑定。
        let lastBindIndex = try XCTUnwrap(steps.lastIndex { if case .bindTaskPicture = $0 { return true }; return false })
        XCTAssertLessThan(lastBindIndex, saveIndex)
    }

    /// 无资源绑定仍必须发 0x97：mapper 不得用 binds.isEmpty 猜测设备当前套图。
    func testEmptyOledBaseStillActivatesAndOmitsFinish() throws {
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: mode, desired: desired, plan: .init(transactions: [], slotAssignments: [:]),
            context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        XCTAssertFalse(steps.contains { if case .bindTaskPicture = $0 { return true }; return false })
        XCTAssertFalse(steps.contains { if case .finishTaskPictureWrite = $0 { return true }; return false })
        XCTAssertEqual(steps.dropLast(1).last, .saveConfig)
        XCTAssertEqual(steps.last, .setActiveTaskPictureSet(mode: 0, set: 0))
        let saveIndex = try XCTUnwrap(steps.firstIndex(of: .saveConfig))
        let activateIndex = try XCTUnwrap(steps.firstIndex(of: .setActiveTaskPictureSet(mode: 0, set: 0)))
        XCTAssertLessThan(saveIndex, activateIndex)
    }

    /// activeSet == -1 表示尚未同步基线，这是 desired 自己的状态，不是对设备当前套图的猜测。
    func testUnsyncedActiveSetOmitsActivateButStillSaves() throws {
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: -1
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try! .init(keyCode: 0x28)), description: "Yes"
        )
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: mode, desired: desired, plan: .init(transactions: [], slotAssignments: [:]),
            context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        XCTAssertFalse(steps.contains { if case .setActiveTaskPictureSet = $0 { return true }; return false })
        XCTAssertFalse(steps.contains { if case .finishTaskPictureWrite = $0 { return true }; return false })
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
            resources: metas, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests)
        XCTAssertNotNil(resourceProgram)
        XCTAssertFalse(resourceProgram!.isEmpty)
        // 分块由声明帧数（12）× 固定编码长度决定，与 CAS 源 byteCount 无关
        let prepares = resourceProgram!.filter { if case .prepareWrite = $0 { return true }; return false }
        XCTAssertEqual(prepares.count, 12 * 7)
        let baseProgram = Mapper.program(
            for: try! .init("base:mode:2"), desired: desired, plan: plan,
            resources: metas, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests)
        XCTAssertNotNil(baseProgram)
        XCTAssertNil(Mapper.program(
            for: try! .init("base:mode:9"), desired: desired, plan: plan,
            resources: metas, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        XCTAssertNil(Mapper.program(
            for: try! .init("bogus"), desired: desired, plan: plan,
            resources: metas, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
    }

    // MARK: 修饰键顺序

    func testShortcutModifierOrderIsCanonical() {
        let shortcut = try! AhaKeyDesiredConfiguration.Shortcut(
            modifiers: ["command", "control", "shift"], keyCode: 0x04
        )
        XCTAssertEqual(Mapper.shortcutHidCodes(shortcut), [0xE0, 0xE1, 0xE3, 0x04])
    }

    // MARK: defaultAnimation（返工 R6：资源程序 + 0x82 绑定语义）

    private func modeWithDefaultAnimation() throws -> (AhaKeyDesiredConfiguration, AhaKeyConfigurationPlanner.Plan) {
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: resource("img-default"), defaultAnimationFrames: 8,
            statusLine: "", framesPerSecond: 12, taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 50)
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [], oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        let plan = AhaKeyConfigurationPlanner.Plan(
            transactions: [], slotAssignments: [resource("img-default"): 0]
        )
        return (desired, plan)
    }

    func testDefaultAnimationHasResourceProgram() throws {
        let (desired, plan) = try modeWithDefaultAnimation()
        let metas = [try! AhaKeyConfigurationResource(
            logicalIdentifier: "img-default",
            sha256: String(repeating: "a", count: 64), byteCount: 12345, mediaType: "gif"
        )]
        let program = Mapper.program(
            for: try! .init("resource:img-default"), desired: desired, plan: plan,
            resources: metas, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests)
        // 不得因 mapper 只搜 task asset 而永久失败；8 帧 × 7 块
        let prepares = program?.filter { if case .prepareWrite = $0 { return true }; return false }
        XCTAssertEqual(prepares?.count, 8 * 7)
    }

    func testDefaultAnimationBindingInBaseProgram() throws {
        let (desired, plan) = try modeWithDefaultAnimation()
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan, context: .parsed(capabilities()), release: .picturesUnrestrictedForTests))
        // defaultAnimation 通过 0x95 idle 槽绑定，不发 0x82
        XCTAssertTrue(steps.contains(.bindTaskPicture(
            mode: 0, set: 0, state: 0,
            startIndex: 0, frameCount: 8, intervalMs: 83
        )))
        // 0x82 bindDefaultPicture 已删除：current 协议禁止，该 case 不存在
    }

    // MARK: compact factory 14B — 用户区 0..<userSlotLimit，不写 reclaim

    private func compactHilCapabilities() -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities.parse(Data([
            0x03, 0x04, 0x02, 0x04,
            0x3F, 0x00,
            0xC8, 0x00,
            0x14, 0x01,
            0x14, 0x01,
            0x1C, 0x01,
        ]))!
    }

    func testCompactFactoryUserWritesStartAtZeroAndStayInPrimary() throws {
        let caps = compactHilCapabilities()
        XCTAssertEqual(caps.userSlotLimit, 276)
        XCTAssertEqual(caps.factorySlotBase, 276)
        let steps = try XCTUnwrap(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 0,
            encodedFrameCount: 1,
            usesSessionUpload: false, userSlotLimit: caps.userSlotLimit
        ))
        guard case .prepareWrite(_, _, let addr) = steps.first else {
            return XCTFail("首槽必须从用户区 0 起编")
        }
        XCTAssertEqual(addr, 0)
        let binds = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: try! modeWithDefaultAnimation().0.modes[0],
            desired: try! modeWithDefaultAnimation().0,
            plan: try! modeWithDefaultAnimation().1,
            context: .parsed(caps), release: .picturesUnrestrictedForTests)).compactMap { step -> UInt16? in
            if case .bindTaskPicture(_, _, _, let start, let count, _) = step {
                XCTAssertLessThan(start, 276)
                XCTAssertLessThanOrEqual(Int(start) + Int(count), 276)
                return start
            }
            return nil
        }
        XCTAssertEqual(binds.first, 0)
        XCTAssertFalse(binds.contains(where: { $0 >= 276 }))
    }

    func testCompactFactoryDoesNotEmitReclaimStartIndex() throws {
        let caps = compactHilCapabilities()
        // slot 10 → 300 >= 276，必须整体失败，不得生成 reclaim 写入或空成功程序
        XCTAssertNil(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 10,
            encodedFrameCount: 1,
            usesSessionUpload: false, userSlotLimit: caps.userSlotLimit
        ))
        let (desired, plan) = try compactDesired(slot: 10, frames: 1)
        let metas = [try! AhaKeyConfigurationResource(
            logicalIdentifier: "img-edge",
            sha256: String(repeating: "a", count: 64), byteCount: 25600, mediaType: "gif"
        )]
        XCTAssertNil(Mapper.program(
            for: try! .init("resource:img-edge"), desired: desired, plan: plan,
            resources: metas, context: .parsed(caps), release: .picturesUnrestrictedForTests))
    }

    private func compactDesired(slot: Int, frames: Int) throws -> (AhaKeyDesiredConfiguration, AhaKeyConfigurationPlanner.Plan) {
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: resource("img-edge"), defaultAnimationFrames: frames,
            statusLine: "", framesPerSecond: 12, taskSets: [setA, setB], activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 50)
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [], oled: oled, lightBar: lightBar)
        let desired = try AhaKeyDesiredConfiguration(modes: [mode])
        let plan = AhaKeyConfigurationPlanner.Plan(
            transactions: [], slotAssignments: [resource("img-edge"): slot]
        )
        return (desired, plan)
    }

    func testCompactPrimaryOverflowFailsWholeProgram() throws {
        let caps = compactHilCapabilities()
        let layout = AhaKeyDeviceLayoutPolicy()
        XCTAssertEqual(layout.startFrameIndex(slot: 9, userRegionBase: 0), 270)
        // start=270，请求 7 帧越过 276：不得截短成 6 帧。
        XCTAssertNil(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 9,
            encodedFrameCount: 7,
            usesSessionUpload: false, userSlotLimit: caps.userSlotLimit
        ))
        let overflow = try compactDesired(slot: 9, frames: 7)
        let metas = [try! AhaKeyConfigurationResource(
            logicalIdentifier: "img-edge",
            sha256: String(repeating: "a", count: 64), byteCount: 7 * 25600, mediaType: "gif"
        )]
        XCTAssertNil(Mapper.program(
            for: try! .init("resource:img-edge"), desired: overflow.0, plan: overflow.1,
            resources: metas, context: .parsed(caps), release: .picturesUnrestrictedForTests))
        XCTAssertNil(Mapper.baseConfigurationProgram(
            mode: overflow.0.modes[0], desired: overflow.0, plan: overflow.1, context: .parsed(caps), release: .picturesUnrestrictedForTests))
        XCTAssertNil(Mapper.program(
            for: try! .init("base:mode:0"), desired: overflow.0, plan: overflow.1,
            resources: metas, context: .parsed(caps), release: .picturesUnrestrictedForTests))
    }

    func testCompactPrimaryLastSixFramesOccupyThrough275() throws {
        let caps = compactHilCapabilities()
        let steps = try XCTUnwrap(Mapper.resourceUploadProgram(
            digest: digest(), slotIndex: 9,
            encodedFrameCount: 6,
            usesSessionUpload: false, userSlotLimit: caps.userSlotLimit
        ))
        let prepares = steps.compactMap { step -> UInt32? in
            if case .prepareWrite(_, _, let addr) = step { return addr }
            return nil
        }
        XCTAssertEqual(prepares.count, 6 * 7)
        XCTAssertEqual(prepares.first, 270 * 28_672)
        XCTAssertEqual(prepares.last, 275 * 28_672 + UInt32(6 * 4096))
        XCTAssertFalse(prepares.contains(where: { $0 >= 276 * 28_672 }))
        let legal = try compactDesired(slot: 9, frames: 6)
        let binds = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: legal.0.modes[0], desired: legal.0, plan: legal.1, context: .parsed(caps), release: .picturesUnrestrictedForTests)).compactMap { step -> (UInt16, UInt16)? in
            if case .bindTaskPicture(_, _, _, let start, let count, _) = step {
                return (start, count)
            }
            return nil
        }
        XCTAssertEqual(binds.first?.0, 270)
        XCTAssertEqual(binds.first?.1, 6)
        XCTAssertTrue(binds.allSatisfy { Int($0.0) + Int($0.1) <= 276 })
        XCTAssertFalse(binds.contains(where: { $0.0 >= 276 }))
    }

    // MARK: OLED 兼容剖面 opcode 序列

    private func commandOpcodes(_ steps: [AhaKeyDeviceProgramStep]) -> [UInt8] {
        steps.compactMap { AhaKeyWireFrameBuilder.commandFrame(for: $0).map { $0[2] } }
    }

    func testStandardProgramOmitsRhinoAndSessionOpcodes() throws {
        let (desired, plan) = try modeWithEverything(activeSet: 0)
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan,
            context: .standard, release: .picturesUnrestrictedForTests
        ))
        // Standard 无 idle 槽：只发 working/done 的 0x93，再用 done 区间绑 0x82。
        XCTAssertEqual(commandOpcodes(steps).filter { $0 == 0x93 || $0 == 0x82 || $0 == 0x95 || $0 == 0x97 || $0 == 0x98 || $0 == 0x9A || $0 == 0x9B }, [
            AhaKeyWireFrameBuilder.cmdUpdateTaskPic,
            AhaKeyWireFrameBuilder.cmdUpdateTaskPic,
            AhaKeyWireFrameBuilder.cmdUpdatePic,
        ])
        let binds = steps.compactMap { step -> (UInt8, UInt8, UInt16, UInt16)? in
            if case .bindLegacyTaskPicture(let mode, let state, let start, let count, _) = step {
                return (mode, state, start, count)
            }
            return nil
        }
        XCTAssertEqual(binds.map { "\($0.0),\($0.1),\($0.2),\($0.3)" }, [
            "2,1,30,30",
            "2,3,0,12",
        ])
        XCTAssertTrue(steps.contains(.bindDefaultPicture(
            mode: 2, startIndex: 0, frameCount: 12, intervalMs: 100
        )))
        XCTAssertFalse(steps.contains { if case .bindTaskPicture = $0 { return true }; return false })
        XCTAssertFalse(steps.contains { if case .setActiveTaskPictureSet = $0 { return true }; return false })
        let resource = try XCTUnwrap(Mapper.program(
            for: try! .init("resource:img-a"), desired: desired, plan: plan,
            resources: [
                try! AhaKeyConfigurationResource(
                    logicalIdentifier: "img-a",
                    sha256: String(repeating: "a", count: 64), byteCount: 12 * 25_600, mediaType: "gif"
                ),
            ],
            context: .standard, release: .picturesUnrestrictedForTests
        ))
        XCTAssertEqual(commandOpcodes(resource), Array(repeating: AhaKeyWireFrameBuilder.cmdPrepareWrite, count: commandOpcodes(resource).count))
        XCTAssertTrue(resource.allSatisfy {
            if case .prepareWrite(let session, _, _) = $0 { return session == nil }
            return true
        })
    }

    func testRhinoDualSetProgramUsesProvenBindAndActivation() throws {
        let (desired, plan) = try modeWithEverything()
        let rhinoCaps = capabilities(sessionUpload: false)
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan,
            context: .parsed(rhinoCaps), release: .picturesUnrestrictedForTests
        ))
        let pictureCommands = steps.compactMap { step -> String? in
            switch step {
            case .bindTaskPicture(_, let set, let state, let start, let count, _):
                return "95 set=\(set) state=\(state) start=\(start) count=\(count)"
            case .setActiveTaskPictureSet(_, let set):
                return "97 set=\(set)"
            case .bindLegacyTaskPicture, .bindDefaultPicture, .finishTaskPictureWrite:
                return "forbidden"
            default:
                return nil
            }
        }
        XCTAssertEqual(pictureCommands, [
            "95 set=0 state=0 start=30 count=30",
            "95 set=0 state=1 start=30 count=30",
            "95 set=0 state=3 start=0 count=12",
            "97 set=1",
        ])
        let resource = try XCTUnwrap(Mapper.program(
            for: try! .init("resource:img-a"), desired: desired, plan: plan,
            resources: [
                try! AhaKeyConfigurationResource(
                    logicalIdentifier: "img-a",
                    sha256: String(repeating: "a", count: 64), byteCount: 12 * 25_600, mediaType: "gif"
                ),
            ],
            context: .parsed(rhinoCaps), release: .picturesUnrestrictedForTests
        ))
        XCTAssertEqual(Set(commandOpcodes(resource)), [AhaKeyWireFrameBuilder.cmdPrepareWrite])
    }

    func testCurrentSessionProgramUsesSessionPrepareAndOmitsBareWrite() throws {
        let (desired, plan) = try modeWithEverything(activeSet: 0)
        let sessionCaps = capabilities(sessionUpload: true, setCount: 1)
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolveParsed(sessionCaps),
            .currentSessionCapable
        )
        let resource = try XCTUnwrap(Mapper.program(
            for: try! .init("resource:img-a"), desired: desired, plan: plan,
            resources: [
                try! AhaKeyConfigurationResource(
                    logicalIdentifier: "img-a",
                    sha256: String(repeating: "a", count: 64), byteCount: 12 * 25_600, mediaType: "gif"
                ),
            ],
            context: .parsed(sessionCaps), release: .picturesUnrestrictedForTests
        ))
        XCTAssertFalse(commandOpcodes(resource).isEmpty)
        XCTAssertTrue(commandOpcodes(resource).allSatisfy { $0 == AhaKeyWireFrameBuilder.cmdPrepareSessionWrite })
        XCTAssertTrue(resource.allSatisfy {
            if case .prepareWrite(let session, _, _) = $0 { return session != nil }
            return true
        })
        let steps = try XCTUnwrap(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan,
            context: .parsed(sessionCaps), release: .picturesUnrestrictedForTests
        ))
        let pictureCommands = steps.compactMap { step -> String? in
            switch step {
            case .bindTaskPicture(_, let set, let state, let start, let count, _):
                return "95 set=\(set) state=\(state) start=\(start) count=\(count)"
            case .setActiveTaskPictureSet(_, let set):
                return "97 set=\(set)"
            case .bindLegacyTaskPicture, .bindDefaultPicture, .finishTaskPictureWrite:
                return "forbidden"
            default:
                return nil
            }
        }
        XCTAssertEqual(pictureCommands, [
            "95 set=0 state=0 start=30 count=30",
            "95 set=0 state=1 start=30 count=30",
            "95 set=0 state=3 start=0 count=12",
            "97 set=0",
        ])
        XCTAssertFalse(pictureCommands.contains { $0.contains("set=1") })
    }

    func testUnsupportedProfileEmitsNoApplyProgram() throws {
        let (desired, plan) = try modeWithEverything()
        let unsupported = AhaKeyOLEDCompatibilityContext.make(.malformedResponse)
        XCTAssertNil(Mapper.program(
            for: try! .init("resource:img-a"), desired: desired, plan: plan,
            resources: [
                try! AhaKeyConfigurationResource(
                    logicalIdentifier: "img-a",
                    sha256: String(repeating: "a", count: 64), byteCount: 12 * 25_600, mediaType: "gif"
                ),
            ],
            context: unsupported, release: .picturesUnrestrictedForTests
        ))
        XCTAssertNil(Mapper.baseConfigurationProgram(
            mode: desired.modes[0], desired: desired, plan: plan,
            context: unsupported, release: .picturesUnrestrictedForTests
        ))
    }
}
