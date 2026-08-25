import XCTest
@testable import AhaKeyConfigShared

/// WBS-5.6 切片 0：desiredConfiguration canonical Codable 冻结。
final class AhaKeyDesiredConfigurationTests: XCTestCase {

    private func resource(_ id: String) -> AhaKeyResourceIdentifier {
        try! AhaKeyResourceIdentifier(id)
    }

    private func sampleConfiguration() throws -> AhaKeyDesiredConfiguration {
        let keys: [AhaKeyDesiredConfiguration.Key] = [
            .init(role: .voice,
                  action: .shortcut(try! .init(modifiers: [], keyCode: 0x58)),
                  description: "语音", voicePreset: "macOSNative"),
            .init(role: .approve,
                  action: .shortcut(try! .init(modifiers: [], keyCode: 0x28)),
                  description: "Yes"),
            .init(role: .reject,
                  action: .macro([
                    try! .init(action: 1, param: 0x51),
                    try! .init(action: 2, param: 0x51),
                    try! .init(action: 3, param: 5),
                    try! .init(action: 1, param: 0x28),
                    try! .init(action: 2, param: 0x28),
                  ]),
                  description: "No"),
            .init(role: .submit,
                  action: .shortcut(try! .init(modifiers: [], keyCode: 0x2A)),
                  description: "回退"),
        ]
        let setA = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: resource("oled-mode0-idle"), framesPerSecond: 12, pixelWidth: 128, pixelHeight: 128, declaredFrameCount: 8),
            try! .init(state: .working, resource: resource("oled-mode0-working"), framesPerSecond: 12, pixelWidth: 128, pixelHeight: 128, declaredFrameCount: 8),
            try! .init(state: .done, resource: resource("oled-mode0-done"), framesPerSecond: 12, pixelWidth: 128, pixelHeight: 128, declaredFrameCount: 8),
            try! .init(state: .error, resource: nil, framesPerSecond: 12),
        ])
        let setB = try AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        let oled = try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: resource("oled-mode0-done"),
            defaultAnimationFrames: 8,
            statusLine: "AhaKey",
            framesPerSecond: 12,
            taskSets: [setA, setB],
            activeSet: 0
        )
        let lightBar = try AhaKeyDesiredConfiguration.LightBar(
            stateMappings: [try! .init(state: 1, effect: "approvalWait")],
            brightness: 35
        )
        let mode = try AhaKeyDesiredConfiguration.Mode(slot: 0, keys: keys, oled: oled, lightBar: lightBar)
        return try AhaKeyDesiredConfiguration(modes: [mode])
    }

    // MARK: 往返与 canonical 稳定性

    func testRoundTripPreservesSemantics() throws {
        let config = try sampleConfiguration()
        let data = try config.canonicalData()
        let decoded = try AhaKeyDesiredConfiguration.decode(from: data)
        XCTAssertEqual(decoded, config)
    }

    func testCanonicalDataIsStableAcrossEncodes() throws {
        let config = try sampleConfiguration()
        XCTAssertEqual(try config.canonicalData(), try config.canonicalData())
    }

    func testKeyActionShortCutAndMacroBothSurvive() throws {
        let config = try sampleConfiguration()
        let decoded = try AhaKeyDesiredConfiguration.decode(from: config.canonicalData())
        let reject = decoded.modes[0].keys.first { $0.role == .reject }
        guard case .macro(let steps) = reject?.action else {
            return XCTFail("reject 应保持 macro 形态")
        }
        XCTAssertEqual(steps.count, 5)
        let approve = decoded.modes[0].keys.first { $0.role == .approve }
        guard case .shortcut(let shortcut) = approve?.action else {
            return XCTFail("approve 应保持 shortcut 形态")
        }
        XCTAssertEqual(shortcut.keyCode, 0x28)
    }

    // MARK: 校验边界

    func testRejectsDuplicateModeSlot() {
        let config = try? sampleConfiguration()
        XCTAssertNotNil(config)
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration(
            modes: [config!.modes[0], config!.modes[0]]
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .duplicateModeSlot) }
    }

    func testRejectsInvalidModeSlot() {
        let config = try! sampleConfiguration()
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.Mode(
            slot: 4, keys: config.modes[0].keys, oled: config.modes[0].oled,
            lightBar: config.modes[0].lightBar
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidModeSlot) }
    }

    func testRejectsOutOfRangeFramesPerSecond() {
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.TaskAsset(
            state: .done, resource: nil, framesPerSecond: 21
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidFramesPerSecond) }
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.TaskAsset(
            state: .done, resource: nil, framesPerSecond: 4
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidFramesPerSecond) }
    }

    func testRejectsWrongTaskSetCountAndActiveSet() {
        let set = try! AhaKeyDesiredConfiguration.TaskSet(assets: [
            try! .init(state: .idle, resource: nil, framesPerSecond: 12),
        ])
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [set], activeSet: 0
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidTaskSetCount) }
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [set, set], activeSet: 2
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidActiveSet) }
        // -1 是合法基线值（尚未同步）
        XCTAssertNoThrow(try AhaKeyDesiredConfiguration.OLED(
            defaultAnimation: nil, statusLine: "", framesPerSecond: 12,
            taskSets: [set, set], activeSet: -1
        ))
    }

    func testRejectsInvalidBrightnessAndMacroAction() {
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.LightBar(
            stateMappings: [], brightness: 0
        )) { XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidBrightness) }
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.MacroStep(action: 5)) {
            XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .invalidMacroAction)
        }
    }

    func testRejectsMalformedKeyAction() {
        XCTAssertThrowsError(try AhaKeyDesiredConfiguration.Shortcut(modifiers: ["shift", "shift"], keyCode: 0)) {
            XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .duplicateModifier)
        }
        // 两个键都没有 → missingKeyAction
        let json = Data("{\"role\":1,\"action\":{},\"description\":\"x\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AhaKeyDesiredConfiguration.Key.self, from: json)) {
            XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .missingKeyAction)
        }
        // 空宏 → emptyMacro
        let emptyMacro = Data("{\"role\":1,\"action\":{\"macro\":[]},\"description\":\"x\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AhaKeyDesiredConfiguration.Key.self, from: emptyMacro)) {
            XCTAssertEqual($0 as? AhaKeyDesiredConfigurationError, .emptyMacro)
        }
    }

    // MARK: 资源引用完整性

    func testReferencedResourcesCollectsAllIdentifiers() throws {
        let config = try sampleConfiguration()
        let refs = config.referencedResources
        XCTAssertEqual(refs, [
            resource("oled-mode0-idle"),
            resource("oled-mode0-working"),
            resource("oled-mode0-done"),
        ])
    }
}
