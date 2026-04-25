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
    @Published private(set) var isRecording = false
    @Published private(set) var statusMessage = "等待苹果原生转写就绪。"
    @Published private(set) var transcriptPreview = ""
    @Published private(set) var lastCommittedText = ""
    @Published private(set) var lastPermissionCheckSummary = "尚未检查麦克风与语音转写权限。"

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalizeWorkItem: DispatchWorkItem?
    private var currentTranscript = ""
    private var didRequestPermissionsThisLaunch = false

    private let syntheticEventUserData: Int64 = 0x4148414B

    private init() { }

    func start() {
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
                try? await Task.sleep(for: .milliseconds(200))
                self.performPermissionRead(requestIfNeeded: false)
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
        lastPermissionCheckSummary =
            "麦克风 \(currentMicGranted ? "已开启" : "未开启") · 语音转写 \(currentSpeechGranted ? "已开启" : "未开启") · 检查于 \(timeLabel)"

        if !currentMicGranted || !currentSpeechGranted {
            statusMessage = "还缺苹果原生语音权限，请先打开麦克风和语音转写权限。"
        } else if !isRecording {
            statusMessage = "苹果原生转写已就绪，按一次语音键开始，再按一次结束。"
        }

        appendDiagnostic("permissions mic=\(currentMicGranted) speech=\(currentSpeechGranted)")
    }

    func toggleRecordingFromVoiceKey() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusMessage = "正在结束录音并整理文字…"
        appendDiagnostic("stop recording requested")

        finalizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finalizeCurrentTranscriptIfNeeded(reason: "timeout_finalize")
            }
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func startRecording() {
        guard microphoneGranted, speechRecognitionGranted else {
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            refreshPermissions(requestIfNeeded: true)
            statusMessage = missingPermissionMessage(micStatus: micStatus, speechStatus: speechStatus)
            appendDiagnostic("blocked start recording micStatus=\(micStatus.rawValue) speechStatus=\(speechStatus.rawValue)")
            VoiceRelayService.shared.showsPermissionOnboarding = true
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
        appendDiagnostic("start recording locale=\(recognizer.locale.identifier)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    /// 同一句：系统多以「整句前缀变长」返回，取 `newT` 即可。中间停顿后偶发只返回**新段**（无前缀关系），
    /// 若再整段赋值会顶掉前句，故在无前缀关系时**拼接**两段。
    private func applyStreamingTranscriptionPartial(_ newRaw: String) {
        let newT = newRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if newT.isEmpty { return }

        let oldT = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if oldT.isEmpty {
            currentTranscript = newT
            return
        }
        if newT.hasPrefix(oldT) {
            currentTranscript = newT
            return
        }
        if oldT.hasPrefix(newT) {
            return
        }
        currentTranscript = Self.joinDisjointTranscriptionSegments(prior: oldT, next: newT)
    }

    private static func joinDisjointTranscriptionSegments(prior: String, next: String) -> String {
        if prior.isEmpty { return next }
        if next.isEmpty { return prior }
        if let last = prior.last {
            if last == "。" || last == "！" || last == "？" {
                return prior + next
            }
            if last == "." || last == "!" || last == "?" {
                return prior + " " + next
            }
        }
        return prior + " " + next
    }

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
                finalizeCurrentTranscriptIfNeeded(reason: "final_result")
                return
            }
        }

        if let error {
            appendDiagnostic("recognition error: \(error.localizedDescription)")
            if !currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalizeCurrentTranscriptIfNeeded(reason: "error_with_text")
            } else {
                cancelRecognitionPipeline()
                statusMessage = "苹果原生转写失败：\(error.localizedDescription)"
            }
        }
    }

    private func finalizeCurrentTranscriptIfNeeded(reason: String) {
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil

        let text = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRecognitionPipeline()

        guard !text.isEmpty else {
            statusMessage = "未识别到有效语音内容。"
            appendDiagnostic("finalize empty reason=\(reason)")
            return
        }

        if injectText(text) {
            lastCommittedText = text
            statusMessage = "已写入：\(text)"
            appendDiagnostic("finalize success reason=\(reason) text=\(text)")
        } else {
            statusMessage = "识别完成，但写入当前光标失败。"
            appendDiagnostic("finalize inject failed reason=\(reason) text=\(text)")
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
        speechStatus: SFSpeechRecognizerAuthorizationStatus
    ) -> String {
        if micStatus != .authorized && speechStatus != .authorized {
            return "还缺麦克风和语音转写权限。请先在系统设置里放开这两项，再按一次语音键。"
        }
        if micStatus != .authorized {
            return "还缺麦克风权限。请先在系统设置里给 AhaKey Studio 打开麦克风，再按一次语音键。"
        }
        return "还缺语音转写权限。请先在系统设置里给 AhaKey Studio 打开语音转写，再按一次语音键。"
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
