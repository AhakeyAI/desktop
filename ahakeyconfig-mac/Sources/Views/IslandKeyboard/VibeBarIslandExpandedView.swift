import AppKit
import SwiftUI
import VibeBar

/// VibeBar Agent Command Center：单机身剪影（灯带 × OLED × 四键 × 底座）。
struct VibeBarIslandExpandedView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var state: VibeBarState

    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @AppStorage(VibeBarIslandSoundSettings.mutedDefaultsKey) private var isIslandSoundMuted = false
    @State private var showingQuitConfirmation = false
    @State private var previewStatusIndex = 0
    @State private var usingPreviewOverride = false
    @State private var keyPadSlots = VibeBarKeyPadSettings.slots
    @State private var petAppearance = VibeBarPetAppearanceSettings.appearance

    private let notchLaneHeaderOffset: CGFloat = -10

    private var displayStatus: VibeBarAgentStatus {
        if let live = liveDerivedStatus {
            return live
        }
        if usingPreviewOverride {
            return VibeBarAgentStatus.allCases[previewStatusIndex % VibeBarAgentStatus.allCases.count]
        }
        return state.agentStatus
    }

    private var liveDerivedStatus: VibeBarAgentStatus? {
        if state.voiceRecording { return .listening }
        if let raw = state.liveIDEStateValue, let ide = IDEState(rawValue: UInt8(raw)) {
            return mapIDEState(ide)
        }
        if state.agentRunning { return .thinking }
        return nil
    }

    var body: some View {
        VibeBarHardwareChassis(
            status: displayStatus,
            state: state,
            taskTitle: taskTitle(for: displayStatus),
            progress: progress(for: displayStatus),
            keys: commandKeys,
            isSoundMuted: $isIslandSoundMuted,
            onOpenMainWindow: openMainWindow,
            onQuit: { showingQuitConfirmation = true },
            onPetTap: cyclePreviewStatus,
            petAppearance: petAppearance
        )
        .frame(width: state.islandWidth)
        .padding(.top, max(0, -notchLaneHeaderOffset))
        .offset(y: notchLaneHeaderOffset)
        .contentShape(Rectangle())
        .onHover { state.onIslandHoverChanged?($0) }
        .alert("退出 AhaKey Studio？", isPresented: $showingQuitConfirmation) {
            Button("退出", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将关闭主窗口与灵动岛。")
        }
        .onAppear {
            state.onIslandAppear?()
            voiceRelay.updateRoutes(from: AhaKeyStudioStore.load() ?? .default)
            usingPreviewOverride = liveDerivedStatus == nil
            keyPadSlots = VibeBarKeyPadSettings.slots
            petAppearance = VibeBarPetAppearanceSettings.appearance
        }
        .onChange(of: state.voiceRecording) { _ in refreshPreviewGate() }
        .onChange(of: state.agentRunning) { _ in refreshPreviewGate() }
        .onChange(of: state.liveIDEStateValue) { _ in refreshPreviewGate() }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarKeyPadSettings.didChangeNotification)) { _ in
            keyPadSlots = VibeBarKeyPadSettings.slots
        }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarPetAppearanceSettings.didChangeNotification)) { _ in
            petAppearance = VibeBarPetAppearanceSettings.appearance
        }
    }

    private var commandKeys: [VibeBarCommandKey] {
        let visible = keyPadSlots.filter(\.isEnabled)
        let slots = visible.isEmpty ? Array(keyPadSlots.prefix(1)) : visible
        return slots.map { makeCommandKey(from: $0) }
    }

    private func makeCommandKey(from slot: VibeBarKeyPadSlot) -> VibeBarCommandKey {
        let systemName: String = {
            if slot.role == .voice {
                return state.voiceRecording ? "mic.fill" : slot.systemImage
            }
            return slot.systemImage
        }()
        let tint: Color = {
            if slot.role == .voice, state.voiceRecording {
                return Color(red: 1.0, green: 0.35, blue: 0.35)
            }
            return slot.tintColor
        }()
        let subtitle: String = {
            if slot.role == .approve, state.leverKnown {
                return state.leverIsAuto ? "Auto" : "Ask"
            }
            return slot.id.uppercased()
        }()

        return VibeBarCommandKey(
            id: slot.role.rawValue,
            title: slot.title,
            subtitle: subtitle,
            systemName: systemName,
            tint: tint
        ) {
            performRole(slot.role)
        }
    }

    private func performRole(_ role: VibeBarKeyPadRole) {
        switch role {
        case .voice:
            if let onKeyRecord = state.onKeyRecord {
                onKeyRecord()
            } else {
                nativeSpeech.toggleRecordingFromVoiceKey()
            }
        case .approve:
            if let onKeyApprove = state.onKeyApprove {
                onKeyApprove()
            } else {
                state.onOpenApprove?()
            }
        case .reject:
            if let onKeyReject = state.onKeyReject {
                onKeyReject()
            } else {
                openMainWindow()
                StudioNavigationRouter.shared.navigate(to: .approve)
            }
        case .submit:
            if let onKeySwitch = state.onKeySwitch {
                onKeySwitch()
            } else {
                cyclePreviewStatus()
            }
        }
    }

    private func mapIDEState(_ ide: IDEState) -> VibeBarAgentStatus {
        switch ide {
        case .permissionRequest: return .approval
        case .preToolUse: return .coding
        case .postToolUse, .userPromptSubmit: return .thinking
        case .taskCompleted: return .completed
        case .sessionStart: return .searching
        case .notification: return .thinking
        case .stop, .sessionEnd: return .idle
        }
    }

    private func taskTitle(for status: VibeBarAgentStatus) -> String {
        if !state.agentTaskTitle.isEmpty { return state.agentTaskTitle }
        switch status {
        case .idle: return "Ready for next task"
        case .listening: return "Voice input active"
        case .thinking: return "Analyzing context"
        case .searching: return "Scanning project"
        case .coding: return "Generating changes"
        case .approval: return "Waiting for your confirm"
        case .completed: return "Task finished"
        case .error: return "Something went wrong"
        }
    }

    private func progress(for status: VibeBarAgentStatus) -> Double {
        if state.agentProgress > 0 { return min(1, max(0, state.agentProgress)) }
        switch status {
        case .thinking: return 0.35
        case .searching: return 0.55
        case .coding: return 0.72
        default: return 0
        }
    }

    private func cyclePreviewStatus() {
        usingPreviewOverride = true
        previewStatusIndex = (previewStatusIndex + 1) % VibeBarAgentStatus.allCases.count
        VibeBarIslandSoundSettings.playInteractionIfEnabled()
    }

    private func refreshPreviewGate() {
        if liveDerivedStatus != nil {
            usingPreviewOverride = false
        }
    }

    private func openMainWindow() {
        state.onOpenMainWindow?()
        state.onIslandCompact?()
        // 等主窗口前台后再切 Tab，避免窗口尚未重建时通知丢失。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            StudioNavigationRouter.shared.selectSettingsTab(.hardware)
        }
    }
}
