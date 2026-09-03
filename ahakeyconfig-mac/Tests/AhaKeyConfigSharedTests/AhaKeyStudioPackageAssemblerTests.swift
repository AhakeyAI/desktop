import XCTest
@testable import AhaKeyConfigShared

/// WBS 5.7 切片 2：Studio 编辑态 → DesiredConfiguration 组装器测试。
/// 覆盖：合法默认配置、defaultAnimation 镜像套图 A done 槽、资源标识符稳定性、
/// idle 镜像约束、申报元数据缺失、角色去重与套图数校验。
final class AhaKeyStudioPackageAssemblerTests: XCTestCase {

    // MARK: - 输入构造辅助

    private func gifURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/ahakey-test-\(name).gif")
    }

    private func asset(
        _ state: AhaKeyDesiredConfiguration.TaskDisplayState,
        path: String? = nil,
        fps: Int = 12,
        frames: Int = 8
    ) -> AhaKeyStudioTaskAssetInput {
        AhaKeyStudioTaskAssetInput(
            state: state,
            localFileURL: path.map { gifURL($0) },
            framesPerSecond: fps,
            declaredFrameCount: path == nil ? nil : frames,
            pixelWidth: path == nil ? nil : 160,
            pixelHeight: path == nil ? nil : 80
        )
    }

    private func setWith(donePath: String?, workingPath: String? = nil) -> AhaKeyStudioTaskSetInput {
        AhaKeyStudioTaskSetInput(assets: [
            asset(.idle),
            asset(.working, path: workingPath),
            asset(.waiting),
            asset(.done, path: donePath),
        ])
    }

    private func modeInput(
        slot: UInt8,
        donePath: String? = nil,
        setB: AhaKeyStudioTaskSetInput? = nil
    ) -> AhaKeyStudioModeInput {
        let keys: [AhaKeyStudioKeyInput] = [
            AhaKeyStudioKeyInput(
                role: .voice,
                action: .shortcut(try! .init(modifiers: [], keyCode: 0x6D)),
                description: "Record",
                voicePreset: "macOSNative"
            ),
            AhaKeyStudioKeyInput(
                role: .approve,
                action: .shortcut(try! .init(modifiers: [], keyCode: 0x28)),
                description: "Accept"
            ),
            AhaKeyStudioKeyInput(
                role: .reject,
                action: .macro([try! .init(action: 1, param: 0x28), try! .init(action: 2, param: 0x28)]),
                description: "No"
            ),
            AhaKeyStudioKeyInput(
                role: .submit,
                action: .shortcut(try! .init(modifiers: ["command"], keyCode: 0x2A)),
                description: "Backspace"
            ),
        ]
        return AhaKeyStudioModeInput(
            slot: slot,
            keys: keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "mode \(slot)",
                framesPerSecond: 12,
                taskSets: [
                    setWith(donePath: donePath),
                    setB ?? AhaKeyStudioTaskSetInput(assets: [
                        asset(.idle), asset(.working), asset(.waiting), asset(.done),
                    ]),
                ],
                activeSet: 0
            ),
            lightBar: AhaKeyStudioLightBarInput(
                stateMappings: [
                    AhaKeyStudioLightMappingInput(state: 3, effect: "singleMove"),
                    AhaKeyStudioLightMappingInput(state: 1, effect: "approvalWait"),
                ],
                brightness: 35
            )
        )
    }

    // MARK: - 测试

    func testDefaultLikeInputProducesValidConfiguration() throws {
        let modes = (0 ... 3).map { modeInput(slot: UInt8($0), donePath: "mode\($0)-done") }
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: modes, includePictureResources: true)
        let configuration = assembled.configuration
        XCTAssertEqual(configuration.modes.count, 4)
        XCTAssertEqual(Set(configuration.modes.map(\.slot)).count, 4, "模式槽位去重")
        for mode in configuration.modes {
            XCTAssertEqual(mode.keys.count, 4)
            XCTAssertEqual(Set(mode.keys.map(\.role)).count, 4, "角色去重")
            XCTAssertEqual(mode.oled.taskSets.count, 2, "恒 2 套")
            for set in mode.oled.taskSets {
                XCTAssertEqual(Set(set.assets.map(\.state)).count, 4, "每套 4 态且不重复")
            }
        }
        // canonical roundtrip 稳定
        let data = try configuration.canonicalData()
        XCTAssertEqual(try AhaKeyDesiredConfiguration.decode(from: data), configuration)
    }

    func testDefaultAnimationMirrorsSetADoneSlot() throws {
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [modeInput(slot: 0, donePath: "done-a")], includePictureResources: true)
        let oled = assembled.configuration.modes[0].oled
        let expected = try AhaKeyResourceIdentifier("mode0-default")
        XCTAssertEqual(oled.defaultAnimation, expected)
        XCTAssertEqual(oled.defaultAnimationFrames, 8)
        // done 槽 TaskAsset 引用同一标识符（镜像语义：一份资源，两处引用）。
        let done = oled.taskSets[0].assets.first { $0.state == .done }
        XCTAssertEqual(done?.resource, expected)
        XCTAssertEqual(done?.declaredFrameCount, 8)
        // 资源清单恰好一条（镜像不重复登记）。
        XCTAssertEqual(assembled.resources.map(\.logicalIdentifier), [expected])
        XCTAssertEqual(assembled.resources[0].fileURL, gifURL("done-a"))
    }

    func testNoDoneResourceYieldsNilDefaultAnimation() throws {
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [modeInput(slot: 1)], includePictureResources: true)
        let oled = assembled.configuration.modes[0].oled
        XCTAssertNil(oled.defaultAnimation)
        XCTAssertNil(oled.defaultAnimationFrames)
        XCTAssertTrue(assembled.resources.isEmpty)
    }

    func testResourceIdentifiersAreStableAndPositional() throws {
        let setB = AhaKeyStudioTaskSetInput(assets: [
            asset(.idle),
            asset(.working, path: "b-working"),
            asset(.waiting, path: "b-waiting"),
            asset(.done, path: "b-done"),
        ])
        let make: () throws -> AhaKeyStudioAssembledConfiguration = {
            try AhaKeyStudioPackageAssembler.assemble(modes: [self.modeInput(slot: 2, donePath: "a-done", setB: setB)], includePictureResources: true)
        }
        let first = try make()
        let second = try make()
        XCTAssertEqual(first, second, "同输入同标识符（稳定）")
        XCTAssertEqual(
            first.resources.map(\.logicalIdentifier.rawValue),
            ["mode2-default", "mode2-set1-done", "mode2-set1-waiting", "mode2-set1-working"],
            "标识符按位派生并按 rawValue 排序"
        )
    }

    func testIdleMirroringDefaultAnimationSharesIdentifier() throws {
        // idle 与套图 A done 同路径 → 引用 default 标识符，不另立资源。
        let setA = AhaKeyStudioTaskSetInput(assets: [
            asset(.idle, path: "shared-done"),
            asset(.working),
            asset(.waiting),
            asset(.done, path: "shared-done"),
        ])
        let mode = AhaKeyStudioModeInput(
            slot: 0,
            keys: modeInput(slot: 0).keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "", framesPerSecond: 12, taskSets: [setA, setWith(donePath: nil)], activeSet: 0
            ),
            lightBar: modeInput(slot: 0).lightBar
        )
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)
        let oled = assembled.configuration.modes[0].oled
        let expected = try AhaKeyResourceIdentifier("mode0-default")
        XCTAssertEqual(oled.taskSets[0].assets.first { $0.state == .idle }?.resource, expected)
        XCTAssertEqual(assembled.resources.count, 1, "同文件镜像只登记一份资源")
    }

    func testIdleWithDistinctResourceThrows() throws {
        // idle 独立图（≠ defaultAnimation）违反 planner 冻结约束，组装期 fail-fast。
        let setA = AhaKeyStudioTaskSetInput(assets: [
            asset(.idle, path: "idle-own"),
            asset(.working),
            asset(.waiting),
            asset(.done, path: "done-a"),
        ])
        let mode = AhaKeyStudioModeInput(
            slot: 3,
            keys: modeInput(slot: 3).keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "", framesPerSecond: 12, taskSets: [setA, setWith(donePath: nil)], activeSet: 0
            ),
            lightBar: modeInput(slot: 3).lightBar
        )
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)) { error in
            XCTAssertEqual(
                error as? AhaKeyStudioPackageAssemblerError,
                .idleResourceMustMirrorDefaultAnimation(mode: 3)
            )
        }
    }

    func testMissingDeclaredMetadataThrows() throws {
        let bad = AhaKeyStudioTaskAssetInput(
            state: .done,
            localFileURL: gifURL("no-meta"),
            framesPerSecond: 12
            // declaredFrameCount / pixel 尺寸缺失
        )
        let setA = AhaKeyStudioTaskSetInput(assets: [asset(.idle), asset(.working), asset(.waiting), bad])
        let mode = AhaKeyStudioModeInput(
            slot: 0,
            keys: modeInput(slot: 0).keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "", framesPerSecond: 12, taskSets: [setA, setWith(donePath: nil)], activeSet: 0
            ),
            lightBar: modeInput(slot: 0).lightBar
        )
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)) { error in
            XCTAssertEqual(
                error as? AhaKeyStudioPackageAssemblerError,
                .missingAssetMetadata(identifier: "mode0-default")
            )
        }
    }

    func testDuplicateKeyRoleRejected() throws {
        var mode = modeInput(slot: 0)
        mode.keys.append(mode.keys[0])
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)) { error in
            XCTAssertEqual(error as? AhaKeyDesiredConfigurationError, .duplicateKeyRole)
        }
    }

    func testInvalidTaskSetCountRejected() throws {
        let mode = AhaKeyStudioModeInput(
            slot: 0,
            keys: modeInput(slot: 0).keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "", framesPerSecond: 12, taskSets: [setWith(donePath: nil)], activeSet: 0
            ),
            lightBar: modeInput(slot: 0).lightBar
        )
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)) { error in
            XCTAssertEqual(
                error as? AhaKeyStudioPackageAssemblerError,
                .invalidTaskSetCount(mode: 0, count: 1)
            )
        }
    }

    func testActiveSetBaselineMinusOnePassesThrough() throws {
        var mode = modeInput(slot: 0)
        mode.oled.activeSet = -1
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)
        XCTAssertEqual(assembled.configuration.modes[0].oled.activeSet, -1, "-1 = 尚未同步基线，跨重启保留")
    }

    func testKeysAndLightOnlyDropsPictureResourcesAndUnsetsActiveSet() throws {
        let mode = modeInput(slot: 0, donePath: "done-a")
        let withPictures = try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)
        XCTAssertFalse(withPictures.resources.isEmpty)
        XCTAssertEqual(withPictures.configuration.modes[0].oled.activeSet, 0)

        let keysAndLight = try AhaKeyStudioPackageAssembler.assemble(
            modes: [mode],
            includePictureResources: false
        )
        XCTAssertTrue(keysAndLight.resources.isEmpty)
        XCTAssertNil(keysAndLight.configuration.modes[0].oled.defaultAnimation)
        XCTAssertEqual(keysAndLight.configuration.modes[0].oled.activeSet, -1)
        XCTAssertEqual(keysAndLight.configuration.modes[0].keys, withPictures.configuration.modes[0].keys)
        XCTAssertEqual(
            keysAndLight.configuration.modes[0].lightBar,
            withPictures.configuration.modes[0].lightBar
        )
        XCTAssertEqual(keysAndLight.configuration.modes[0].oled.statusLine, "")
        XCTAssertEqual(keysAndLight.configuration.modes[0].oled.framesPerSecond, 12)
    }

    func testKeysAndLightOnlyIgnoresMalformedOLEDDraft() throws {
        let mode = AhaKeyStudioModeInput(
            slot: 0,
            keys: modeInput(slot: 0).keys,
            oled: AhaKeyStudioOLEDInput(
                statusLine: "stale-broken-oled",
                framesPerSecond: 99,
                taskSets: [setWith(donePath: "broken")],
                activeSet: 0
            ),
            lightBar: modeInput(slot: 0).lightBar
        )
        XCTAssertThrowsError(
            try AhaKeyStudioPackageAssembler.assemble(modes: [mode], includePictureResources: true)
        )
        let assembled = try AhaKeyStudioPackageAssembler.assemble(
            modes: [mode],
            includePictureResources: false
        )
        XCTAssertTrue(assembled.resources.isEmpty)
        XCTAssertNil(assembled.configuration.modes[0].oled.defaultAnimation)
        XCTAssertEqual(assembled.configuration.modes[0].oled.activeSet, -1)
        XCTAssertEqual(assembled.configuration.modes[0].oled.statusLine, "")
        XCTAssertEqual(assembled.configuration.modes[0].oled.framesPerSecond, 12)
        XCTAssertEqual(assembled.configuration.modes[0].oled.taskSets.count, 2)
        XCTAssertEqual(assembled.configuration.modes[0].keys.count, 4)
        XCTAssertEqual(assembled.configuration.modes[0].lightBar.brightness, 35)
    }

    func testScopedAssemblerIgnoresOtherPageFieldsAndNoOpsWhenScreenUnchanged() {
        let screen = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("ok"),
            isDirty: true,
            baseline: .init(trust: .verified, value: .text("ok"))
        )
        let otherPage = AhaKeyStudioFrozenField(
            id: .keyAction(modeSlot: 0, role: .voice),
            value: .keyAction(try! sampleKeyAction()),
            isDirty: true,
            baseline: .init(trust: .verified, value: .keyAction(try! sampleKeyAction(keyCode: 5)))
        )
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                fields: [screen, otherPage]
            )
        )
        XCTAssertEqual(assembly, .noOp)
    }

    func testScopedAssemblerWritesDirtySetBOnlyAndActivatesSelectedSetWithoutMirroringIdle() {
        let doneB = AhaKeyStudioFrozenField(
            id: .screenTaskAsset(modeSlot: 0, setIndex: 1, state: .done),
            value: .asset(
                path: "/tmp/b-done.gif", framesPerSecond: 12, declaredFrameCount: 6,
                pixelWidth: 160, pixelHeight: 80
            ),
            isDirty: true,
            baseline: .init(trust: .verified, value: .asset(
                path: "/tmp/old.gif", framesPerSecond: 12, declaredFrameCount: 6,
                pixelWidth: 160, pixelHeight: 80
            ))
        )
        let idleA = AhaKeyStudioFrozenField(
            id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .idle),
            value: .asset(
                path: "/tmp/a-idle.gif", framesPerSecond: 12, declaredFrameCount: 2,
                pixelWidth: 160, pixelHeight: 80
            ),
            isDirty: false,
            baseline: .init(trust: .verified, value: .asset(
                path: "/tmp/a-idle.gif", framesPerSecond: 12, declaredFrameCount: 2,
                pixelWidth: 160, pixelHeight: 80
            ))
        )
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                selectedTaskSet: 1,
                fields: [doneB, idleA]
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("应写出套图 B dirty")
        }
        XCTAssertFalse(plan.writeTaskSetA)
        XCTAssertTrue(plan.writeTaskSetB)
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertTrue(plan.emitsSetActiveSetOpcode)
        XCTAssertFalse(plan.bindsDefaultAnimation)
        XCTAssertFalse(plan.fieldMask.contains(.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .idle)))
        XCTAssertEqual(plan.resources.count, 1)
        XCTAssertEqual(plan.resources[0].logicalIdentifier.rawValue, "mode0-set1-done")
        XCTAssertNotNil(plan.values[.screenTaskAsset(modeSlot: 0, setIndex: 1, state: .done)])
    }

    func testStandardDoesNotEmitPhysicalSetBForLogicalBOrBothDirty() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                selectedTaskSet: 1,
                overwriteConfirmed: true,
                fields: standardCompleteSet(logicalSet: 0, prefix: "/tmp/a")
                    + standardCompleteSet(logicalSet: 1, prefix: "/tmp/b")
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("选中逻辑 B 应映射到物理套 0")
        }
        XCTAssertTrue(plan.writeTaskSetA)
        XCTAssertFalse(plan.writeTaskSetB)
        XCTAssertFalse(plan.emitsSetActiveSetOpcode)
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertTrue(plan.resources.allSatisfy { $0.logicalIdentifier.rawValue.contains("-set0-") })
        XCTAssertFalse(plan.resources.contains { $0.logicalIdentifier.rawValue.contains("-set1-") })
        XCTAssertEqual(plan.resources.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertEqual(plan.fieldMask, Set(plan.values.keys))
        XCTAssertTrue(plan.fieldMask.allSatisfy { id in
            if case .screenTaskAsset(_, 1, let state) = id { return state != .idle }
            return false
        })
        XCTAssertFalse(plan.fieldMask.contains { id in
            if case .screenTaskAsset(_, 0, _) = id { return true }
            return false
        })
        XCTAssertFalse(plan.fieldMask.contains { id in
            if case .screenTaskAsset(_, _, .idle) = id { return true }
            return false
        })
        XCTAssertEqual(plan.values.count, AhaKeyTaskDisplayState.legacyStates.count)
    }

    func testUnknownUneditedFieldsDoNotCreateAWrite() {
        let field = AhaKeyStudioFrozenField(
            id: .screenStatusLine(modeSlot: 0),
            value: .text("current"),
            isDirty: false,
            baseline: .unknown
        )
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: .screen(modeSlot: 0),
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    fields: [field]
                )
            ),
            .noOp
        )
    }

    func testRhinoUnknownDirtyRequiresOverwriteConfirmation() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                overwriteConfirmed: false,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenStatusLine(modeSlot: 0),
                        value: .text("new"),
                        isDirty: true,
                        baseline: .unknown
                    ),
                ]
            )
        )
        XCTAssertEqual(assembly, .requiresOverwriteConfirmation)
    }

    func testStandardUnknownBaselineRequiresOverwriteConfirmation() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                overwriteConfirmed: false,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
                        value: .asset(
                            path: "/tmp/new.gif", framesPerSecond: 12, declaredFrameCount: 3,
                            pixelWidth: 160, pixelHeight: 80
                        ),
                        isDirty: true,
                        baseline: .unknown
                    ),
                ]
            )
        )
        XCTAssertEqual(assembly, .requiresOverwriteConfirmation)
    }

    func testStandardMissingRequiredFieldFailClosedAfterConfirmation() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                overwriteConfirmed: true,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
                        value: .asset(
                            path: "/tmp/new.gif", framesPerSecond: 12, declaredFrameCount: 3,
                            pixelWidth: 160, pixelHeight: 80
                        ),
                        isDirty: true,
                        baseline: .unknown
                    ),
                ]
            )
        )
        XCTAssertEqual(assembly, .missingTrustedPageCache)
    }

    func testKeyAndLightPlansCarryTypedValues() throws {
        let action = try sampleKeyAction()
        let keyAssembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .key(modeSlot: 0, role: .approve),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .keyAction(modeSlot: 0, role: .approve),
                        value: .keyAction(action),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .keyAction(try sampleKeyAction(keyCode: 9)))
                    ),
                    AhaKeyStudioFrozenField(
                        id: .keyDescription(modeSlot: 0, role: .approve),
                        value: .text("ok"),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .text("old"))
                    ),
                ]
            )
        )
        guard case .write(let keyPlan) = keyAssembly else {
            return XCTFail("key dirty 应有 typed payload")
        }
        XCTAssertEqual(keyPlan.values[.keyAction(modeSlot: 0, role: .approve)]?.keyActionValue, action)
        XCTAssertEqual(keyPlan.values[.keyDescription(modeSlot: 0, role: .approve)]?.textValue, "ok")

        let lightAssembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .lights(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .lightBrightness(modeSlot: 0),
                        value: .integer(80),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .integer(35))
                    ),
                    AhaKeyStudioFrozenField(
                        id: .lightMapping(modeSlot: 0, state: 1),
                        value: .text("pulse"),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .text("off"))
                    ),
                ]
            )
        )
        guard case .write(let lightPlan) = lightAssembly else {
            return XCTFail("light dirty 应有 typed payload")
        }
        XCTAssertEqual(lightPlan.values[.lightBrightness(modeSlot: 0)]?.integerValue, 80)
        XCTAssertEqual(lightPlan.values[.lightMapping(modeSlot: 0, state: 1)]?.textValue, "pulse")
    }

    func testLeverAndPowerPagesFailClosed() {
        for page in [AhaKeyStudioPageID.lever, .power] {
            let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: page,
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    fields: [
                        AhaKeyStudioFrozenField(
                            id: page == .lever ? .leverMacro : .powerAction,
                            value: .text("x"),
                            isDirty: true,
                            baseline: .unknown
                        ),
                    ]
                )
            )
            XCTAssertEqual(assembly, .unsupportedPage)
        }
    }

    func testIndependentUnknownConfirmationWritesOnlyDirtyFields() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .rhinoDualSet(sessionUploadAdvertised: false),
                overwriteConfirmed: true,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenStatusLine(modeSlot: 0),
                        value: .text("new"),
                        isDirty: true,
                        baseline: .unknown
                    ),
                    AhaKeyStudioFrozenField(
                        id: .screenFramesPerSecond(modeSlot: 0),
                        value: .integer(12),
                        isDirty: false,
                        baseline: .unknown
                    ),
                ]
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("确认后只应写 dirty 字段")
        }
        XCTAssertEqual(plan.fieldMask, [.screenStatusLine(modeSlot: 0)])
        XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
        XCTAssertEqual(plan.statusLine, "new")
        XCTAssertNil(plan.framesPerSecond)
    }

    func testRequiredAssetMissingURLFailsClosedAfterConfirmation() {
        var fields = standardCompleteSet(logicalSet: 0, prefix: "/tmp/std")
        fields = fields.map { field in
            guard case .screenTaskAsset(_, _, .done) = field.id else { return field }
            return AhaKeyStudioFrozenField(
                id: field.id,
                value: .asset(
                    path: nil, framesPerSecond: 12, declaredFrameCount: 3,
                    pixelWidth: 160, pixelHeight: 80
                ),
                isDirty: true,
                baseline: field.baseline
            )
        }
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                overwriteConfirmed: true,
                fields: fields
            )
        )
        XCTAssertEqual(assembly, .missingTrustedPageCache)
    }

    func testStandardRequiredSetExcludesIdle() {
        let required = AhaKeyStudioFieldOwnership.requiredFields(
            on: .screen(modeSlot: 0),
            profile: .legacyStandard,
            selectedTaskSet: 0
        )
        XCTAssertEqual(required.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertFalse(required.contains { id in
            if case .screenTaskAsset(_, _, .idle) = id { return true }
            return false
        })
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                overwriteConfirmed: true,
                fields: standardCompleteSet(logicalSet: 0, prefix: "/tmp/std") + [
                    AhaKeyStudioFrozenField(
                        id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .idle),
                        value: .asset(
                            path: "/tmp/std-idle.gif", framesPerSecond: 12, declaredFrameCount: 3,
                            pixelWidth: 160, pixelHeight: 80
                        ),
                        isDirty: true,
                        baseline: .init(
                            trust: .writeConfirmed,
                            value: .asset(
                                path: "/tmp/std-idle-old.gif", framesPerSecond: 12, declaredFrameCount: 3,
                                pixelWidth: 160, pixelHeight: 80
                            )
                        )
                    ),
                ]
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("Standard 整组应写出 C1 legacy states")
        }
        XCTAssertEqual(plan.fieldMask, Set(plan.values.keys))
        XCTAssertFalse(plan.fieldMask.contains { id in
            if case .screenTaskAsset(_, _, .idle) = id { return true }
            return false
        })
        XCTAssertFalse(plan.bindsDefaultAnimation)
        XCTAssertFalse(plan.resources.contains { $0.logicalIdentifier.rawValue.contains("idle") })
    }

    func testStandardActiveSetOnlyIsNoOp() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                selectedTaskSet: 1,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenActiveSet(modeSlot: 0),
                        value: .integer(1),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .integer(0))
                    ),
                ]
            )
        )
        XCTAssertEqual(assembly, .noOp)
    }

    func testStandardPictureWriteRecordsImplicitActivationWithoutActiveSetField() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .legacyStandard,
                selectedTaskSet: 1,
                overwriteConfirmed: true,
                fields: standardCompleteSet(logicalSet: 1, prefix: "/tmp/b") + [
                    AhaKeyStudioFrozenField(
                        id: .screenActiveSet(modeSlot: 0),
                        value: .integer(1),
                        isDirty: true,
                        baseline: .init(trust: .verified, value: .integer(0))
                    ),
                ]
            )
        )
        guard case .write(let plan) = assembly else {
            return XCTFail("picture 写入应带协议内隐式激活")
        }
        XCTAssertFalse(plan.fieldMask.contains(.screenActiveSet(modeSlot: 0)))
        XCTAssertEqual(plan.fieldMask, Set(plan.values.keys))
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertFalse(plan.emitsSetActiveSetOpcode)
        XCTAssertEqual(plan.resources.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertTrue(plan.resources.allSatisfy { $0.logicalIdentifier.rawValue.contains("-set0-") })
    }

    func testRhinoAndCurrentActiveSetOnlyEmitSetActiveSetOpcode() {
        for profile in [
            AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false),
            .currentSessionCapable,
        ] {
            let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: .screen(modeSlot: 0),
                    profile: profile,
                    selectedTaskSet: 1,
                    fields: [
                        AhaKeyStudioFrozenField(
                            id: .screenActiveSet(modeSlot: 0),
                            value: .integer(1),
                            isDirty: true,
                            baseline: .init(trust: .verified, value: .integer(0))
                        ),
                    ]
                )
            )
            guard case .write(let plan) = assembly else {
                return XCTFail("Rhino/current activeSet-only 应发 0x97")
            }
            XCTAssertEqual(plan.fieldMask, [.screenActiveSet(modeSlot: 0)])
            XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
            XCTAssertEqual(plan.values[.screenActiveSet(modeSlot: 0)]?.integerValue, 1)
            XCTAssertEqual(plan.activateTaskSet, 1)
            XCTAssertTrue(plan.emitsSetActiveSetOpcode)
            XCTAssertFalse(plan.writeTaskSetA)
            XCTAssertFalse(plan.writeTaskSetB)
            XCTAssertTrue(plan.resources.isEmpty)
            XCTAssertNil(plan.statusLine)
            XCTAssertNil(plan.framesPerSecond)
        }
    }

    func testMalformedTypedValuesFailClosedBeforeWrite() throws {
        let cases: [(AhaKeyStudioPageID, AhaKeyStudioFrozenField)] = [
            (
                .screen(modeSlot: 0),
                AhaKeyStudioFrozenField(
                    id: .screenStatusLine(modeSlot: 0),
                    value: .integer(1),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .text("old"))
                )
            ),
            (
                .screen(modeSlot: 0),
                AhaKeyStudioFrozenField(
                    id: .screenFramesPerSecond(modeSlot: 0),
                    value: .text("12"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(12))
                )
            ),
            (
                .screen(modeSlot: 0),
                AhaKeyStudioFrozenField(
                    id: .screenActiveSet(modeSlot: 0),
                    value: .text("1"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(0))
                )
            ),
            (
                .key(modeSlot: 0, role: .approve),
                AhaKeyStudioFrozenField(
                    id: .keyAction(modeSlot: 0, role: .approve),
                    value: .text("x"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .keyAction(try sampleKeyAction()))
                )
            ),
            (
                .lights(modeSlot: 0),
                AhaKeyStudioFrozenField(
                    id: .lightBrightness(modeSlot: 0),
                    value: .text("80"),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .integer(35))
                )
            ),
            (
                .lights(modeSlot: 0),
                AhaKeyStudioFrozenField(
                    id: .lightMapping(modeSlot: 0, state: 1),
                    value: .integer(1),
                    isDirty: true,
                    baseline: .init(trust: .verified, value: .text("off"))
                )
            ),
        ]
        for (page, field) in cases {
            let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: page,
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    selectedTaskSet: 1,
                    fields: [field]
                )
            )
            XCTAssertEqual(assembly, .missingTrustedPageCache, "\(field.id)")
        }

        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: .screen(modeSlot: 0),
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    selectedTaskSet: 1,
                    fields: [
                        AhaKeyStudioFrozenField(
                            id: .screenActiveSet(modeSlot: 0),
                            value: .integer(0),
                            isDirty: true,
                            baseline: .init(trust: .verified, value: .integer(1))
                        ),
                    ]
                )
            ),
            .missingTrustedPageCache
        )
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: .screen(modeSlot: 0),
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    selectedTaskSet: 0,
                    fields: [
                        AhaKeyStudioFrozenField(
                            id: .screenActiveSet(modeSlot: 0),
                            value: .integer(2),
                            isDirty: true,
                            baseline: .init(trust: .verified, value: .integer(0))
                        ),
                    ]
                )
            ),
            .missingTrustedPageCache
        )
    }

    func testUnsupportedProfileDoesNotAssembleWrite() {
        let assembly = AhaKeyStudioPackageAssembler.assembleScopedPage(
            AhaKeyStudioPageSnapshot(
                pageID: .screen(modeSlot: 0),
                profile: .unsupported,
                fields: [
                    AhaKeyStudioFrozenField(
                        id: .screenStatusLine(modeSlot: 0),
                        value: .text("x"),
                        isDirty: true,
                        baseline: .unknown
                    ),
                ]
            )
        )
        XCTAssertEqual(assembly, .unsupportedProfile)
    }

    private func standardCompleteSet(logicalSet: Int, prefix: String) -> [AhaKeyStudioFrozenField] {
        AhaKeyTaskDisplayState.legacyStates.compactMap {
            AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: UInt8($0.rawValue))
        }.map { state in
            let value = AhaKeyStudioFieldValue.asset(
                path: "\(prefix)-\(state.rawValue).gif",
                framesPerSecond: 12,
                declaredFrameCount: 3,
                pixelWidth: 160,
                pixelHeight: 80
            )
            return AhaKeyStudioFrozenField(
                id: .screenTaskAsset(modeSlot: 0, setIndex: logicalSet, state: state),
                value: value,
                isDirty: true,
                baseline: .init(
                    trust: .writeConfirmed,
                    value: .asset(
                        path: "\(prefix)-old.gif",
                        framesPerSecond: 12,
                        declaredFrameCount: 3,
                        pixelWidth: 160,
                        pixelHeight: 80
                    )
                )
            )
        }
    }

    private func sampleKeyAction(keyCode: UInt8 = 4) throws -> AhaKeyDesiredConfiguration.KeyAction {
        .shortcut(try AhaKeyDesiredConfiguration.Shortcut(modifiers: ["command"], keyCode: keyCode))
    }
}
