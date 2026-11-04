import Foundation

/// Four firmware slots, two LEDs each. Current F99D renders steady state
/// colors, so both real observations and the mock must avoid virtual pulses.
public struct WS3TaskLightAnimation: Equatable {
    public private(set) var snapshot = WS3TaskSnapshot(slots: [nil, nil, nil, nil])!
    public init() {}

    public mutating func observe(_ value: WS3TaskSnapshot, at _: TimeInterval) {
        snapshot = value
    }

    public func intensity(slot: Int, at _: TimeInterval) -> Double {
        guard (0..<4).contains(slot), snapshot.slots[slot] != nil else { return 0 }
        return 1
    }

    /// Fixed three-session demo. It never enters the real task registry.
    public static func mock(at elapsed: TimeInterval) -> Self {
        let sequences: [[WS3TaskState]] = [
            [.running, .waiting, .done], [.waiting, .running, .done], [.done, .waiting, .running]
        ]
        let step = Int(max(0, elapsed) / 3)
        var value = Self()
        value.observe(WS3TaskSnapshot(slots: sequences[step % 3].map { WS3TaskSlot(state: $0) } + [nil])!, at: Double(step * 3))
        return value
    }
}
