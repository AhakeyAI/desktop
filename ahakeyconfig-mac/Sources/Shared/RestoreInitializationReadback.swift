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

    public var matchesX1RefactorDefaults: Bool {
        guard workMode == 0, standbyMinutes == 60, voiceState == 0, display.brightness == 35,
              sideSwitch.positions == [
                .init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())
              ],
              display.resources.allSatisfy({
                !$0.userValid && $0.writeState == .empty && $0.frames == 0 &&
                    $0.payloadBytes == 0 && $0.crc32 == 0
              }) else { return false }
        let effects: [UInt8] = [11, 5, 1, 1, 1, 6, 6, 7, 0]
        guard lights.lights.allSatisfy({ $0.effect == effects[Int($0.state)] }) else { return false }
        for mode: UInt8 in 0..<4 {
            let route = routes.routes[Int(mode)]
            guard route.kind == .ordinary,
                  route.action == (mode < 3 ? Data([0x73, 1, 0x6D]) : Data()) else { return false }
        }
        for key in keys {
            guard key == Self.expectedKey(mode: key.mode, index: key.keyIndex) else { return false }
        }
        return true
    }

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
