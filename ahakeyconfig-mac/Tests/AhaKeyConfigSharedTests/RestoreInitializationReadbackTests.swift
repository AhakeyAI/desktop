import XCTest
@testable import AhaKeyConfigShared

final class RestoreInitializationReadbackTests: XCTestCase {
    /// Independent wire values transcribed from firmware 0a055ba, not the app's canvas defaults.
    private func keys() -> [OrdinaryKeyReadback] {
        let fixture = [
            ["73|6d|Record", "73|28|Yes", "74|015102510151025101280228|No", "73|2a|Backspace"],
            ["73|6d|Record", "73|28|Accept", "73|2a|Reject", "73|2a|Backspace"],
            ["73|6d|Record", "73|28|Accept", "73|29|Reject", "73|2a|Backspace"],
            ["00||", "00||", "00||", "00||"]
        ]
        return fixture.enumerated().flatMap { mode, row in
            row.enumerated().map { index, text in
                let fields = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                let hex = fields[1]
                let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
                    let start = hex.index(hex.startIndex, offsetBy: offset)
                    return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
                }
                return .init(mode: UInt8(mode), keyIndex: UInt8(index),
                    actionType: UInt8(fields[0], radix: 16)!, action: Data(bytes), description: Data(fields[2].utf8))
            }
        }
    }
    private func facts(workMode: UInt8 = 0, changedKey: Bool = false, wrongLights: Bool = false,
                       customResource: Bool = false, standby: UInt16 = 60, voice: UInt8 = 0,
                       consumer: Bool = false) -> RestoreInitializationReadback {
        var bindings = keys()
        if changedKey {
            bindings[0] = .init(mode: 0, keyIndex: 0, actionType: 0x73, action: Data([0x6D]), description: Data("changed".utf8))
        }
        let routes = (0..<4).map { index in
            if index == 0 && consumer { return K1OutputRoute(kind: .consumer, action: Data([0xCF, 0]))! }
            return K1OutputRoute(kind: .ordinary, action: index < 3 ? Data([0x73, 1, 0x6D]) : Data())!
        }
        let resources: [WS3ResourceReadback] = (UInt8(0)..<19).map { id in
            let isCustom = customResource && id == 0
            let state: WS3ResourceWriteState = isCustom ? .valid : .empty
            let basic = WS3DisplayValue.resourceBasic(userValid: isCustom, writeState: state)
            let integrity: WS3DisplayValue
            if isCustom {
                integrity = .resourceIntegrity(frames: 1, bytes: WS3ResourceReadback.frameBytes, crc32: 7)
            } else {
                integrity = .resourceIntegrity(frames: 0, bytes: 0, crc32: 0)
            }
            return WS3ResourceReadback(id: id, basic: basic, integrity: integrity)!
        }
        let defaults: [UInt8] = [11, 5, 1, 1, 1, 6, 6, 7, 0]
        let lights = (UInt8(0)..<4).flatMap { mode in
            (UInt8(0)..<9).map { state in
                WS3SingleLightSnapshot(generation: 5, mode: mode, state: state,
                    effect: wrongLights && mode == 3 && state == 8 ? 1 : defaults[Int(state)])
            }
        }
        return RestoreInitializationReadback(workMode: workMode, keys: bindings,
            routes: .init(routes: routes)!, standbyMinutes: standby, voiceState: voice,
            sideSwitch: .init(physicalState: 1, positions: [
                .init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())
            ]), display: .init(generation: 5, brightness: 35, resources: resources),
            lights: .init(generation: 5, lights: lights)!)!
    }
    func testFirmwareDefaultsMatchIncludingEmptyFourthModeAndFactoryF18Routes() {
        XCTAssertTrue(facts().matchesX1RefactorDefaults)
        XCTAssertTrue(facts().keys.filter { $0.mode == 3 }.allSatisfy {
            $0.actionType == 0 && $0.action.isEmpty && $0.description.isEmpty
        })
    }
    func testEachUnrestoredDomainPreventsSuccess() {
        for value in [
            facts(workMode: 1), facts(changedKey: true), facts(wrongLights: true),
            facts(customResource: true), facts(standby: 30), facts(voice: 2), facts(consumer: true)
        ] { XCTAssertFalse(value.matchesX1RefactorDefaults) }
    }
    func testMissingDuplicateOrMixedGenerationFactsAreNotCompleteReadback() {
        let value = facts()
        var duplicate = value.keys; duplicate[15] = duplicate[0]
        for bindings in [Array(value.keys.dropLast()), duplicate] {
            XCTAssertNil(RestoreInitializationReadback(workMode: 0, keys: bindings, routes: value.routes,
                standbyMinutes: 60, voiceState: 0, sideSwitch: value.sideSwitch,
                display: value.display, lights: value.lights))
        }
        XCTAssertNil(RestoreInitializationReadback(workMode: 0, keys: value.keys, routes: value.routes,
            standbyMinutes: 60, voiceState: 0, sideSwitch: value.sideSwitch,
            display: .init(generation: 6, brightness: 35, resources: value.display.resources), lights: value.lights))
    }
}
