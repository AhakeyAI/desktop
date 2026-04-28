import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import os.log

private let voiceRelayLog = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "VoiceRelay")

private struct VoiceTriggerBinding: Hashable {
    let keyCode: CGKeyCode
    let modifiers: Set<ShortcutModifier>

    var displayLabel: String {
        let modifierLabel = ShortcutModifier.displayOrder
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        return modifierLabel + macKeyName(for: keyCode)
    }
}

private enum VoiceRouteAction: Hashable {
    case macOSDictation
    case functionRelay(appName: String)

    var title: String {
        switch self {
        case .macOSDictation:
            "macOS 原生语音"
        case let .functionRelay(appName):
            appName
        }
    }
}

private struct VoiceRoute: Hashable {
    let binding: VoiceTriggerBinding
    let action: VoiceRouteAction
    let mode: AhaKeyModeSlot
    let usesFactoryFallback: Bool
}

final class VoiceRelayService: ObservableObject {
    static let shared = VoiceRelayService()

    @Published private(set) var isListening = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var statusMessage = "等待语音路由初始化。"
    @Published private(set) var activeRouteSummary = "未配置语音软件。"
    @Published var showsPermissionOnboarding = false
    @Published private(set) var lastPermissionCheckSummary = "尚未检查权限。"

    private let routeQueue = DispatchQueue(label: "lab.jawa.ahakeyconfig.voiceRelay.routes")
    private var routes: [VoiceRoute] = []

    /// 我们用 CGEventTap（不是 NSEvent.addGlobalMonitor），因为只有 CGEventTap 能真正
    /// "吞掉"键盘事件，防止硬件语音键漏到前台 App（比如 Claude Code CLI / iTerm 等终端
    /// 会把 F17/F18 翻译成 xterm CSI 转义序列，用户看起来就是"乱码")。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var didRequestPermissionsThisLaunch = false

    private var shadowSuppressUntil: TimeInterval = 0

    /// 当 route.action 是 .functionRelay 时用来模拟"长按 Fn"的状态。
    /// 键盘硬件语音键是 tap（按下立即松开），但微信/Typeless 的"按住说话"要求 Fn 一直按住。
    /// 所以 app 侧做 toggle：第 1 次 tap 注入 Fn keyDown 并记下 holdingRoute；
    /// 第 2 次 tap 注入 Fn keyUp 并清空。硬件本身的 keyUp 完全忽略。
    private var holdingRoute: VoiceRoute?

    private let syntheticEventUserData: Int64 = 0x4148414B
    private let fnKeyCode: CGKeyCode = 63
    private let emojiShadowKeyCode: CGKeyCode = 179
    private let shadowSuppressSeconds: TimeInterval = 0.06

    private init() { }

    // MARK: - Public

    func start() {
        if !didRequestPermissionsThisLaunch {
            didRequestPermissionsThisLaunch = true
            refreshPermissions(requestIfNeeded: true)
        } else {
            refreshPermissions()
        }
    }

    /// - Parameter deferredTCCRequery: 用户点「重新检查」时置 true。部分 macOS 版本在刚改完系统设置、仍停留本 App 时，TCC 的 PreFlight 会短暂返回旧值；延后一拍再读更可靠，并先显示「正在检查」避免误认无响应。
    func refreshPermissions(requestIfNeeded: Bool = false, deferredTCCRequery: Bool = false) {
        if requestIfNeeded {
            performPermissionRead(requestIfNeeded: true)
            return
        }
        if deferredTCCRequery {
            DispatchQueue.main.async {
                self.lastPermissionCheckSummary = "正在检查系统权限…"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.performPermissionRead(requestIfNeeded: false)
            }
            return
        }
        performPermissionRead(requestIfNeeded: false)
    }

    private func performPermissionRead(requestIfNeeded: Bool) {
        let inputMonitoring = requestIfNeeded ? CGRequestListenEventAccess() : CGPreflightListenEventAccess()
        let postEventAccess = requestIfNeeded ? CGRequestPostEventAccess() : CGPreflightPostEventAccess()

        let accessibility: Bool
        if requestIfNeeded {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            accessibility = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibility = AXIsProcessTrusted()
        }

        let timeLabel = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let lastCheckSummary =
            "输入监控 \(inputMonitoring ? "已开启" : "未开启") · 辅助功能 \((accessibility && postEventAccess) ? "已开启" : "未开启") · 检查于 \(timeLabel)"

        DispatchQueue.main.async {
            self.inputMonitoringGranted = inputMonitoring
            self.accessibilityGranted = accessibility && postEventAccess
            self.lastPermissionCheckSummary = lastCheckSummary
            self.showsPermissionOnboarding = !(inputMonitoring && accessibility && postEventAccess)
            self.refreshStatusMessage()
        }

        let exePath = Bundle.main.executablePath ?? "unknown"
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        appendDiagnostic("permissions inputMonitoring=\(inputMonitoring) accessibility=\(accessibility) postEvent=\(postEventAccess) exe=\(exePath) bundle=\(bundleID)")

        if inputMonitoring && accessibility && postEventAccess {
            DispatchQueue.main.async {
                self.ensureMonitorsIfPossible()
            }
        } else {
            DispatchQueue.main.async {
                self.stopMonitors()
            }
        }
    }

    func dismissPermissionOnboarding() {
        showsPermissionOnboarding = false
    }

    func updateRoutes(from draft: AhaKeyStudioDraft) {
        let builtRoutes = Self.buildRoutes(from: draft)

        // 只有路由集合真的变化时才释放"按住"状态，避免 SwiftUI 频繁重建/无关 onChange
        // 间接把 functionRelay 的 hold 状态冲掉（典型表现：微信按住说话过几秒自动结束）。
        let routesChanged: Bool = routeQueue.sync { self.routes != builtRoutes }
        if routesChanged {
            releaseFunctionRelayHoldIfNeeded()
        }

        routeQueue.async {
            self.routes = builtRoutes
            let summary = builtRoutes.isEmpty
                ? "未配置语音软件。"
                : builtRoutes.map { route in
                    let fallback = route.usesFactoryFallback ? " · 出厂 F18 兼容" : ""
                    return "\(route.mode.title) \(route.action.title) ← \(route.binding.displayLabel)\(fallback)"
                }.joined(separator: " / ")

            DispatchQueue.main.async {
                self.activeRouteSummary = summary
                self.refreshStatusMessage()
            }
        }
    }

    // MARK: - Event Monitoring (CGEventTap)

    private func ensureMonitorsIfPossible() {
        guard eventTap == nil else {
            isListening = true
            refreshStatusMessage()
            return
        }

        guard inputMonitoringGranted, accessibilityGranted else {
            isListening = false
            refreshStatusMessage()
            return
        }

        // 关注 keyDown / keyUp。flagsChanged 不需要，因为 voice key 都映射为非 modifier 键。
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
            let service = Unmanaged<VoiceRelayService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handleTappedEvent(type: type, event: cgEvent)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            appendDiagnostic("event tap create failed (缺辅助功能或输入监控权限?)")
            isListening = false
            refreshStatusMessage()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        isListening = true
        appendDiagnostic("cg event tap started")
        voiceRelayLog.info("Voice relay CG event tap started")
        refreshStatusMessage()
    }

    private func stopMonitors() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
        releaseFunctionRelayHoldIfNeeded()
        isListening = false
        appendDiagnostic("cg event tap stopped")
        refreshStatusMessage()
    }

    /// CGEventTap 回调。返回 `nil` 表示吞掉事件（不让它抵达前台 App）；返回 passUnretained
    /// 表示放行。务必只在成功 match 到 route 时才吞，避免误杀普通按键。
    private func handleTappedEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 1. 系统可能因为我们耗时过长临时禁用了 tap，这里补救重启一下。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                appendDiagnostic("cg event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input")")
            }
            return Unmanaged.passUnretained(event)
        }

        // 2. 自己合成出来的事件（比如 functionRelay 注入的 Fn）必须放行，不然会死循环。
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventUserData {
            return Unmanaged.passUnretained(event)
        }

        // 3. 只关心 keyDown / keyUp；别的类型直接放行。
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = normalizedModifierSet(from: event.flags)

        // 4. Emoji 面板影子键 179 抑制：Fn 注入之后 macOS 会连带发一个影子 keyDown，
        //    把它吞掉避免 Emoji 面板闪一下。
        let now = Date().timeIntervalSinceReferenceDate
        if keyCode == emojiShadowKeyCode,
           now <= routeQueue.sync(execute: { shadowSuppressUntil })
        {
            appendDiagnostic("shadow suppress keyCode=\(keyCode) type=\(type.rawValue)")
            return nil
        }

        // 5. 匹配语音路由。没匹配就一律放行。
        guard let route = matchingRoute(forKeyCode: keyCode, flags: flags) else {
            return Unmanaged.passUnretained(event)
        }

        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        appendDiagnostic("matched keyCode=\(keyCode) type=\(type.rawValue) autorepeat=\(isAutoRepeat) route=\(route.action.title) mode=\(route.mode.rawValue)")

        switch route.action {
        case .macOSDictation:
            if type == .keyDown, !isAutoRepeat {
                Task { @MainActor in
                    NativeSpeechTranscriptionService.shared.toggleRecordingFromVoiceKey()
                }
            }
            // keyDown/keyUp 都吞掉，避免硬件发出的 F17/F18 漏到前台 App（比如 Claude CLI
            // 所在的终端会把它翻译成 \e[...~ 字样）。
            return nil

        case .functionRelay:
            // 硬件语音键是一次 tap（会同时发 keyDown/keyUp），但微信等 App 需要"按住"。
            // 所以这里只在 keyDown 触发 toggle，keyUp 忽略。
            if type == .keyDown, !isAutoRepeat {
                toggleFunctionRelayHold(for: route)
            }
            return nil
        }
    }

    private func toggleFunctionRelayHold(for route: VoiceRoute) {
        let shouldRelease: Bool = routeQueue.sync {
            if holdingRoute != nil {
                holdingRoute = nil
                return true
            } else {
                holdingRoute = route
                return false
            }
        }
        if shouldRelease {
            postFunctionKey(isKeyDown: false)
            appendDiagnostic("function relay toggle → release (\(route.action.title))")
        } else {
            postFunctionKey(isKeyDown: true)
            appendDiagnostic("function relay toggle → hold (\(route.action.title))")
        }
        // Fn 无论按下还是松开，都可能触发系统 Emoji 面板影子键，统一抑制一下。
        routeQueue.async {
            self.shadowSuppressUntil = Date().timeIntervalSinceReferenceDate + self.shadowSuppressSeconds
        }
    }

    /// 在服务停止监听、路由变化或权限失效时，保证不会把 Fn "按住"状态悬挂在系统键盘里。
    private func releaseFunctionRelayHoldIfNeeded() {
        let releasing: Bool = routeQueue.sync {
            if holdingRoute != nil {
                holdingRoute = nil
                return true
            }
            return false
        }
        if releasing {
            postFunctionKey(isKeyDown: false)
            appendDiagnostic("function relay force release")
        }
    }

    private func matchingRoute(forKeyCode keyCode: CGKeyCode, flags: Set<ShortcutModifier>) -> VoiceRoute? {
        return routeQueue.sync {
            routes.first { route in
                route.binding.keyCode == keyCode && route.binding.modifiers == flags
            }
        }
    }

    // MARK: - Posting

    private func postFunctionKey(isKeyDown: Bool) {
        appendDiagnostic("post fn keyDown=\(isKeyDown)")
        let flags: CGEventFlags = isKeyDown ? .maskSecondaryFn : []
        postKeyboardEvent(keyCode: fnKeyCode, keyDown: isKeyDown, flags: flags)
    }

    private func postKeyboardEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventUserData)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    private func refreshStatusMessage() {
        if !inputMonitoringGranted || !accessibilityGranted {
            statusMessage = "还缺系统权限：请为 AhaKey Studio 打开“输入监控”和“辅助功能”，授权后回到软件点“重新检查权限”。"
            return
        }

        guard isListening else {
            statusMessage = "语音键后台监听准备中。关闭窗口后，AhaKey Studio 也会继续驻留后台。"
            return
        }

        if activeRouteSummary == "未配置语音软件。" {
            statusMessage = "后台监听已启动，但当前没有可接管的语音软件。"
            return
        }

        statusMessage = "后台监听已启动。Mode 0 出厂 F18 也会被接管到你选中的语音软件。"
    }

    private static func buildRoutes(from draft: AhaKeyStudioDraft) -> [VoiceRoute] {
        var orderedRoutes: [VoiceRoute] = []
        var seenBindings = Set<VoiceTriggerBinding>()

        for mode in AhaKeyModeSlot.allCases {
            let voiceKey = draft.draft(for: mode).key(for: .voice)
            guard let preset = voiceKey.voicePreset,
                  preset.availableInV1,
                  preset != .custom,
                  let action = action(for: preset),
                  let binding = macBinding(for: voiceKey.shortcut)
            else { continue }

            if seenBindings.insert(binding).inserted {
                orderedRoutes.append(
                    VoiceRoute(
                        binding: binding,
                        action: action,
                        mode: mode,
                        usesFactoryFallback: false
                    )
                )
            }

            if mode == .mode0 {
                let fallback = VoiceTriggerBinding(keyCode: 79, modifiers: [])
                if seenBindings.insert(fallback).inserted {
                    orderedRoutes.append(
                        VoiceRoute(
                            binding: fallback,
                            action: action,
                            mode: mode,
                            usesFactoryFallback: true
                        )
                    )
                }
            }
        }

        return orderedRoutes
    }

    private static func action(for preset: VoicePreset) -> VoiceRouteAction? {
        switch preset {
        case .macOSNative:
            .macOSDictation
        case .typeless:
            .functionRelay(appName: "Typeless / Fn")
        case .wechat:
            .functionRelay(appName: "微信语音")
        case .claudeCode:
            // Claude Code preset 复用 macOS 原生 ASR：录音 → 识别 → ⌘V 粘到当前光标。
            // 这样按键会被我们的 monitor 吃掉，不会漏到 Claude CLI 终端里变成 CSI 乱码。
            .macOSDictation
        case .codex, .doubao, .custom:
            nil
        }
    }

    private func appendDiagnostic(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = diagnosticLogURL
        routeQueue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try line.data(using: .utf8)?.write(to: url)
                } else if let handle = try? FileHandle(forWritingTo: url) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                    try handle.close()
                }
            } catch {
                voiceRelayLog.error("voice relay diagnostic write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private var diagnosticLogURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AhaKeyConfig/diagnostics", isDirectory: true)
        return directory.appendingPathComponent("voice-relay.log")
    }
}

private func normalizedModifierSet(from flags: CGEventFlags) -> Set<ShortcutModifier> {
    var modifiers = Set<ShortcutModifier>()
    if flags.contains(.maskControl) {
        modifiers.insert(.control)
    }
    if flags.contains(.maskAlternate) {
        modifiers.insert(.option)
    }
    if flags.contains(.maskShift) {
        modifiers.insert(.shift)
    }
    if flags.contains(.maskCommand) {
        modifiers.insert(.command)
    }
    return modifiers
}

private func normalizedModifierSet(from flags: NSEvent.ModifierFlags) -> Set<ShortcutModifier> {
    var modifiers = Set<ShortcutModifier>()
    if flags.contains(.control) {
        modifiers.insert(.control)
    }
    if flags.contains(.option) {
        modifiers.insert(.option)
    }
    if flags.contains(.shift) {
        modifiers.insert(.shift)
    }
    if flags.contains(.command) {
        modifiers.insert(.command)
    }
    return modifiers
}

private func macBinding(for shortcut: ShortcutBinding) -> VoiceTriggerBinding? {
    guard let keyCode = macKeyCode(forHIDUsage: shortcut.keyCode) else { return nil }
    return VoiceTriggerBinding(keyCode: keyCode, modifiers: Set(shortcut.modifiers))
}

private func macKeyName(for keyCode: CGKeyCode) -> String {
    switch keyCode {
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    case 105: return "F13"
    case 107: return "F14"
    case 113: return "F15"
    case 106: return "F16"
    case 64: return "F17"
    case 79: return "F18"
    case 80: return "F19"
    case 36: return "Return"
    case 53: return "Escape"
    case 51: return "Delete"
    case 48: return "Tab"
    case 49: return "Space"
    case 57: return "CapsLock"
    case 117: return "ForwardDelete"
    case 124: return "→"
    case 123: return "←"
    case 125: return "↓"
    case 126: return "↑"
    case 0 ... 25:
        let letters: [CGKeyCode: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G",
            4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N",
            31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
            9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        ]
        return letters[keyCode] ?? "Key \(keyCode)"
    default:
        return "Key \(keyCode)"
    }
}

private func macKeyCode(forHIDUsage hidCode: UInt8) -> CGKeyCode? {
    switch hidCode {
    case HIDUsage.f1: return 122
    case HIDUsage.f2: return 120
    case HIDUsage.f3: return 99
    case HIDUsage.f4: return 118
    case HIDUsage.f5: return 96
    case HIDUsage.f6: return 97
    case HIDUsage.f7: return 98
    case HIDUsage.f8: return 100
    case HIDUsage.f9: return 101
    case HIDUsage.f10: return 109
    case HIDUsage.f11: return 103
    case HIDUsage.f12: return 111
    case HIDUsage.f13: return 105
    case HIDUsage.f14: return 107
    case HIDUsage.f15: return 113
    case HIDUsage.f16: return 106
    case HIDUsage.f17: return 64
    case HIDUsage.f18: return 79
    case HIDUsage.f19: return 80
    case HIDUsage.enter: return 36
    case HIDUsage.escape: return 53
    case HIDUsage.backspace: return 51
    case HIDUsage.tab: return 48
    case HIDUsage.space: return 49
    case HIDUsage.capsLock: return 57
    case HIDUsage.deleteForward: return 117
    case HIDUsage.rightArrow: return 124
    case HIDUsage.leftArrow: return 123
    case HIDUsage.downArrow: return 125
    case HIDUsage.upArrow: return 126
    case 0x04: return 0
    case 0x05: return 11
    case 0x06: return 8
    case 0x07: return 2
    case 0x08: return 14
    case 0x09: return 3
    case 0x0A: return 5
    case 0x0B: return 4
    case 0x0C: return 34
    case 0x0D: return 38
    case 0x0E: return 40
    case 0x0F: return 37
    case 0x10: return 46
    case 0x11: return 45
    case 0x12: return 31
    case 0x13: return 35
    case 0x14: return 12
    case 0x15: return 15
    case 0x16: return 1
    case 0x17: return 17
    case 0x18: return 32
    case 0x19: return 9
    case 0x1A: return 13
    case 0x1B: return 7
    case 0x1C: return 16
    case 0x1D: return 6
    case 0x1E: return 18
    case 0x1F: return 19
    case 0x20: return 20
    case 0x21: return 21
    case 0x22: return 23
    case 0x23: return 22
    case 0x24: return 26
    case 0x25: return 28
    case 0x26: return 25
    case 0x27: return 29
    default:
        return nil
    }
}
