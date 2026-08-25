import Combine
import Foundation
import VibeBar

/// 把主 app 的 BLE / 语音服务状态镜像到 VibeBarState，让灵动岛 UI 自动跟随。
@MainActor
final class VibeBarBridge {
    let state = VibeBarState()
    private var cancellables = Set<AnyCancellable>()

    func attach(
        bleManager: AhaKeyBLEManager,
        onOpenMainWindow: @escaping () -> Void
    ) {
        attach(
            bleManager: bleManager,
            voiceRelay: .shared,
            nativeSpeech: .shared,
            onOpenMainWindow: onOpenMainWindow
        )
    }

    func attach(
        bleManager: AhaKeyBLEManager,
        voiceRelay: VoiceRelayService,
        nativeSpeech: NativeSpeechTranscriptionService,
        onOpenMainWindow: @escaping () -> Void
    ) {
        // WindowGroup 的视图可能多次出现；重新绑定前取消旧订阅，避免重复回调与上游对象滞留。
        cancellables.removeAll()
        state.onOpenMainWindow = onOpenMainWindow

        // BLE
        bleManager.$isConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.keyboardConnected = $0 }
            .store(in: &cancellables)

        bleManager.$batteryLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.batteryLevel = $0 }
            .store(in: &cancellables)

        bleManager.$deviceName
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.deviceName = $0 }
            .store(in: &cancellables)

        // Lever: switchState == 0 即 auto；优先采用 agent 缓存（agent 占用 BLE 时主 app 自己未连接）
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

        // 语音
        voiceRelay.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state.voiceListening = $0 }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            nativeSpeech.$isRecording,
            nativeSpeech.$isLongPressRecording
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] recording, longPress in
            self?.state.voiceRecording = recording || longPress
        }
        .store(in: &cancellables)
    }
}
