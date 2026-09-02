import XCTest
@testable import AhaKeyConfigShared

/// RELEASE-0.2 C-2：v0.2 投影接入 planner/mapper 后，键位/灯效不得产出 OLED 资源或 0x95/0x97。
final class AhaKeyReleaseV02WiringTests: XCTestCase {

    /// 固件 1.3 `tp_write_caps14` 精确 fixture（factory-off 14B）。
    private let caps14Payload = Data([
        0x03, 0x04, 0x02, 0x04,
        0x33, 0x00,
        0xC8, 0x00,
        0x20, 0x01,
        0x00, 0x00, 0x00, 0x00,
    ])

    private let keysAndLightOpcodes: Set<UInt8> = [
        AhaKeyWireFrameBuilder.cmdUpdateCustomKey,
        AhaKeyWireFrameBuilder.cmdSetLightMapping,
        AhaKeyWireFrameBuilder.cmdSetBrightness,
        AhaKeyWireFrameBuilder.cmdSaveConfig,
    ]

    private func caps14() throws -> AhaKeyFirmwareCapabilities {
        try XCTUnwrap(AhaKeyFirmwareCapabilities.parse(caps14Payload))
    }

    private func v0_2CurrentProjection() throws -> AhaKeyReleaseFeatureProjection {
        AhaKeyReleaseFeaturePolicy.current.projection(.parsed(try caps14()))
    }

    private func resource(_ id: String) -> AhaKeyResourceIdentifier { try! AhaKeyResourceIdentifier(id) }

    private func meta(_ id: String) -> AhaKeyConfigurationResource {
        try! AhaKeyConfigurationResource(
            logicalIdentifier: id,
            sha256: String(repeating: "a", count: 64),
            byteCount: 1024,
            mediaType: "gif"
        )
    }

    private func emptyOLED(activeSet: Int) throws -> AhaKeyDesiredConfiguration.OLED {
        let emptySet = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try .init(state: .idle, resource: nil, framesPerSecond: 12),
            try .init(state: .working, resource: nil, framesPerSecond: 12),
            try .init(state: .waiting, resource: nil, framesPerSecond: 12),
            try .init(state: .done, resource: nil, framesPerSecond: 12),
        ])
        return try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [emptySet, emptySet], activeSet: activeSet
        )
    }

    private func keysAndLightDesired(activeSet: Int = 0) throws -> AhaKeyDesiredConfiguration {
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try .init(keyCode: 0x28)), description: "Yes"
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let mode = try AhaKeyDesiredConfiguration.Mode(
            slot: 0, keys: [key], oled: try emptyOLED(activeSet: activeSet), lightBar: lightBar
        )
        return try AhaKeyDesiredConfiguration(modes: [mode])
    }

    private func picturedDesired() throws -> AhaKeyDesiredConfiguration {
        let asset = try AhaKeyDesiredConfiguration.TaskAsset(
            state: .done, resource: resource("img-a"),
            framesPerSecond: 12, pixelWidth: 128, pixelHeight: 128, declaredFrameCount: 8
        )
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [asset])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [setA, setB], activeSet: 0
        )
        let key = AhaKeyDesiredConfiguration.Key(
            role: .approve, action: .shortcut(try .init(keyCode: 0x28)), description: "Yes"
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(stateMappings: [], brightness: 35)
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: [key], oled: oled, lightBar: lightBar)
        return try AhaKeyDesiredConfiguration(modes: [mode])
    }

    func testV02KeysAndLightPlanOmitsResourceTransaction() throws {
        let capabilities = try caps14()
        let release = try v0_2CurrentProjection()
        XCTAssertTrue(release.allowsBasicConfigurationWrite)
        XCTAssertFalse(release.allowsResourcePackage)
        XCTAssertFalse(release.allowsPictureWrites)

        let result = AhaKeyConfigurationPlanner.plan(
            desired: try keysAndLightDesired(),
            resources: [],
            context: .parsed(capabilities), release: release
        )
        guard case .success(let plan) = result else {
            return XCTFail("空 OLED 键位/灯效应规划成功: \(result)")
        }
        XCTAssertEqual(plan.transactions.map(\.kind), [.baseConfiguration])
        XCTAssertTrue(plan.slotAssignments.isEmpty)
        XCTAssertTrue(plan.transactions[0].uploads.isEmpty)
    }

    func testV02PictureResourcesAreRejected() throws {
        let result = AhaKeyConfigurationPlanner.plan(
            desired: try picturedDesired(),
            resources: [meta("img-a")],
            context: .parsed(try caps14()), release: try v0_2CurrentProjection()
        )
        XCTAssertEqual(result, .failure(.releaseResourcePackageNotAllowed))
    }

    func testV02NegotiatingProjectionRejectsBasicWrite() throws {
        let release = AhaKeyReleaseFeaturePolicy.current.projection(.negotiating)
        let result = AhaKeyConfigurationPlanner.plan(
            desired: try keysAndLightDesired(),
            resources: [],
            context: .parsed(try caps14()), release: release
        )
        XCTAssertEqual(result, .failure(.releaseWriteNotAllowed))
    }

    func testV02MapperOmitsTaskPictureOpcodesOnEmptyOLED() throws {
        let desired = try keysAndLightDesired(activeSet: 0)
        let mode = desired.modes[0]
        let steps = try XCTUnwrap(AhaKeyConfigurationStepMapper.baseConfigurationProgram(
            mode: mode,
            desired: desired,
            plan: .init(transactions: [], slotAssignments: [:]),
            context: .parsed(try caps14()), release: try v0_2CurrentProjection()
        ))
        XCTAssertFalse(steps.contains { if case .bindTaskPicture = $0 { return true }; return false })
        XCTAssertFalse(steps.contains { if case .setActiveTaskPictureSet = $0 { return true }; return false })
        XCTAssertFalse(steps.contains { if case .finishTaskPictureWrite = $0 { return true }; return false })
        XCTAssertEqual(steps.last, .saveConfig)
        XCTAssertTrue(steps.contains(.setKeyShortcut(mode: 0, keyIndex: 1, hidCodes: [0x28])))
        XCTAssertTrue(steps.contains(.setBrightness(35)))
        XCTAssertTrue(steps.contains(.setLightMapping(mode: 0, effects: [0, 0, 0, 0, 0, 0, 0, 0, 0])))
    }

    func testV02KeysAndLightWireOpcodesExcludePictureCommands() throws {
        let desired = try keysAndLightDesired(activeSet: 0)
        let steps = try XCTUnwrap(AhaKeyConfigurationStepMapper.baseConfigurationProgram(
            mode: desired.modes[0],
            desired: desired,
            plan: .init(transactions: [], slotAssignments: [:]),
            context: .parsed(try caps14()), release: try v0_2CurrentProjection()
        ))
        var opcodes: [UInt8] = []
        for step in steps {
            let frame = try XCTUnwrap(AhaKeyWireFrameBuilder.commandFrame(for: step))
            XCTAssertGreaterThan(frame.count, 2)
            opcodes.append(frame[2])
        }
        XCTAssertEqual(Set(opcodes).subtracting(keysAndLightOpcodes), [])
        XCTAssertFalse(opcodes.contains(AhaKeyWireFrameBuilder.cmdUpdateTaskPicSet))
        XCTAssertFalse(opcodes.contains(AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet))
        XCTAssertFalse(opcodes.contains(AhaKeyWireFrameBuilder.cmdFinishTaskPicWrite))
        XCTAssertFalse(opcodes.contains(AhaKeyWireFrameBuilder.cmdUpdatePic))
    }

    func testV02ResourceProgramStepIsNil() throws {
        let desired = try picturedDesired()
        let plan = AhaKeyConfigurationPlanner.Plan(
            transactions: [],
            slotAssignments: [resource("img-a"): 0]
        )
        XCTAssertNil(
            AhaKeyConfigurationStepMapper.program(
                for: try AhaKeyRuntimeStepIdentifier("resource:img-a"),
                desired: desired,
                plan: plan,
                resources: [meta("img-a")],
                context: .parsed(try caps14()), release: try v0_2CurrentProjection()
            )
        )
    }
}
