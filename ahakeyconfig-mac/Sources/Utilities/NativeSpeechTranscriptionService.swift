import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import Speech

@MainActor
final class NativeSpeechTranscriptionService: ObservableObject {
    static let shared = NativeSpeechTranscriptionService()

    @Published private(set) var microphoneGranted = false
    @Published private(set) var speechRecognitionGranted = false
    @Published private(set) var siriEnabled = false
    @Published private(set) var dictationEnabled = false
    @Published private(set) var isRecording = false
    @Published private(set) var isStartingRecording = false
    @Published private(set) var statusMessage = NSLocalizedString("等待苹果原生转写就绪。", comment: "")
    @Published private(set) var transcriptPreview = ""
    @Published private(set) var lastCommittedText = ""
    @Published private(set) var deferredTranscripts: [DeferredVoiceTranscript] = []
    @Published private(set) var lastPermissionCheckSummary = NSLocalizedString("尚未检查麦克风、语音转写与 Siri 权限。", comment: "")

    // MARK: 录音触发方式配置
    /// 短按（切换式）：录音结束后是否调用 AhaType 整理
    @Published var shortPressAhaTypeEnabled: Bool = UserDefaults.standard.object(forKey: "nativeSpeech.shortPressAhaType") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shortPressAhaTypeEnabled, forKey: "nativeSpeech.shortPressAhaType") }
    }
    /// 长按模式（按住录音，松手发送）始终开启，不再由用户关闭
    @Published var longPressEnabled: Bool = true
    /// 长按模式结束后是否调用 AhaType（默认关闭：快速直发）
    @Published var longPressAhaTypeEnabled: Bool = UserDefaults.standard.object(forKey: "nativeSpeech.longPressAhaType") as? Bool ?? false {
        didSet { UserDefaults.standard.set(longPressAhaTypeEnabled, forKey: "nativeSpeech.longPressAhaType") }
    }
    /// 长按判定阈值（毫秒）
    @Published var longPressThresholdMs: Int = UserDefaults.standard.object(forKey: "nativeSpeech.longPressThresholdMs") as? Int ?? 500 {
        didSet { UserDefaults.standard.set(longPressThresholdMs, forKey: "nativeSpeech.longPressThresholdMs") }
    }

    /// 当前是否处于长按录音模式（按住中，松手会直接发送）
    @Published private(set) var isLongPressRecording = false

    private var longPressTimerWork: DispatchWorkItem?
    private var voicePressGate = NativeVoicePressGate()
    private var pressedPolicy: VoiceProcessingPolicy?
    @MainActor
    private final class Recording {
        let id: UUID
        let capture: NativeSpeechCapturing
        let policy: VoiceRecordingPolicySnapshot
        var accumulator = SpeechTranscriptAccumulator()
        var text = ""
        var finishing = false
        var closed = false
        var finalizeWorkItem: DispatchWorkItem?
        init(id: UUID, capture: NativeSpeechCapturing, policy: VoiceRecordingPolicySnapshot) {
            self.id = id; self.capture = capture; self.policy = policy
        }
    }
    private var currentCapture: Recording?
    private var finishingCaptures: [UUID: Recording] = [:]
    private var recordingPolicy: VoiceRecordingPolicySnapshot? { currentCapture?.policy }
    private var recordingGeneration = UUID()

    var legacyProcessingPolicy: VoiceProcessingPolicy {
        .init(shortPressAhaType: shortPressAhaTypeEnabled, longPressAhaType: longPressAhaTypeEnabled,
              longPressThresholdMs: longPressThresholdMs)
    }
    private var startupTask: Task<Void, Never>?
    private let captureFactory: () -> NativeSpeechCapturing
    private let authorizationCheck: (() -> Bool)?
    private let hudHandler: ((VoiceStatusHUDState, TimeInterval?) -> Void)?
    private let diagnosticSink: ((String) -> Void)?
    private let textInjector: ((String) -> Bool)?
    private var hasActiveCapture: Bool { isRecording || isStartingRecording }


    private let syntheticEventUserData: Int64 = 0x4148414B

    init(captureFactory: @escaping () -> NativeSpeechCapturing = { NativeSpeechCaptureSession() },
         authorizationCheck: (() -> Bool)? = nil,
         hud: ((VoiceStatusHUDState, TimeInterval?) -> Void)? = nil,
         diagnosticSink: ((String) -> Void)? = nil,
         textInjector: ((String) -> Bool)? = nil) {
        self.captureFactory = captureFactory
        self.authorizationCheck = authorizationCheck
        self.hudHandler = hud
        self.diagnosticSink = diagnosticSink
        self.textInjector = textInjector
    }

    private func presentHUD(_ state: VoiceStatusHUDState, autoHideAfter delay: TimeInterval? = nil) {
        if let hudHandler { hudHandler(state, delay) }
        else { VoiceStatusHUDController.shared.show(state, autoHideAfter: delay) }
    }

    func start() {
        if hudHandler == nil { VoiceStatusHUDController.shared.prepare() }
        AhaTypeTextOptimizer.shared.refreshFromDisk()
        refreshPermissions(requestIfNeeded: false)
    }

    /// - Parameter deferredTCCRequery: 与 `VoiceRelayService` 一致：用户点「重新检查」时延后一拍再读，避免 TCC 状态未刷新时界面像「没反应」。
    func refreshPermissions(requestIfNeeded: Bool = false, deferredTCCRequery: Bool = false) {
        if requestIfNeeded {
            performPermissionRead(requestIfNeeded: true)
            return
        }
        if deferredTCCRequery {
            lastPermissionCheckSummary = NSLocalizedString("正在检查麦克风与语音转写权限…", comment: "")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(450) * 1_000_000)
                self.performPermissionRead(requestIfNeeded: false)
                if !self.microphoneGranted || !self.speechRecognitionGranted {
                    try? await Task.sleep(nanoseconds: UInt64(800) * 1_000_000)
                    self.performPermissionRead(requestIfNeeded: false)
                }
            }
            return
        }
        performPermissionRead(requestIfNeeded: false)
    }

    private func performPermissionRead(requestIfNeeded: Bool) {
        let currentMicGranted = Self.isMicrophoneGranted()

        let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        let currentSpeechGranted = currentSpeechStatus == .authorized
        let currentSiriEnabled = Self.readBooleanPreference(
            domain: "com.apple.assistant.support",
            key: "Assistant Enabled"
        ) ?? false
        let currentDictationEnabled = Self.readBooleanPreference(
            domain: "com.apple.assistant.support",
            key: "Dictation Enabled"
        ) ?? Self.readBooleanPreference(
            domain: "com.apple.HIToolbox",
            key: "AppleDictationAutoEnable"
        ) ?? false

        if requestIfNeeded {
            if Self.isMicrophoneUndetermined() {
                // 先弹麦克风，用户响应后再检查语音识别，避免两个弹框同时排队、顺序混乱
                Self.requestMicrophoneAccess {
                    Task { @MainActor in
                        self.refreshPermissions()
                        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                            SFSpeechRecognizer.requestAuthorization { _ in
                                Task { @MainActor in self.refreshPermissions() }
                            }
                        }
                    }
                }
                return
            }

            if currentSpeechStatus == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { _ in
                    Task { @MainActor in
                        self.refreshPermissions()
                    }
                }
            }
        }

        let timeLabel = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        microphoneGranted = currentMicGranted
        speechRecognitionGranted = currentSpeechGranted
        siriEnabled = currentSiriEnabled
        dictationEnabled = currentDictationEnabled
        lastPermissionCheckSummary =
            "麦克风 \(currentMicGranted ? "已开启" : "未开启") · 语音转写 \(currentSpeechGranted ? "已开启" : "未开启") · Siri \(currentSiriEnabled ? "已开启" : "未开启") · 听写 \(currentDictationEnabled ? "已开启" : "未开启") · 检查于 \(timeLabel)"

        if !currentMicGranted || !currentSpeechGranted || !currentSiriEnabled || !currentDictationEnabled {
            statusMessage = NSLocalizedString("还缺苹果原生语音权限，请先打开麦克风、语音转写、Siri 与听写。", comment: "")
        } else if !hasActiveCapture {
            statusMessage = NSLocalizedString("苹果原生转写已就绪，按一次语音键开始，再按一次结束。", comment: "")
        }

        appendDiagnostic("permissions mic=\(currentMicGranted) speech=\(currentSpeechGranted) siri=\(currentSiriEnabled) dictation=\(currentDictationEnabled)")
    }

    // MARK: - 语音键事件入口（VoiceRelayService 调用）

    /// keyDown 时调用：若长按模式启用，开启长按计时器；否则立即开始录音或等 keyUp 切换。
    func handleVoiceKeyDown(trigger: CGKeyCode, policy: VoiceProcessingPolicy? = nil) {
        guard let ticket = voicePressGate.begin(code: trigger) else { return }
        let policy = policy ?? legacyProcessingPolicy
        pressedPolicy = policy
        if longPressEnabled, !hasActiveCapture {
            // 启动长按计时：阈值内松开 → 短按；超时后仍按着 → 进入长按录音
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.voicePressGate.isCurrent(ticket) else { return }
                self.longPressTimerWork = nil
                if !self.hasActiveCapture {
                    self.isLongPressRecording = true
                    self.startRecording(policy: policy, gesture: .longPress)
                    self.appendDiagnostic("long press threshold reached → start long press recording")
                }
            }
            longPressTimerWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + policy.thresholdSeconds,
                execute: work
            )
        } else if !longPressEnabled {
            // 无长按：keyDown 直接切换（兼容旧行为）
            if hasActiveCapture { stopRecording() }
            else { startRecording(policy: policy, gesture: .shortPress) }
        }
        // 若 longPressEnabled 且已在录音中，keyDown 不做任何事，等 keyUp 判断
    }

    /// keyUp 时调用：若长按模式活跃 → 结束并直接发送；否则短按切换。
    func handleVoiceKeyUp(trigger: CGKeyCode) {
        guard voicePressGate.end(code: trigger) else { return }
        let policy = pressedPolicy ?? legacyProcessingPolicy
        pressedPolicy = nil
        if isLongPressRecording {
            // 长按录音结束：停止并按长按配置决定是否用 AhaType
            isLongPressRecording = false
            longPressTimerWork?.cancel()
            longPressTimerWork = nil
            appendDiagnostic("long press key up → stop + \((recordingPolicy?.usesAhaType ?? longPressAhaTypeEnabled) ? "ahatype" : "direct")")
            stopRecording(bypassAhaType: !longPressAhaTypeEnabled)
            return
        }

        if let work = longPressTimerWork {
            // 计时器还没触发 → 短按，取消计时并切换录音
            work.cancel()
            longPressTimerWork = nil
            appendDiagnostic("short press (keyUp before threshold) → toggle")
            if hasActiveCapture {
                stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
            } else {
                startRecording(policy: policy, gesture: .shortPress)
            }
        } else if longPressEnabled, hasActiveCapture {
            // 长按模式开启时，短按第一次已进入切换式录音；第二次短按没有 timer，
            // 仍应按短按配置结束录音，保持“按一次开始，再按一次结束”的体验。
            appendDiagnostic("short press while recording → stop")
            stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
        } else if !longPressEnabled {
            // 无长按模式：keyDown 已处理，keyUp 不重复
        }
    }

    /// Listening stops must cancel a pending short-press timer without turning
    /// its cancellation into the keyUp gesture that starts a new recording.
    func cancelPendingVoiceKeyPress() {
        voicePressGate.cancel()
        pressedPolicy = nil
        longPressTimerWork?.cancel()
        longPressTimerWork = nil
        if isLongPressRecording || isStartingRecording {
            isLongPressRecording = false
            stopRecording(bypassAhaType: !longPressAhaTypeEnabled)
        }
    }

    func toggleRecordingFromVoiceKey() {
        if hasActiveCapture {
            stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
        } else {
            startRecording()
        }
    }

    func stopRecording() {
        stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
    }

    func requestMicrophonePermission() {
        if Self.isMicrophoneUndetermined() {
            Self.requestMicrophoneAccess {
                Task { @MainActor in
                    self.refreshPermissions()
                    // macOS 26 上 requestRecordPermission 可能静默返回、不弹窗；
                    // 若 completion 回来权限仍是 undetermined，说明系统没有显示弹框，
                    // 直接引导用户去系统设置手动开启。
                    if Self.isMicrophoneUndetermined() {
                        self.openMicrophoneSystemSettings()
                    }
                }
            }
        } else if Self.isMicrophoneDenied() {
            Task { @MainActor in
                self.attemptResetAndRequestMicrophonePermission()
            }
        } else {
            refreshPermissions()
        }
    }

    private func openMicrophoneSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    private func attemptResetAndRequestMicrophonePermission() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("麦克风权限已被拒绝", comment: "")
        alert.informativeText = NSLocalizedString("需要重置麦克风权限才能重新授权。", comment: "")
        alert.addButton(withTitle: NSLocalizedString("重置并授权", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("打开系统设置", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("取消", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            DispatchQueue.global(qos: .userInitiated).async {
                PermissionSignatureChecker.resetMicrophonePermission { success, message in
                    DispatchQueue.main.async {
                        if success {
                            // 重置成功后直接重新请求，TCC 记录已清空无需重启
                            Self.requestMicrophoneAccess {
                                Task { @MainActor in
                                    self.refreshPermissions()
                                    // 若弹框未出现（macOS 26 静默返回），直接打开系统设置
                                    if !Self.isMicrophoneGranted() {
                                        self.openMicrophoneSystemSettings()
                                    }
                                }
                            }
                        } else {
                            // tccutil 失败（SIP 开启时普通进程无权限），引导到系统设置
                            print("[NativeSpeech] tccutil reset failed: \(message)")
                            self.openMicrophoneSystemSettings()
                        }
                    }
                }
            }
        } else if response == .alertSecondButtonReturn {
            openMicrophoneSystemSettings()
        }
    }

    func requestSpeechRecognitionPermission() {
        let status = SFSpeechRecognizer.authorizationStatus()
        appendDiagnostic("requestSpeechRecognitionPermission status=\(status.rawValue)")
        switch status {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    self.refreshPermissions()
                }
            }
        case .denied, .restricted:
            Task { @MainActor in
                self.attemptResetAndRequestSpeechRecognitionPermission()
            }
        default:
            refreshPermissions()
        }
    }

    private func attemptResetAndRequestSpeechRecognitionPermission() {
        let bundleId = Bundle.main.bundleIdentifier ?? "lab.jawa.ahakeyconfig"
        appendDiagnostic("attemptResetAndRequestSpeechRecognition bundleId=\(bundleId)")

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("语音识别权限已被拒绝", comment: "")
        alert.informativeText = NSLocalizedString("需要重置语音识别权限才能继续。点击「重置」后需重启应用才能重新授权。", comment: "")
        alert.addButton(withTitle: NSLocalizedString("重置并重启", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("打开系统设置", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("取消", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = ["reset", "SpeechRecognition", bundleId]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    print("[NativeSpeech] tccutil reset SpeechRecognition status=\(task.terminationStatus) output=\(output)")
                } catch {
                    print("[NativeSpeech] tccutil reset SpeechRecognition error=\(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        } else if response == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func stopRecording(bypassAhaType: Bool) {
        if isStartingRecording {
            cancelRecognitionPipeline()
            isLongPressRecording = false
            statusMessage = NSLocalizedString("已取消启动录音。", comment: "")
            presentHUD(.init(kind: .warning, title: NSLocalizedString("已取消录音", comment: ""),
                subtitle: NSLocalizedString("尚未开始采集语音", comment: "")), autoHideAfter: 1.5)
            appendDiagnostic("cancelled pending audio startup")
            return
        }
        guard isRecording, let recording = currentCapture else { return }
        let bypassAhaType = !recording.policy.usesAhaType
        recording.finishing = true
        finishingCaptures[recording.id] = recording
        isRecording = false
        statusMessage = NSLocalizedString("正在结束录音并整理文字…", comment: "")
        presentHUD(.recognizing)
        appendDiagnostic("stop recording requested bypassAhaType=\(bypassAhaType)")
        Task { @MainActor in
            await recording.capture.finish()
            guard !recording.closed else { return }
            let work = DispatchWorkItem { [weak self, weak recording] in
                guard let self, let recording, !recording.closed else { return }
                self.finalizeCurrentTranscriptIfNeeded(reason: "timeout_finalize", recording: recording)
            }
            recording.finalizeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    private func startRecording(policy: VoiceProcessingPolicy? = nil,
                                gesture: VoiceRecordingPolicySnapshot.Gesture = .shortPress) {
        guard authorizationCheck?() ?? (microphoneGranted && speechRecognitionGranted && siriEnabled && dictationEnabled) else {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            refreshPermissions(requestIfNeeded: true)
            statusMessage = missingPermissionMessage(micStatus: micStatus, speechStatus: speechStatus,
                siriEnabled: siriEnabled, dictationEnabled: dictationEnabled)
            appendDiagnostic("blocked start recording micStatus=\(micStatus.rawValue) speechStatus=\(speechStatus.rawValue)")
            if !VoiceRelayService.shared.isPermissionOnboardingSuppressed { VoiceRelayService.shared.showsPermissionOnboarding = true }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let previous = currentCapture {
            if previous.finishing { currentCapture = nil }
            else { cancelRecognitionPipeline() }
        }
        let generation = UUID()
        recordingGeneration = generation
        let snapshot = VoiceRecordingPolicySnapshot(policy: policy ?? legacyProcessingPolicy,
            gesture: gesture, ahaTypeEnabledAtStart: AhaTypeTextOptimizer.shared.isEnabled)
        transcriptPreview = ""
        lastCommittedText = ""
        let capture = captureFactory()
        let startupStartedAt = ProcessInfo.processInfo.systemUptime
        let recording = Recording(id: generation, capture: capture, policy: snapshot)
        currentCapture = recording
        isStartingRecording = true
        statusMessage = NSLocalizedString("正在启动麦克风，显示录音中后开始说话。", comment: "")
        presentHUD(.starting)
        appendDiagnostic("audio startup requested")
        startupTask = Task { @MainActor in
            do {
                let locale = try await capture.start { [weak self, weak recording] update in
                    Task { @MainActor in
                        guard let self, let recording, !recording.closed else { return }
                        self.handleRecognition(update, recording: recording)
                    }
                }
                guard self.recordingGeneration == generation, self.isStartingRecording, !Task.isCancelled else {
                    capture.cancel()
                    self.appendDiagnostic("discarded stale audio startup")
                    return
                }
                self.startupTask = nil
                self.isStartingRecording = false
                self.isRecording = true
                self.statusMessage = NSLocalizedString("苹果原生转写录音中… 再按一次语音键结束。", comment: "")
                self.presentHUD(.recording)
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - startupStartedAt) * 1_000)
                self.appendDiagnostic("start recording locale=\(locale) startupMs=\(elapsed)")
            } catch {
                guard self.recordingGeneration == generation else { return }
                self.startupTask = nil
                self.cancelRecognitionPipeline()
                self.isLongPressRecording = false
                self.statusMessage = error.localizedDescription
                self.presentHUD(.init(kind: .warning, title: NSLocalizedString("无法开始录音", comment: ""),
                    subtitle: error.localizedDescription), autoHideAfter: 3)
                self.appendDiagnostic("audio startup failed")
            }
        }
    }

    private func handleRecognition(_ update: NativeSpeechRecognitionUpdate, recording: Recording) {
        guard !recording.closed else { return }
        if let text = update.text {
            if !text.isEmpty {
                recording.text = recording.accumulator.apply(text, completion: update.completion)
                if currentCapture === recording { transcriptPreview = recording.text }
            }
            appendDiagnostic("partial result=\(text) isFinal=\(update.isFinal)")
            if update.isFinal {
                finalizeCurrentTranscriptIfNeeded(reason: "final_result", recording: recording)
                return
            }
        }
        if let error = update.errorDescription {
            appendDiagnostic("recognition error: \(error)")
            if !recording.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeCurrentTranscriptIfNeeded(reason: "error_with_text", recording: recording)
            } else {
                let isForeground = recordingGeneration == recording.id
                closeRecording(recording)
                if isForeground {
                    statusMessage = "苹果原生转写失败：\(error)"
                    presentHUD(.init(kind: .warning, title: NSLocalizedString("识别失败", comment: ""),
                        subtitle: NSLocalizedString("请重试或检查语音权限", comment: "")), autoHideAfter: 2)
                }
            }
        }
    }

    private func finalizeCurrentTranscriptIfNeeded(reason: String, recording: Recording) {
        guard !recording.closed else {
            appendDiagnostic("skip duplicate finalize reason=\(reason)")
            return
        }
        let finalization = recording.accumulator.finalization
        let capturedPolicy = recording.policy
        let isForeground = recordingGeneration == recording.id
        closeRecording(recording)
        let text: String
        switch finalization {
        case .ready(let value): text = value
        case .review(let previous, let latest):
            deferredTranscripts.append(.init(text: latest, requiresReview: true, previousText: previous))
            if isForeground {
                statusMessage = NSLocalizedString("转写内容尚未完整确认，已保留供核对，未自动粘贴。", comment: "")
                presentHUD(.init(kind: .warning, title: NSLocalizedString("请核对转写内容", comment: ""),
                    subtitle: NSLocalizedString("文字已保留在语音设置中", comment: "")), autoHideAfter: 3)
            }
            appendDiagnostic("finalize retained for review reason=\(reason)")
            return
        case .empty: text = ""
        }

        guard !text.isEmpty else {
            if isForeground {
                statusMessage = NSLocalizedString("未识别到有效语音内容。", comment: "")
                presentHUD(.empty, autoHideAfter: 1.8)
            }
            appendDiagnostic("finalize empty reason=\(reason)")
            return
        }

        let willUseAhaType = capturedPolicy.usesAhaType
        if isForeground {
            statusMessage = willUseAhaType ? NSLocalizedString("AhaType 整理中…", comment: "") : NSLocalizedString("准备粘贴…", comment: "")
            presentHUD(willUseAhaType ? .ahaType : .pasting)
        }
        appendDiagnostic("finalize begin reason=\(reason) bypass=\(!willUseAhaType) rawText=\(text)")

        let completionTicket = recording.id
        Task { @MainActor in
            var cloudTimedOut = false
            var cloudFailure: String?
            let result = await VoiceTranscriptCompletion.run(text: text, ticket: completionTicket,
                currentTicket: { self.recordingGeneration }, process: { source in
                    if willUseAhaType {
                        let processed = await AhaTypeTextOptimizer.shared.processResultIfEnabled(source, enabledForRecording: true, onTimeout: { cloudTimedOut = true })
                        cloudFailure = processed.failureReason
                        return processed.text
                    }
                    return source
                })
            let output: String
            switch result {
            case .ready(let value):
                guard self.recordingGeneration == completionTicket else {
                    self.deferredTranscripts.append(.init(text: value))
                    return
                }
                output = value
            case .deferred(let value):
                self.deferredTranscripts.append(.init(text: value))
                self.appendDiagnostic("late completion retained for explicit copy")
                return
            }
            if self.injectText(output) {
                self.lastCommittedText = output
                self.statusMessage = output == text ? "已写入：\(output)" : "AhaType 已整理并写入：\(output)"
                if cloudTimedOut {
                    self.statusMessage = NSLocalizedString("云端整理超时，已使用原始转写。", comment: "")
                    presentHUD(.init(kind: .warning, title: NSLocalizedString("已写入原文", comment: ""),
                        subtitle: NSLocalizedString("云端整理超时，请稍后重试", comment: "")), autoHideAfter: 3)
                } else if let cloudFailure {
                    self.statusMessage = cloudFailure
                    presentHUD(.rawWritten, autoHideAfter: 2.4)
                } else { presentHUD(.done, autoHideAfter: 1.4) }
                self.appendDiagnostic("finalize success reason=\(reason) rawText=\(text) outputText=\(output)")
            } else {
                self.statusMessage = NSLocalizedString("识别完成，但写入当前光标失败。", comment: "")
                presentHUD(.failed, autoHideAfter: 2.0)
                self.appendDiagnostic("finalize inject failed reason=\(reason) text=\(output)")
            }
        }
    }

    func editDeferredTranscript(id: UUID, text: String) {
        guard let index = deferredTranscripts.firstIndex(where: { $0.id == id && $0.requiresReview }) else { return }
        deferredTranscripts[index].text = text
    }

    func copyDeferredTranscript(id: UUID, confirmedReview: Bool = false) {
        guard let item = deferredTranscripts.first(where: { $0.id == id }),
              !item.requiresReview || confirmedReview,
              !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(item.text, forType: .string) {
            deferredTranscripts.removeAll { $0.id == id }
        }
    }

    private func closeRecording(_ recording: Recording) {
        recording.closed = true
        recording.finalizeWorkItem?.cancel()
        recording.finalizeWorkItem = nil
        recording.capture.cancel()
        finishingCaptures[recording.id] = nil
        if currentCapture === recording {
            currentCapture = nil
            startupTask?.cancel(); startupTask = nil
            isStartingRecording = false
            isRecording = false
            isLongPressRecording = false
        }
    }

    private func cancelRecognitionPipeline() {
        recordingGeneration = UUID()
        if let recording = currentCapture { closeRecording(recording) }
        startupTask?.cancel(); startupTask = nil
        isStartingRecording = false
        isRecording = false
    }

    private func missingPermissionMessage(
        micStatus: AVAuthorizationStatus,
        speechStatus: SFSpeechRecognizerAuthorizationStatus,
        siriEnabled: Bool,
        dictationEnabled: Bool
    ) -> String {
        var missing: [String] = []
        if micStatus != .authorized {
            missing.append(NSLocalizedString("麦克风", comment: ""))
        }
        if speechStatus != .authorized {
            missing.append(NSLocalizedString("语音转写", comment: ""))
        }
        if !siriEnabled {
            missing.append("Siri")
        }
        if !dictationEnabled {
            missing.append(NSLocalizedString("听写", comment: ""))
        }
        return "还缺\(missing.joined(separator: "、"))权限。请先在系统设置里打开后，再按一次语音键。"
    }

    // MARK: - 麦克风权限辅助（macOS 14+ 用 AVAudioApplication，旧系统回退 AVCaptureDevice）

    private static func isMicrophoneGranted() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    private static func isMicrophoneUndetermined() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .undetermined
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        }
    }

    private static func isMicrophoneDenied() -> Bool {
        if #available(macOS 14.0, *) {
            let p = AVAudioApplication.shared.recordPermission
            return p == .denied
        } else {
            let s = AVCaptureDevice.authorizationStatus(for: .audio)
            return s == .denied || s == .restricted
        }
    }

    private static func requestMicrophoneAccess(completion: @escaping () -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { _ in completion() }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { _ in completion() }
        }
    }

    private static func readBooleanPreference(domain: String, key: String) -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return nil
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func injectText(_ text: String) -> Bool {
        if let textInjector { return textInjector(text) }
        guard !text.isEmpty else { return false }
        guard CGPreflightPostEventAccess() else {
            appendDiagnostic("inject denied: no post event access")
            return false
        }

        // 走剪贴板 + ⌘V 的方式：
        // Electron / Chromium 应用（Cursor、VS Code、Slack 等）会吞掉
        // CGEvent.keyboardSetUnicodeString 合成的 Unicode 键盘事件，所以
        // 用标准的粘贴路径更通用稳定。粘贴完成后恢复原剪贴板内容。
        if injectViaPaste(text: text) {
            return true
        }

        // 理论上不会落到这里——保留 Unicode-synthesis 作为 last-resort fallback。
        appendDiagnostic("inject fallback to unicode-synthesis")
        for scalar in text.utf16 {
            var unit = scalar
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                return false
            }

            withUnsafePointer(to: &unit) { pointer in
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
            }

            down.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
            up.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(5_000)
        }

        return true
    }

    /// 用 NSPasteboard + 合成 ⌘V 的方式把 `text` 注入到当前焦点位置。
    /// 返回 true 表示已投递粘贴事件；之后会异步恢复原剪贴板内容。
    private func injectViaPaste(text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // 备份当前剪贴板（保留所有类型的数据，兼容图片/富文本）
        var backup: [(NSPasteboard.PasteboardType, Data)] = []
        if let types = pasteboard.types {
            for type in types {
                if let data = pasteboard.data(forType: type) {
                    backup.append((type, data))
                }
            }
        }

        pasteboard.clearContents()
        let wrote = pasteboard.setString(text, forType: .string)
        guard wrote else {
            appendDiagnostic("paste inject failed: pasteboard setString returned false")
            restorePasteboard(backup: backup)
            return false
        }

        // 合成 ⌘V —— virtualKey 0x09 = V（kVK_ANSI_V）
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            appendDiagnostic("paste inject failed: cannot create CGEvent")
            restorePasteboard(backup: backup)
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        appendDiagnostic("paste inject posted ⌘V for text.count=\(text.count)")

        // 给目标 app 足够时间消费粘贴事件再恢复剪贴板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.restorePasteboard(backup: backup)
        }

        return true
    }

    private func restorePasteboard(backup: [(NSPasteboard.PasteboardType, Data)]) {
        guard !backup.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        for (type, data) in backup {
            pb.setData(data, forType: type)
        }
    }

    private func appendDiagnostic(_ message: String) {
        if let diagnosticSink { diagnosticSink(message); return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = diagnosticLogURL

        Task.detached {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data(line.utf8).write(to: url)
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                    try handle.close()
                }
            } catch {
                // ignore diagnostics write errors
            }
        }
    }

    private var diagnosticLogURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
        return directory.appendingPathComponent("native-speech.log")
    }
}
