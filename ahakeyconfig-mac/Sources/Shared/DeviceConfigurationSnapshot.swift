import Foundation

/// Device readback only. Local editing drafts never populate this snapshot.
public struct DeviceConfigurationSnapshot: Equatable {
    public enum Field: Hashable {
        case key(mode: UInt8, index: UInt8)
        case standby, voice, sideSwitch
    }

    public private(set) var generation: UInt64
    public private(set) var keys: [Field: OrdinaryKeyReadbackResult] = [:]
    public private(set) var standbyMinutes: UInt16?
    public private(set) var voiceOnboardingState: UInt8?
    public private(set) var sideSwitch: SideSwitchReadback?
    public private(set) var failures: [Field: String] = [:]

    public init(generation: UInt64 = 0) { self.generation = generation }

    public mutating func reset(generation: UInt64) {
        self = Self(generation: generation)
    }

    public mutating func recordKey(_ result: OrdinaryKeyReadbackResult, mode: UInt8, index: UInt8, generation: UInt64) {
        guard generation == self.generation, mode < 4, index < 4 else { return }
        let field = Field.key(mode: mode, index: index)
        keys[field] = result
        failures.removeValue(forKey: field)
    }

    public mutating func recordStandby(_ value: UInt16, generation: UInt64) {
        guard generation == self.generation, [0, 30, 60, 120].contains(value) else { return }
        standbyMinutes = value
        failures.removeValue(forKey: .standby)
    }

    public mutating func recordVoice(_ value: UInt8, generation: UInt64) {
        guard generation == self.generation, value <= 4 else { return }
        voiceOnboardingState = value
        failures.removeValue(forKey: .voice)
    }

    public mutating func recordSideSwitch(_ value: SideSwitchReadback, generation: UInt64) {
        guard generation == self.generation, value.positions.count == 2,
              value.positions.allSatisfy({ $0.bindType <= 3 }) else { return }
        sideSwitch = value
        failures.removeValue(forKey: .sideSwitch)
    }

    public mutating func recordFailure(_ field: Field, message: String, generation: UInt64) {
        guard generation == self.generation else { return }
        failures[field] = message
        switch field {
        case .key: keys.removeValue(forKey: field)
        case .standby: standbyMinutes = nil
        case .voice: voiceOnboardingState = nil
        case .sideSwitch: sideSwitch = nil
        }
    }
}
