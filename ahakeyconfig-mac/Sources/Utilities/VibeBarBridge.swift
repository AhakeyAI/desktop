import Combine
import Foundation
import VibeBar

/// 把主 app 的 BLE / 语音服务状态镜像到 VibeBarState，让灵动岛 UI 自动跟随。
@MainActor
final class VibeBarBridge {
    let state = VibeBarState()
    private var cancellables = Set<AnyCancellable>()
    private weak var bleManager: AhaKeyBLEManager?

    func attach(
        bleManager: AhaKeyBLEManager,
        voiceRelay: VoiceRelayService = .shared,
        nativeSpeech: NativeSpeechTranscriptionService = .shared,
        onOpenMainWindow: @escaping () -> Void
    ) {
        self.bleManager = bleManager
        state.onOpenMainWindow = onOpenMainWindow

        bleManager.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                self?.state.keyboardConnected = connected
                self?.syncAppearance()
            }
            .store(in: &cancellables)

        bleManager.$batteryLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.batteryLevel = $0 }
            .store(in: &cancellables)

        bleManager.$deviceName
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.deviceName = $0 }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            bleManager.$isConnected,
            bleManager.$switchState,
            bleManager.$agentSwitchState
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] connected, switchState, agentSwitchState in
            guard let self else { return }
            if let agent = agentSwitchState {
                self.state.leverKnown = true
                self.state.leverIsAuto = (agent == 0)
            } else if connected {
                self.state.leverKnown = true
                self.state.leverIsAuto = (switchState == 0)
            } else {
                self.state.leverKnown = false
                self.state.leverIsAuto = false
            }
        }
        .store(in: &cancellables)

        voiceRelay.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] listening in
                self?.state.voiceListening = listening
                self?.syncAppearance()
                self?.syncAgentStatus()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            nativeSpeech.$isRecording,
            nativeSpeech.$isLongPressRecording
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] recording, longPress in
            self?.state.voiceRecording = recording || longPress
            self?.syncAppearance()
            self?.syncAgentStatus()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            bleManager.$workMode,
            AgentManager.shared.$isRunning,
            bleManager.$isConnected
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, running, _ in
            self?.state.agentRunning = running
            self?.syncAppearance()
            self?.syncAgentStatus()
        }
        .store(in: &cancellables)

        bleManager.$liveIDEStateValue
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.state.liveIDEStateValue = value
                self?.syncAgentStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .ahaKeyIslandAppearanceApplyRequested))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAppearance() }
            .store(in: &cancellables)

        syncAppearance()
        syncAgentStatus()
    }

    private func syncAppearance() {
        guard let bleManager else { return }
        let mode = AhaKeyModeSlot(rawValue: bleManager.workMode) ?? .mode0
        VibeBarIslandAppearanceSettings.sync(
            to: state,
            agentRunning: AgentManager.shared.isRunning,
            modePrimary: mode.name,
            connected: bleManager.isConnected
        )
    }

    private func syncAgentStatus() {
        if state.voiceRecording {
            state.agentStatus = .listening
            state.agentTaskTitle = "Voice input active"
            state.agentProgress = 0
            return
        }

        if let raw = state.liveIDEStateValue, let ide = IDEState(rawValue: UInt8(clamping: raw)) {
            switch ide {
            case .permissionRequest:
                state.agentStatus = .approval
                state.agentTaskTitle = "Waiting for your confirm"
                state.agentProgress = 0
            case .preToolUse:
                state.agentStatus = .coding
                state.agentTaskTitle = "Generating changes"
                state.agentProgress = 0.72
            case .postToolUse, .userPromptSubmit, .notification:
                state.agentStatus = .thinking
                state.agentTaskTitle = "Analyzing context"
                state.agentProgress = 0.4
            case .taskCompleted:
                state.agentStatus = .completed
                state.agentTaskTitle = "Task finished"
                state.agentProgress = 1
            case .sessionStart:
                state.agentStatus = .searching
                state.agentTaskTitle = "Scanning project"
                state.agentProgress = 0.5
            case .stop, .sessionEnd:
                state.agentStatus = .idle
                state.agentTaskTitle = ""
                state.agentProgress = 0
            }
            return
        }

        if state.agentRunning {
            state.agentStatus = .thinking
            state.agentTaskTitle = "Agent is running"
            state.agentProgress = 0.3
        } else {
            state.agentStatus = .idle
            state.agentTaskTitle = ""
            state.agentProgress = 0
        }
    }
}
