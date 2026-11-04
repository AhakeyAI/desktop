import Foundation

/// Four firmware slots, two LEDs each. Blink only changed slots for three
/// cycles; an unchanged snapshot/heartbeat must never restart the animation.
public struct WS3TaskLightAnimation: Equatable {
    public private(set) var snapshot = WS3TaskSnapshot(slots: [nil, nil, nil, nil])!
    private var changedAt: [TimeInterval?] = Array(repeating: nil, count: 4)
    public init() {}

    public mutating func observe(_ value: WS3TaskSnapshot, at now: TimeInterval) {
        for slot in 0..<4 where snapshot.slots[slot] != value.slots[slot] {
            changedAt[slot] = value.slots[slot] == nil ? nil : now
        }
        snapshot = value
    }

    public func intensity(slot: Int, at now: TimeInterval) -> Double {
        guard (0..<4).contains(slot), snapshot.slots[slot] != nil else { return 0 }
        guard let start = changedAt[slot] else { return 1 }
        let elapsed = max(0, now - start)
        guard elapsed < 1.8 else { return 1 }
        return elapsed.truncatingRemainder(dividingBy: 0.6) < 0.25 ? 1 : 0.12
    }

    /// Fixed three-session demo. It never enters the real task registry.
    public static func mock(at elapsed: TimeInterval) -> Self {
        let sequences: [[WS3TaskState]] = [
            [.running, .waiting, .done], [.waiting, .running, .done], [.done, .waiting, .running]
        ]
        let step = Int(max(0, elapsed) / 3)
        var value = Self()
        // Only the previous frame is needed to preserve unchanged slots.
        if step > 0 {
            value.observe(WS3TaskSnapshot(slots: sequences[(step - 1) % 3].map { WS3TaskSlot(state: $0) } + [nil])!, at: -10)
        }
        value.observe(WS3TaskSnapshot(slots: sequences[step % 3].map { WS3TaskSlot(state: $0) } + [nil])!, at: Double(step * 3))
        return value
    }
}
