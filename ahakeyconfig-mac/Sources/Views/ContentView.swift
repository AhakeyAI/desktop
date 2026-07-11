import AppKit
import SwiftUI
import VibeBar

struct ContentView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var islandState: VibeBarState
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false

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
                    voiceRelay.suppressPermissionOnboarding(for: 60)
                    FeatureCoachTipController.shared.refreshInterested()
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
            bleManager.refreshBluetoothAuthorization()
            voiceRelay.refreshPermissions(deferredTCCRequery: true)
            nativeSpeech.refreshPermissions(deferredTCCRequery: true)
        }
        .onChange(of: onboardingPermissionState.allPermissionsGranted) { allGranted in
            if allGranted {
                unifiedOnboardingCompleted = true
                voiceRelay.showsPermissionOnboarding = false
                FeatureCoachTipController.shared.refreshInterested()
            } else if shouldShowUnifiedOnboarding {
                voiceRelay.suppressPermissionOnboarding(for: 60)
            }
        }
        .onChange(of: unifiedOnboardingCompleted) { completed in
            if completed {
                // 全屏引导结束（含重放后再次完成）：主壳早已挂载，需主动唤醒气泡 tip。
                FeatureCoachTipController.shared.refreshInterested()
            }
        }
    }

    @ViewBuilder
    private var mainWorkspace: some View {
        if #available(macOS 14.0, *) {
            AhaKeySettingsRootView(bleManager: bleManager, islandState: islandState)
                .focusEffectDisabled()
        } else {
            AhaKeySettingsRootView(bleManager: bleManager, islandState: islandState)
        }
    }

    private var onboardingPermissionState: AhaKeyOnboardingPermissionState {
        AhaKeyOnboardingPermissionState(
            bluetoothPermissionGranted: bleManager.bluetoothPermissionGranted,
            bluetoothPoweredOn: bleManager.bluetoothPoweredOn,
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
        !unifiedOnboardingCompleted
    }

    private var onboardingActions: AhaKeyOnboardingActions {
        AhaKeyOnboardingActions(
            requestPermissions: {
                voiceRelay.suppressPermissionOnboarding()
                requestOnboardingPermissionsThenOpenPrivacySettingsIfNeeded(
                    bleManager: bleManager,
                    voiceRelay: voiceRelay,
                    nativeSpeech: nativeSpeech
                )
            },
            requestPermission: { kind in
                voiceRelay.suppressPermissionOnboarding()
                requestSingleOnboardingPermission(
                    kind,
                    bleManager: bleManager,
                    voiceRelay: voiceRelay,
                    nativeSpeech: nativeSpeech
                )
            },
            recheckPermissions: {
                voiceRelay.suppressPermissionOnboarding()
                bleManager.refreshBluetoothAuthorization()
                voiceRelay.refreshPermissions(deferredTCCRequery: true)
                nativeSpeech.refreshPermissions(deferredTCCRequery: true)
            },
            openSystemSettings: {
                voiceRelay.suppressPermissionOnboarding()
                openFirstMissingOnboardingPermissionSettings(
                    bleManager: bleManager,
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
    bleManager: AhaKeyBLEManager,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService
) {
    voiceRelay.suppressPermissionOnboarding(for: 60)

    switch kind {
    case .bluetooth:
        bleManager.ensureCentralManager()
        bleManager.refreshBluetoothAuthorization()
        bleManager.userInitiatedConnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            bleManager.refreshBluetoothAuthorization()
            if bleManager.bluetoothAuthorizationDeniedOrRestricted || !bleManager.bluetoothPoweredOn {
                openOnboardingPermissionSettings(.bluetooth)
            }
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
    bleManager: AhaKeyBLEManager,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService,
    delay: TimeInterval = 0.45
) {
    bleManager.refreshBluetoothAuthorization()
    voiceRelay.suppressPermissionOnboarding()
    voiceRelay.refreshPermissions(requestIfNeeded: true)
    nativeSpeech.refreshPermissions(requestIfNeeded: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        voiceRelay.suppressPermissionOnboarding()
        bleManager.refreshBluetoothAuthorization()
        openFirstMissingOnboardingPermissionSettings(
            bleManager: bleManager,
            voiceRelay: voiceRelay,
            nativeSpeech: nativeSpeech
        )
    }
}

@MainActor
private func openFirstMissingOnboardingPermissionSettings(
    bleManager: AhaKeyBLEManager,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService
) {
    if !bleManager.bluetoothPermissionGranted || !bleManager.bluetoothPoweredOn {
        if openFirstAvailableOnboardingSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"]) { return }
    }
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
