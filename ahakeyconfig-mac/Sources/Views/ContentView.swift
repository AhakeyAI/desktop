import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var runtimeStore: AhaKeyStudioRuntimeClient
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false
    @State private var dismissedIncompleteOnboardingThisSession = false

    var body: some View {
        ZStack {
            mainWorkspace
                .allowsHitTesting(!shouldShowUnifiedOnboarding)
                .accessibilityHidden(shouldShowUnifiedOnboarding)

            if shouldShowUnifiedOnboarding {
                UnifiedAhaKeyOnboardingView(
                    permissionState: onboardingPermissionState,
                    actions: onboardingActions
                ) { _, _ in
                    unifiedOnboardingCompleted = true
                    dismissedIncompleteOnboardingThisSession = !onboardingPermissionState.allPermissionsGranted
                    voiceRelay.suppressPermissionOnboarding(for: 60)
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .onAppear {
            if shouldShowUnifiedOnboarding {
                voiceRelay.suppressPermissionOnboarding(for: 60)
            } else {
                voiceRelay.showsPermissionOnboarding = false
            }
            voiceRelay.refreshPermissions(deferredTCCRequery: true)
            nativeSpeech.refreshPermissions(deferredTCCRequery: true)
        }
        .onChange(of: onboardingPermissionState.allPermissionsGranted) { allGranted in
            if allGranted {
                dismissedIncompleteOnboardingThisSession = false
                unifiedOnboardingCompleted = true
                voiceRelay.showsPermissionOnboarding = false
            } else if shouldShowUnifiedOnboarding {
                voiceRelay.suppressPermissionOnboarding(for: 60)
            }
        }
    }

    @ViewBuilder
    private var mainWorkspace: some View {
        if #available(macOS 14.0, *) {
            AhaKeyStudioView(runtimeStore: runtimeStore)
                .focusEffectDisabled()
        } else {
            AhaKeyStudioView(runtimeStore: runtimeStore)
        }
    }

    private var onboardingPermissionState: AhaKeyOnboardingPermissionState {
        AhaKeyOnboardingPermissionState(
            // Studio 不再直接持有蓝牙：权限与连接由 Runtime 管理；
            // 该行语义改为 Runtime 在线（离线时引导用户修复后台服务）。
            bluetoothPermissionGranted: true,
            bluetoothPoweredOn: runtimeStore.isOnline,
            inputMonitoringGranted: voiceRelay.inputMonitoringGranted,
            accessibilityGranted: voiceRelay.accessibilityGranted,
            microphoneGranted: nativeSpeech.microphoneGranted,
            speechRecognitionGranted: nativeSpeech.speechRecognitionGranted,
            siriEnabled: nativeSpeech.siriEnabled,
            dictationEnabled: nativeSpeech.dictationEnabled,
            voiceSummary: voiceRelay.statusMessage,
            speechSummary: nativeSpeech.statusMessage,
            isRecording: nativeSpeech.isRecording,
            transcriptPreview: nativeSpeech.transcriptPreview,
            lastCommittedText: nativeSpeech.lastCommittedText,
            speechStatusMessage: nativeSpeech.statusMessage
        )
    }

    private var shouldShowUnifiedOnboarding: Bool {
        !unifiedOnboardingCompleted ||
            (!onboardingPermissionState.allPermissionsGranted && !dismissedIncompleteOnboardingThisSession)
    }

    private var onboardingActions: AhaKeyOnboardingActions {
        AhaKeyOnboardingActions(
            requestPermissions: {
                voiceRelay.suppressPermissionOnboarding()
                requestOnboardingPermissionsThenOpenPrivacySettingsIfNeeded(
                    runtimeStore: runtimeStore,
                    voiceRelay: voiceRelay,
                    nativeSpeech: nativeSpeech
                )
            },
            requestPermission: { kind in
                voiceRelay.suppressPermissionOnboarding()
                requestSingleOnboardingPermission(
                    kind,
                    runtimeStore: runtimeStore,
                    voiceRelay: voiceRelay,
                    nativeSpeech: nativeSpeech
                )
            },
            recheckPermissions: {
                voiceRelay.suppressPermissionOnboarding()
                voiceRelay.refreshPermissions(deferredTCCRequery: true)
                nativeSpeech.refreshPermissions(deferredTCCRequery: true)
            },
            openSystemSettings: {
                voiceRelay.suppressPermissionOnboarding()
                openFirstMissingOnboardingPermissionSettings(
                    runtimeStore: runtimeStore,
                    voiceRelay: voiceRelay,
                    nativeSpeech: nativeSpeech
                )
            },
            toggleTryExperience: {
                voiceRelay.suppressPermissionOnboarding()
                nativeSpeech.toggleRecordingFromVoiceKey()
            }
        )
    }
}

@MainActor
private func requestSingleOnboardingPermission(
    _ kind: AhaKeyOnboardingPermissionKind,
    runtimeStore: AhaKeyStudioRuntimeClient,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService
) {
    voiceRelay.suppressPermissionOnboarding(for: 60)

    switch kind {
    case .bluetooth:
        // Studio 不再直连蓝牙：键盘连接由 AhaKey Runtime 管理。离线时引导修复后台服务。
        if !runtimeStore.isOnline {
            RuntimeServiceManager.shared.refresh()
            RuntimeServiceManager.shared.runtimeUserAlert = NSLocalizedString("键盘连接由 AhaKey Runtime 管理。请在主界面「更多 → 设备与后台服务」里修复并启动后台服务；运行后会自动连接键盘。", comment: "")
        }

    case .inputMonitoring:
        voiceRelay.requestInputMonitoringPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            voiceRelay.refreshPermissions(deferredTCCRequery: true)
            if !voiceRelay.inputMonitoringGranted {
                openOnboardingPermissionSettings(.inputMonitoring)
            }
        }

    case .accessibility:
        voiceRelay.requestAccessibilityPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            voiceRelay.refreshPermissions(deferredTCCRequery: true)
            if !voiceRelay.accessibilityGranted {
                openOnboardingPermissionSettings(.accessibility)
            }
        }

    case .microphone:
        nativeSpeech.requestMicrophonePermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            nativeSpeech.refreshPermissions(deferredTCCRequery: true)
            if !nativeSpeech.microphoneGranted {
                openOnboardingPermissionSettings(.microphone)
            }
        }

    case .speechRecognition:
        nativeSpeech.requestSpeechRecognitionPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            nativeSpeech.refreshPermissions(deferredTCCRequery: true)
            if !nativeSpeech.speechRecognitionGranted {
                openOnboardingPermissionSettings(.speechRecognition)
            }
        }

    case .siri, .dictation:
        openOnboardingPermissionSettings(kind)
    }
}

@MainActor
private func requestOnboardingPermissionsThenOpenPrivacySettingsIfNeeded(
    runtimeStore: AhaKeyStudioRuntimeClient,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService,
    delay: TimeInterval = 0.45
) {
    voiceRelay.suppressPermissionOnboarding()
    voiceRelay.refreshPermissions(requestIfNeeded: true)
    nativeSpeech.refreshPermissions(requestIfNeeded: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        voiceRelay.suppressPermissionOnboarding()
        openFirstMissingOnboardingPermissionSettings(
            runtimeStore: runtimeStore,
            voiceRelay: voiceRelay,
            nativeSpeech: nativeSpeech
        )
    }
}

@MainActor
private func openFirstMissingOnboardingPermissionSettings(
    runtimeStore: AhaKeyStudioRuntimeClient,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService
) {
    if !voiceRelay.inputMonitoringGranted {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]) { return }
    }
    if !voiceRelay.accessibilityGranted {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]) { return }
    }
    if !nativeSpeech.microphoneGranted {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"]) { return }
    }
    if !nativeSpeech.speechRecognitionGranted {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"]) { return }
    }
    if !nativeSpeech.siriEnabled {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.Siri-Settings.extension"]) { return }
    }
    if !nativeSpeech.dictationEnabled {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]) { return }
    }
    openCombinedOnboardingPrivacySettingsURL()
}

@MainActor
private func openOnboardingPermissionSettings(_ kind: AhaKeyOnboardingPermissionKind) {
    let candidates: [String]
    switch kind {
    case .bluetooth:
        candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
            "x-apple.systempreferences:com.apple.BluetoothSettings",
        ]
    case .inputMonitoring:
        candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]
    case .accessibility:
        candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
    case .microphone:
        candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"]
    case .speechRecognition:
        candidates = ["x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"]
    case .siri:
        candidates = ["x-apple.systempreferences:com.apple.Siri-Settings.extension"]
    case .dictation:
        candidates = ["x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]
    }
    if openFirstAvailableOnboardingSystemSettingsURL(candidates) { return }
    openCombinedOnboardingPrivacySettingsURL()
}

@MainActor
private func openCombinedOnboardingPrivacySettingsURL() {
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.Siri-Settings.extension",
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
    ]
    if openFirstAvailableOnboardingSystemSettingsURL(candidates) { return }
    let appPaths = [
        "/System/Applications/System Settings.app",
        "/System/Library/CoreServices/Applications/System Settings.app",
        "/System/Applications/System Preferences.app",
    ]
    for path in appPaths where FileManager.default.fileExists(atPath: path) {
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            return
        }
    }
}

@discardableResult
private func openFirstAvailableOnboardingSystemSettingsURL(_ candidates: [String]) -> Bool {
    for candidate in candidates {
        guard let url = URL(string: candidate) else { continue }
        if NSWorkspace.shared.open(url) {
            return true
        }
    }
    return false
}
