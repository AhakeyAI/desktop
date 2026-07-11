import AppKit
import Foundation

/// Posts a configured shortcut to the system (used by VibeBar virtual keyboard mapping).
enum ShortcutInjection {
    static func postTap(_ shortcut: ShortcutBinding) {
        guard shortcut.isConfigured else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        var flags = CGEventFlags()
        for modifier in shortcut.orderedModifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            }
        }
        guard let virtualKey = cgKeyCode(forHIDUsage: shortcut.keyCode) else { return }
        postKey(virtualKey, keyDown: true, flags: flags, source: source)
        postKey(virtualKey, keyDown: false, flags: flags, source: source)
    }

    static func postKeyDraft(_ key: AhaKeyKeyDraft) {
        if key.usesMacro { return }
        postTap(key.shortcut)
    }

    private static func postKey(_ virtualKey: CGKeyCode, keyDown: Bool, flags: CGEventFlags, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func cgKeyCode(forHIDUsage hidCode: UInt8) -> CGKeyCode? {
        switch hidCode {
        case HIDUsage.f18: return 79
        case HIDUsage.f19: return 80
        case HIDUsage.enter: return 36
        case HIDUsage.escape: return 53
        case HIDUsage.backspace: return 51
        case HIDUsage.space: return 49
        default: return nil
        }
    }
}
