import Foundation

/// Optional on older drafts: nil continues to use the legacy preferences.
struct VoiceProcessingPolicy: Codable, Equatable, Hashable {
    var shortPressAhaType: Bool
    var longPressAhaType: Bool
    var longPressThresholdMs: Int

    var thresholdSeconds: Double {
        Double(min(2_000, max(200, longPressThresholdMs))) / 1_000
    }
}

/// Value captured when audio starts; later mode/configuration changes cannot
/// turn a direct recording into a cloud request, or change its press type.
struct VoiceRecordingPolicySnapshot: Equatable {
    enum Gesture { case shortPress, longPress }
    let policy: VoiceProcessingPolicy
    let gesture: Gesture
    let ahaTypeEnabledAtStart: Bool

    var usesAhaType: Bool {
        ahaTypeEnabledAtStart && (gesture == .shortPress ? policy.shortPressAhaType : policy.longPressAhaType)
    }
}
