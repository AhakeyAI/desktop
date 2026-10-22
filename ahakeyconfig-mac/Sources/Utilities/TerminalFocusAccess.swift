import AppKit
import ApplicationServices
import AhaKeyConfigShared

private let terminalFocusAXCallback: AXObserverCallback = { observer, _, _, _ in
    Task { @MainActor in TerminalFocusAccess.shared.observed(observer) }
}

/// Native UI metadata only; no AXValue, terminal contents, or window titles.
@MainActor
final class TerminalFocusAccess {
    static let shared = TerminalFocusAccess()
    private var observer: AXObserver?
    private var target: TerminalForegroundSource.Target?
    private var window: AXUIElement?
    private var changed: (() -> Void)?

    func frontmost() -> TerminalForegroundSource.Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let provider = app.bundleIdentifier.flatMap(TerminalSelectionQuery.Provider.init(rawValue:)),
              let instance = WS3ProcessInstance.capture(app.processIdentifier) else { return nil }
        return .init(provider: provider, instance: instance)
    }
    func start(_ target: TerminalForegroundSource.Target, changed: @escaping () -> Void) -> Bool {
        self.changed = changed
        if self.target != target || observer == nil {
            stop()
            self.changed = changed
            var created: AXObserver?
            guard AXObserverCreate(target.instance.pid, terminalFocusAXCallback, &created) == .success, let created else { return false }
            let app = AXUIElementCreateApplication(target.instance.pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification] {
                guard AXObserverAddNotification(created, app, name as CFString, nil) == .success else { return false }
            }
            observer = created; self.target = target
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        guard let observer else { return false }
        let app = AXUIElementCreateApplication(target.instance.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let focused = unsafeBitCast(value, to: AXUIElement.self)
        if window.map({ CFEqual($0, focused) }) != true {
            if let window {
                AXObserverRemoveNotification(observer, window, kAXTitleChangedNotification as CFString)
                AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString)
                AXObserverRemoveNotification(observer, window, kAXSelectedChildrenChangedNotification as CFString)
            }
            AXUIElementSetMessagingTimeout(focused, 0.1)
            guard AXObserverAddNotification(observer, focused, kAXTitleChangedNotification as CFString, nil) == .success else { return false }
            _ = AXObserverAddNotification(observer, focused, kAXUIElementDestroyedNotification as CFString, nil)
            _ = AXObserverAddNotification(observer, focused, kAXSelectedChildrenChangedNotification as CFString, nil)
            window = focused
        }
        return true
    }
    func observed(_ source: AXObserver) {
        guard let observer, CFEqual(observer, source) else { return }
        changed?()
    }
    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; target = nil; window = nil; changed = nil
    }
    func authorize(_ target: TerminalForegroundSource.Target?) async -> Bool {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            guard AXIsProcessTrustedWithOptions(options) else { return false }
        }
        guard let target, target.instance.isAlive else { return false }
        return await TerminalSelectionQuery.requestAuthorization(processID: target.instance.pid, provider: target.provider)
    }
}
