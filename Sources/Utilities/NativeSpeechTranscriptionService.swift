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
    @Published private(set) var statusMessage = "等待苹果原生转写就绪。"
    @Published private(set) var transcriptPreview = ""
    @Published private(set) var lastCommittedText = ""
    @Published private(set) var lastPermissionCheckSummary = "尚未检查麦克风、语音转写与 Siri 权限。"

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
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizeWorkItem: DispatchWorkItem?
    private var currentTranscript = ""
    /// 防止 `isFinal`、1s 超时、`error` 回调各触发一次，导致同一段被 ⌘V 多遍
    private var hasCommittedThisRecording = false
    private var didRequestPermissionsThisLaunch = false

    private let syntheticEventUserData: Int64 = 0x4148414B

    private init() { }

    func start() {
        AhaTypeTextOptimizer.shared.refreshFromDisk()
        if !didRequestPermissionsThisLaunch {
            didRequestPermissionsThisLaunch = true
            refreshPermissions(requestIfNeeded: true)
        } else {
            refreshPermissions()
        }
    }

    /// - Parameter deferredTCCRequery: 与 `VoiceRelayService` 一致：用户点「重新检查」时延后一拍再读，避免 TCC 状态未刷新时界面像「没反应」。
    func refreshPermissions(requestIfNeeded: Bool = false, deferredTCCRequery: Bool = false) {
        if requestIfNeeded {
            performPermissionRead(requestIfNeeded: true)
            return
        }
        if deferredTCCRequery {
            lastPermissionCheckSummary = "正在检查麦克风与语音转写权限…"
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
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let currentMicGranted = micStatus == .authorized

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
            if micStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    Task { @MainActor in
                        self.refreshPermissions()
                    }
                }
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
            statusMessage = "还缺苹果原生语音权限，请先打开麦克风、语音转写、Siri 与听写。"
        } else if !isRecording {
            statusMessage = "苹果原生转写已就绪，按一次语音键开始，再按一次结束。"
        }

        appendDiagnostic("permissions mic=\(currentMicGranted) speech=\(currentSpeechGranted) siri=\(currentSiriEnabled) dictation=\(currentDictationEnabled)")
    }

    // MARK: - 语音键事件入口（VoiceRelayService 调用）

    /// keyDown 时调用：若长按模式启用，开启长按计时器；否则立即开始录音或等 keyUp 切换。
    func handleVoiceKeyDown() {
        if longPressEnabled, !isRecording {
            // 启动长按计时：阈值内松开 → 短按；超时后仍按着 → 进入长按录音
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.longPressTimerWork = nil
                if !self.isRecording {
                    self.isLongPressRecording = true
                    self.startRecording()
                    self.appendDiagnostic("long press threshold reached → start long press recording")
                }
            }
            longPressTimerWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Double(longPressThresholdMs) / 1000,
                execute: work
            )
        } else if !longPressEnabled {
            // 无长按：keyDown 直接切换（兼容旧行为）
            toggleRecordingFromVoiceKey()
        }
        // 若 longPressEnabled 且已在录音中，keyDown 不做任何事，等 keyUp 判断
    }

    /// keyUp 时调用：若长按模式活跃 → 结束并直接发送；否则短按切换。
    func handleVoiceKeyUp() {
        if isLongPressRecording {
            // 长按录音结束：停止并按长按配置决定是否用 AhaType
            isLongPressRecording = false
            longPressTimerWork?.cancel()
            longPressTimerWork = nil
            appendDiagnostic("long press key up → stop + \(longPressAhaTypeEnabled ? "ahatype" : "direct")")
            stopRecording(bypassAhaType: !longPressAhaTypeEnabled)
            return
        }

        if let work = longPressTimerWork {
            // 计时器还没触发 → 短按，取消计时并切换录音
            work.cancel()
            longPressTimerWork = nil
            appendDiagnostic("short press (keyUp before threshold) → toggle")
            if isRecording {
                stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
            } else {
                startRecording()
            }
        } else if longPressEnabled, isRecording {
            // 长按模式开启时，短按第一次已进入切换式录音；第二次短按没有 timer，
            // 仍应按短按配置结束录音，保持“按一次开始，再按一次结束”的体验。
            appendDiagnostic("short press while recording → stop")
            stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
        } else if !longPressEnabled {
            // 无长按模式：keyDown 已处理，keyUp 不重复
        }
    }

    func toggleRecordingFromVoiceKey() {
        if isRecording {
            stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
        } else {
            startRecording()
        }
    }

    func stopRecording() {
        stopRecording(bypassAhaType: !shortPressAhaTypeEnabled)
    }

    func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    self.refreshPermissions()
                }
            }
        } else {
            refreshPermissions()
        }
    }

    func requestSpeechRecognitionPermission() {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    self.refreshPermissions()
                }
            }
        } else {
            refreshPermissions()
        }
    }

    func stopRecording(bypassAhaType: Bool) {
        guard isRecording else { return }
        isRecording = false
        statusMessage = "正在结束录音并整理文字…"
        VoiceStatusHUDController.shared.show(.recognizing)
        pendingFinalizeBypassAhaType = bypassAhaType
        appendDiagnostic("stop recording requested bypassAhaType=\(bypassAhaType)")

        finalizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finalizeCurrentTranscriptIfNeeded(reason: "timeout_finalize", bypassAhaType: bypassAhaType)
            }
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func startRecording() {
        guard microphoneGranted, speechRecognitionGranted, siriEnabled, dictationEnabled else {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            refreshPermissions(requestIfNeeded: true)
            statusMessage = missingPermissionMessage(
                micStatus: micStatus,
                speechStatus: speechStatus,
                siriEnabled: siriEnabled,
                dictationEnabled: dictationEnabled
            )
            appendDiagnostic("blocked start recording micStatus=\(micStatus.rawValue) speechStatus=\(speechStatus.rawValue) siri=\(siriEnabled) dictation=\(dictationEnabled)")
            if !VoiceRelayService.shared.isPermissionOnboardingSuppressed {
                VoiceRelayService.shared.showsPermissionOnboarding = true
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let recognizer = makeSpeechRecognizer() else {
            statusMessage = "当前系统语言暂不支持苹果原生转写。"
            appendDiagnostic("speech recognizer unavailable")
            return
        }

        cancelRecognitionPipeline()
        currentTranscript = ""
        transcriptPreview = ""
        lastCommittedText = ""
        hasCommittedThisRecording = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            statusMessage = "无法启动麦克风录音。"
            appendDiagnostic("audio engine start failed: \(error.localizedDescription)")
            return
        }

        audioEngine = engine
        recognitionRequest = request
        isRecording = true
        statusMessage = "苹果原生转写录音中… 再按一次语音键结束。"
        VoiceStatusHUDController.shared.show(.recording)
        appendDiagnostic("start recording locale=\(recognizer.locale.identifier)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    /// 流式 + 同一段录音里停顿后续说：多数帧里 `formattedString` 是「从本段开录至今的整段」；  
    /// 若用英文空格去拼两段中文，或把「同一句的改判」与「下一段整句」都旧+新硬接，就会叠出很多遍。  
    /// 结束提交：另见 `hasCommittedThisRecording`。
    private func applyStreamingTranscriptionPartial(_ newRaw: String) {
        let newT = newRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if newT.isEmpty { return }

        let oldT = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if oldT.isEmpty {
            currentTranscript = newT
            return
        }
        if newT == oldT { return }
        if newT.hasPrefix(oldT) {
            currentTranscript = newT
            return
        }
        if oldT.hasPrefix(newT) {
            return
        }
        if newT.contains(oldT), newT.count > oldT.count {
            currentTranscript = newT
            return
        }
        if oldT.contains(newT) {
            return
        }
        if let merged = Self.mergeByTailHeadOverlap(prior: oldT, next: newT) {
            currentTranscript = merged
            return
        }
        if Self.commonPrefixLength(oldT, newT) >= 3 {
            currentTranscript = newT
            return
        }
        if newT.count <= 6, let a = oldT.last, let b = newT.first, Self.isCJK(a), Self.isCJK(b) {
            currentTranscript = oldT + newT
            return
        }
        if let last = oldT.last, last == "。" || last == "！" || last == "？" {
            if let b = newT.first, Self.isCJK(b) {
                currentTranscript = oldT + newT
                return
            }
        }
        // 不盲拼长串；以本次整段假设为准
        currentTranscript = newT
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var n = 0
        for (x, y) in zip(a, b) {
            if x == y { n += 1 } else { break }
        }
        return n
    }

    private static func mergeByTailHeadOverlap(prior: String, next: String) -> String? {
        if prior.isEmpty { return next }
        if next.isEmpty { return prior }
        let maxK = min(prior.count, next.count)
        guard maxK > 0 else { return nil }
        for k in stride(from: maxK, through: 1, by: -1) {
            if String(prior.suffix(k)) == String(next.prefix(k)) {
                return prior + next.dropFirst(k)
            }
        }
        return nil
    }

    private static func isCJK(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0x4E00 ... 0x9FFF).contains(v) { return true }
            if (0x3400 ... 0x4DBF).contains(v) { return true }
            if (0x3000 ... 0x303F).contains(v) { return true }
        }
        return false
    }

    private var pendingFinalizeBypassAhaType = false

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let newText = result.bestTranscription.formattedString
            // 流式结果：同一句会以前缀方式变长，直接取 new 即可；中间停顿后系统可能只返回
            // 新一段文字（不含前句），再整串赋值会顶掉前句——须按前缀关系合并，否则拼接。
            if !newText.isEmpty {
                applyStreamingTranscriptionPartial(newText)
                transcriptPreview = currentTranscript
            }
            appendDiagnostic("partial result=\(newText) isFinal=\(result.isFinal)")
            if result.isFinal {
                finalizeCurrentTranscriptIfNeeded(reason: "final_result", bypassAhaType: pendingFinalizeBypassAhaType)
                return
            }
        }

        if let error {
            appendDiagnostic("recognition error: \(error.localizedDescription)")
            if !currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeCurrentTranscriptIfNeeded(reason: "error_with_text", bypassAhaType: pendingFinalizeBypassAhaType)
            } else {
                cancelRecognitionPipeline()
                statusMessage = "苹果原生转写失败：\(error.localizedDescription)"
                VoiceStatusHUDController.shared.show(
                    VoiceStatusHUDState(kind: .warning, title: "识别失败", subtitle: "请重试或检查语音权限"),
                    autoHideAfter: 2.0
                )
            }
        }
    }

    private func finalizeCurrentTranscriptIfNeeded(reason: String, bypassAhaType: Bool = false) {
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil

        if hasCommittedThisRecording {
            appendDiagnostic("skip duplicate finalize reason=\(reason)")
            return
        }

        let text = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRecognitionPipeline()

        guard !text.isEmpty else {
            statusMessage = "未识别到有效语音内容。"
            VoiceStatusHUDController.shared.show(.empty, autoHideAfter: 1.8)
            appendDiagnostic("finalize empty reason=\(reason)")
            return
        }

        hasCommittedThisRecording = true
        let willUseAhaType = !bypassAhaType && AhaTypeTextOptimizer.shared.isEnabled
        statusMessage = willUseAhaType ? "AhaType 整理中…" : "准备粘贴…"
        VoiceStatusHUDController.shared.show(willUseAhaType ? .ahaType : .pasting)
        appendDiagnostic("finalize begin reason=\(reason) bypass=\(bypassAhaType) rawText=\(text)")

        Task { @MainActor in
            let output: String
            if willUseAhaType {
                output = await AhaTypeTextOptimizer.shared.processIfEnabled(text)
            } else {
                output = text
            }
            if self.injectText(output) {
                self.lastCommittedText = output
                self.statusMessage = output == text ? "已写入：\(output)" : "AhaType 已整理并写入：\(output)"
                VoiceStatusHUDController.shared.show(.done, autoHideAfter: 1.4)
                self.appendDiagnostic("finalize success reason=\(reason) rawText=\(text) outputText=\(output)")
            } else {
                self.statusMessage = "识别完成，但写入当前光标失败。"
                VoiceStatusHUDController.shared.show(.failed, autoHideAfter: 2.0)
                self.appendDiagnostic("finalize inject failed reason=\(reason) text=\(output)")
            }
        }
    }

    private func cancelRecognitionPipeline() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    private func makeSpeechRecognizer() -> SFSpeechRecognizer? {
        if let preferredIdentifier = Locale.preferredLanguages.first {
            let locale = Locale(identifier: preferredIdentifier)
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }

        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
            return recognizer
        }

        return nil
    }

    private func missingPermissionMessage(
        micStatus: AVAuthorizationStatus,
        speechStatus: SFSpeechRecognizerAuthorizationStatus,
        siriEnabled: Bool,
        dictationEnabled: Bool
    ) -> String {
        var missing: [String] = []
        if micStatus != .authorized {
            missing.append("麦克风")
        }
        if speechStatus != .authorized {
            missing.append("语音转写")
        }
        if !siriEnabled {
            missing.append("Siri")
        }
        if !dictationEnabled {
            missing.append("听写")
        }
        return "还缺\(missing.joined(separator: "、"))权限。请先在系统设置里打开后，再按一次语音键。"
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
