import AppKit
import Foundation
import UserNotifications

/// 实验性前台 TUI Adapter：把拨杆状态实时映射到当前前台 Kimi 会话的 `/yolo on/off`。
///
/// 限制：
/// - 默认关闭，需用户在设置中开启「实时控制当前前台 Kimi」。
/// - 仅支持 Terminal.app 和 iTerm2。
/// - 必须能确认当前聚焦 tab 的前台进程是 kimi；否则不输入任何字符。
/// - 拨杆防抖 300ms，同状态 5 秒内不重复发送。
/// - 无法确认目标或注入失败时：自动档静默跳过；手动档发高优先级警告，因为 manual
///   是安全回退方向。
enum KimiTUIAdapter {
    private static let suiteName = "lab.jawa.ahakeyconfig"
    private static let enabledKey = "kimiTUIAdapterEnabled"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static var isEnabled: Bool {
        get { sharedDefaults?.bool(forKey: enabledKey) ?? false }
        set { sharedDefaults?.set(newValue, forKey: enabledKey) }
    }

    private static let debounceIntervalMs = 300
    private static let deduplicationIntervalSec: TimeInterval = 5

    private static var lastSentMode: KimiPermissionModeController.DesiredPermissionMode?
    private static var lastSentAt: Date?
    private static var pendingWorkItem: DispatchWorkItem?

    /// 拨杆状态变化时调用。会防抖后尝试向前台 Kimi 发送 `/yolo on` 或 `/yolo off`。
    static func applyModeIfNeeded(for switchState: Int?) {
        guard isEnabled else { return }
        let mode = KimiPermissionModeController.desiredMode(for: switchState)

        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [mode] in
            performSend(mode: mode)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(debounceIntervalMs),
            execute: work
        )
    }

    private static func performSend(mode: KimiPermissionModeController.DesiredPermissionMode) {
        // 同状态去重：5 秒内不再重复发送。
        if lastSentMode == mode,
           let lastAt = lastSentAt,
           Date().timeIntervalSince(lastAt) < deduplicationIntervalSec {
            return
        }

        let target = currentTarget()
        guard target != nil else {
            KimiHookDebugLog.append(event: "kimi_tui_adapter_skip", details: [
                "reason": "target_not_confirmed",
                "mode": mode.description,
            ])
            return
        }

        let command = mode == .yolo ? "/yolo on" : "/yolo off"
        guard injectText(command, into: target!) else {
            KimiHookDebugLog.append(event: "kimi_tui_adapter_inject_failed", details: [
                "mode": mode.description,
                "command": command,
            ])
            if mode == .manual {
                notifyManualFallbackFailed()
            }
            return
        }

        lastSentMode = mode
        lastSentAt = Date()
        KimiHookDebugLog.append(event: "kimi_tui_adapter_sent", details: [
            "command": command,
            "target": target!.debugDescription,
        ])
    }

    // MARK: - 目标检测

    private struct Target: CustomDebugStringConvertible {
        let terminalBundleId: String
        let tty: String

        var debugDescription: String {
            "\(terminalBundleId)@\(tty)"
        }
    }

    private static let supportedBundleIds = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]

    private static func currentTarget() -> Target? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              supportedBundleIds.contains(bundleId) else { return nil }

        guard let tty = currentTTY(bundleId: bundleId),
              tty.hasPrefix("/dev/tty") || tty.hasPrefix("tty") else { return nil }
        let normalizedTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"

        guard let foreground = foregroundProcessForTTY(normalizedTTY),
              foreground.contains("kimi") else { return nil }

        return Target(terminalBundleId: bundleId, tty: normalizedTTY)
    }

    private static func currentTTY(bundleId: String) -> String? {
        let script: String
        switch bundleId {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
                try
                    return tty of selected tab of front window
                on error
                    return ""
                end try
            end tell
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
                try
                    return tty of current session of current window
                on error
                    return ""
                end try
            end tell
            """
        default:
            return nil
        }
        return runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func foregroundProcessForTTY(_ tty: String) -> String? {
        let device = (tty as NSString).lastPathComponent
        guard !device.isEmpty else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-t", device, "-o", "command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // ps -t <tty> -o command= 会列出该 TTY 上的所有进程；第一行通常是前台进程。
        return output.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - 输入注入

    private static func injectText(_ text: String, into target: Target) -> Bool {
        switch target.terminalBundleId {
        case "com.apple.Terminal":
            return injectViaTerminalKeystroke(text)
        case "com.googlecode.iterm2":
            return injectViaItermWrite(text)
        default:
            return false
        }
    }

    private static func injectViaTerminalKeystroke(_ text: String) -> Bool {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            tell application process "Terminal"
                set frontMost to frontmost
            end tell
        end tell
        if frontMost then
            tell application "System Events"
                keystroke "\(escaped)"
                keystroke return
            end tell
        end if
        """
        let result = runAppleScript(script)
        return result != nil
    }

    private static func injectViaItermWrite(_ text: String) -> Bool {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            try
                tell current session of current window
                    write text "\(escaped)"
                end tell
                return "ok"
            on error errMsg
                return errMsg
            end try
        end tell
        """
        let result = runAppleScript(script)
        return result?.contains("ok") == true
    }

    private static func runAppleScript(_ source: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 失败通知

    private static func notifyManualFallbackFailed() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("AhaKey 安全警告", comment: "")
        content.body = NSLocalizedString("拨杆已切到手动档，但当前 Kimi 会话可能仍处于 YOLO。请立即手动执行 /yolo off。", comment: "")
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: "lab.jawa.ahakeyconfig.kimiManualFallbackFailed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
