import Foundation

public struct VoiceHandoffSnapshot: Equatable {
    public let onboardingState: UInt8
    public let keys: [OrdinaryKeyReadback]
    public init(onboardingState: UInt8, keys: [OrdinaryKeyReadback]) {
        self.onboardingState = onboardingState
        self.keys = keys
    }
    public var isValid: Bool {
        onboardingState <= 4 && keys.count == 4 && keys.enumerated().allSatisfy { mode, key in
            key.mode == UInt8(mode) && key.keyIndex == 0 && key.isKnownEditableAction && key.description.count <= 20 &&
            11 + key.action.count + key.description.count <= 64 && (key.actionType != 0 || key.action.isEmpty)
        }
    }
    public var desktopBindings: [OrdinaryKeyReadback] {
        keys.map { .init(mode: $0.mode, keyIndex: 0, actionType: 0x73, action: Data([0x6D]), description: $0.description) }
    }
    public var isDesktopF18Confirmed: Bool { isValid && onboardingState == 3 && keys == desktopBindings }
}

/// Global onboarding ownership changes last, after every mode has a safe
/// desktop trigger. Never suppress at launch, reconnect, or a mere read.
public enum ConfirmedVoiceHandoff {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidSnapshot, changedSinceRead, bindingsMismatch, ownershipMismatch, hostNotReady
        public var errorDescription: String? {
            switch self {
            case .invalidSnapshot: return NSLocalizedString("四个模式的 Voice 绑定尚未完整确认，不能接管。", comment: "")
            case .changedSinceRead: return NSLocalizedString("语音预设或 Voice 绑定已变化，请重新读取。", comment: "")
            case .bindingsMismatch: return NSLocalizedString("Voice 绑定读回不一致，未完成接管。", comment: "")
            case .ownershipMismatch: return NSLocalizedString("语音所有权读回不一致，接管结果未确认。", comment: "")
            case .hostNotReady: return NSLocalizedString("请先完成 App 语音权限设置，并结束当前录音。", comment: "")
            }
        }
    }
    public static let suppressRequest = Data([0xAA, 0xBB, 0x96, 3, 0xCC, 0xDD])

    @MainActor
    public static func run(baseline: VoiceHandoffSnapshot, checkSession: () throws -> Void,
                           checkHostReady: () throws -> Void, read: () async throws -> VoiceHandoffSnapshot,
                           prepareHost: () throws -> Void, write: (Data) async throws -> Void) async throws -> VoiceHandoffSnapshot {
        guard baseline.isValid, baseline.desktopBindings.allSatisfy(OrdinaryKeyConfiguration.valid) else { throw Failure.invalidSnapshot }
        try checkSession()
        try checkHostReady()
        let current = try await read()
        try checkSession()
        guard current == baseline else { throw Failure.changedSinceRead }
        try checkHostReady()
        // Prepare the existing App pipeline before any F18 can become effective.
        // If a subsequent device operation fails, this explicitly selected host
        // route remains prepared; do not claim an automatic rollback.
        try prepareHost()
        try checkSession()
        let targets = baseline.desktopBindings
        let changed = zip(current.keys, targets).filter { $0 != $1 }.map { $1 }
        if !changed.isEmpty {
            for key in changed {
                guard let request = OrdinaryKeyConfiguration.actionRequest(key) else { throw Failure.invalidSnapshot }
                try await write(request)
                try checkSession()
            }
            try await write(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]))
            try checkSession()
        }
        let staged = changed.isEmpty ? current : try await read()
        try checkSession()
        guard staged.keys == targets else { throw Failure.bindingsMismatch }
        guard staged.onboardingState == baseline.onboardingState else { throw Failure.changedSinceRead }
        if staged.onboardingState == 3 { return staged }
        try checkHostReady()
        try await write(suppressRequest)
        try checkSession()
        let actual = try await read()
        try checkSession()
        guard actual.onboardingState == 3 else { throw Failure.ownershipMismatch }
        guard actual.keys == targets else { throw Failure.bindingsMismatch }
        return actual
    }
}
