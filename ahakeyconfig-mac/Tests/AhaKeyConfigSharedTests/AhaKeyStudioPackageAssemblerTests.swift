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
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: modes)
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
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [modeInput(slot: 0, donePath: "done-a")])
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
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [modeInput(slot: 1)])
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
            try AhaKeyStudioPackageAssembler.assemble(modes: [self.modeInput(slot: 2, donePath: "a-done", setB: setB)])
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
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [mode])
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
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode])) { error in
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
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode])) { error in
            XCTAssertEqual(
                error as? AhaKeyStudioPackageAssemblerError,
                .missingAssetMetadata(identifier: "mode0-default")
            )
        }
    }

    func testDuplicateKeyRoleRejected() throws {
        var mode = modeInput(slot: 0)
        mode.keys.append(mode.keys[0])
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode])) { error in
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
        XCTAssertThrowsError(try AhaKeyStudioPackageAssembler.assemble(modes: [mode])) { error in
            XCTAssertEqual(
                error as? AhaKeyStudioPackageAssemblerError,
                .invalidTaskSetCount(mode: 0, count: 1)
            )
        }
    }

    func testActiveSetBaselineMinusOnePassesThrough() throws {
        var mode = modeInput(slot: 0)
        mode.oled.activeSet = -1
        let assembled = try AhaKeyStudioPackageAssembler.assemble(modes: [mode])
        XCTAssertEqual(assembled.configuration.modes[0].oled.activeSet, -1, "-1 = 尚未同步基线，跨重启保留")
    }

    func testKeysAndLightOnlyDropsPictureResourcesAndUnsetsActiveSet() throws {
        let mode = modeInput(slot: 0, donePath: "done-a")
        let withPictures = try AhaKeyStudioPackageAssembler.assemble(modes: [mode])
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
    }
}
