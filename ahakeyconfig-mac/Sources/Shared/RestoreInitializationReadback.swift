import Foundation

/// Expectations derived from init_default_key_bund / restore_initialization_apply_defaults
/// at firmware 0a055ba. Matching settings is not proof of firmware binary provenance.
public struct RestoreInitializationReadback: Equatable {
    public let workMode: UInt8
    public let keys: [OrdinaryKeyReadback]
    public let routes: K1OutputRouteTransaction.Snapshot
    public let standbyMinutes: UInt16
    public let voiceState: UInt8
    public let sideSwitch: SideSwitchReadback
    public let display: WS3DisplaySnapshot
    public let lights: WS3LightCatalogSnapshot

    public init?(workMode: UInt8, keys: [OrdinaryKeyReadback], routes: K1OutputRouteTransaction.Snapshot,
                 standbyMinutes: UInt16, voiceState: UInt8, sideSwitch: SideSwitchReadback,
                 display: WS3DisplaySnapshot, lights: WS3LightCatalogSnapshot) {
        guard workMode < 4, keys.count == 16,
              keys.allSatisfy({ $0.mode < 4 && $0.keyIndex < 4 }),
              Set(keys.map { Int($0.mode) * 4 + Int($0.keyIndex) }).count == 16,
              sideSwitch.positions.count == 2,
              display.verifiesDisplaySettings(in: lights.generation) else { return nil }
        self.workMode = workMode; self.keys = keys; self.routes = routes
        self.standbyMinutes = standbyMinutes; self.voiceState = voiceState
        self.sideSwitch = sideSwitch; self.display = display; self.lights = lights
    }

    public enum DefaultDifference: Equatable {
        case workMode(actual: UInt8), standby, voice, sideSwitch, brightness
        case resource(UInt8)
        case light(mode: UInt8, state: UInt8)
        case route(mode: UInt8)
        case key(mode: UInt8, index: UInt8)
    }

    /// All comparisons remain strict. Reporting a runtime mode separately lets
    /// the caller distinguish it from a changed persisted configuration domain.
    public var defaultDifferences: [DefaultDifference] {
        var differences: [DefaultDifference] = []
        if workMode != 0 { differences.append(.workMode(actual: workMode)) }
        if standbyMinutes != 60 { differences.append(.standby) }
        if voiceState != 0 { differences.append(.voice) }
        if sideSwitch.positions != [
            .init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())
        ] { differences.append(.sideSwitch) }
        if display.brightness != 35 { differences.append(.brightness) }
        for resource in display.resources where resource.userValid || resource.writeState != .empty ||
            resource.frames != 0 || resource.payloadBytes != 0 || resource.crc32 != 0 {
            differences.append(.resource(resource.id))
        }
        let effects: [UInt8] = [11, 5, 1, 1, 1, 6, 6, 7, 0]
        for light in lights.lights where light.effect != effects[Int(light.state)] {
            differences.append(.light(mode: light.mode, state: light.state))
        }
        for mode: UInt8 in 0..<4 {
            let route = routes.routes[Int(mode)]
            if route.kind != .ordinary || route.action != (mode < 3 ? Data([0x73, 1, 0x6D]) : Data()) {
                differences.append(.route(mode: mode))
            }
        }
        for key in keys where key != Self.expectedKey(mode: key.mode, index: key.keyIndex) {
            differences.append(.key(mode: key.mode, index: key.keyIndex))
        }
        return differences
    }
    public var matchesX1RefactorDefaults: Bool { defaultDifferences.isEmpty }

    private static func expectedKey(mode: UInt8, index: UInt8) -> OrdinaryKeyReadback {
        if mode == 3 {
            return .init(mode: mode, keyIndex: index, actionType: 0, action: Data(), description: Data())
        }
        let names = [
            ["Record", "Yes", "No", "Backspace"],
            ["Record", "Accept", "Reject", "Backspace"],
            ["Record", "Accept", "Reject", "Backspace"]
        ]
        let action: Data
        var type: UInt8 = 0x73
        switch index {
        case 0: action = Data([0x6D])
        case 1: action = Data([0x28])
        case 2 where mode == 0:
            type = 0x74
            action = Data([1, 0x51, 2, 0x51, 1, 0x51, 2, 0x51, 1, 0x28, 2, 0x28])
        case 2 where mode == 2: action = Data([0x29])
        default: action = Data([0x2A])
        }
        return .init(mode: mode, keyIndex: index, actionType: type, action: action,
                     description: Data(names[Int(mode)][Int(index)].utf8))
    }
}
