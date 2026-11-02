import AppKit
import SwiftUI

struct KeyCaptureOverlay: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var shortcut: ShortcutBinding
    @Binding var isRecording: Bool
    let onActivate: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        configure(nsView)
        if isRecording && isEnabled {
            DispatchQueue.main.async {
                guard nsView.isCaptureEnabled else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func configure(_ view: KeyCaptureNSView) {
        view.isCaptureEnabled = isEnabled
        view.onBeginRecording = {
            guard isEnabled else { return }
            onActivate()
            isRecording = true
        }
        view.onCapture = { event in
            guard isEnabled else { return }
            guard let hidCode = HIDUsage.hidCode(forMacKeyCode: event.keyCode) else {
                NSSound.beep()
                isRecording = false
                return
            }
            shortcut = ShortcutBinding(
                modifiers: shortcutModifiers(from: event.modifierFlags),
                keyCode: hidCode
            )
            isRecording = false
        }
        view.onCaptureModifier = { keyCode in
            guard isEnabled else { return }
            guard let hidCode = HIDUsage.hidCode(forMacKeyCode: keyCode) else {
                NSSound.beep()
                isRecording = false
                return
            }
            shortcut = ShortcutBinding(modifiers: [], keyCode: hidCode)
            isRecording = false
        }
    }

    static func dismantleNSView(_ nsView: KeyCaptureNSView, coordinator: ()) {
        nsView.isCaptureEnabled = false
        nsView.onBeginRecording = nil
        nsView.onCapture = nil
        nsView.onCaptureModifier = nil
    }

    final class KeyCaptureNSView: NSView {
        var isCaptureEnabled = true {
            didSet {
                if !isCaptureEnabled {
                    pendingModifierCapture?.cancel()
                    pendingModifierCapture = nil
                    if window?.firstResponder === self { window?.makeFirstResponder(nil) }
                }
            }
        }
        var onBeginRecording: (() -> Void)?
        var onCapture: ((NSEvent) -> Void)?
        var onCaptureModifier: ((UInt16) -> Void)?
        private var pendingModifierCapture: DispatchWorkItem?

        override var acceptsFirstResponder: Bool { isCaptureEnabled }

        override func mouseDown(with event: NSEvent) {
            guard isCaptureEnabled else { return }
            window?.makeFirstResponder(self)
            onBeginRecording?()
        }

        override func keyDown(with event: NSEvent) {
            guard isCaptureEnabled else { return }
            pendingModifierCapture?.cancel()
            pendingModifierCapture = nil
            onCapture?(event)
        }

        override func flagsChanged(with event: NSEvent) {
            guard isCaptureEnabled else { return }
            onBeginRecording?()
            pendingModifierCapture?.cancel()
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control)
                || flags.contains(.option)
                || flags.contains(.shift)
                || flags.contains(.command)
                || flags.contains(.capsLock)
                || flags.contains(.function)
            else {
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isCaptureEnabled else { return }
                self.onCaptureModifier?(event.keyCode)
                self.pendingModifierCapture = nil
            }
            pendingModifierCapture = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
        }
    }
}

private func shortcutModifiers(from flags: NSEvent.ModifierFlags) -> [ShortcutModifier] {
    var modifiers: [ShortcutModifier] = []
    if flags.contains(.control) { modifiers.append(.control) }
    if flags.contains(.option) { modifiers.append(.option) }
    if flags.contains(.shift) { modifiers.append(.shift) }
    if flags.contains(.command) { modifiers.append(.command) }
    return modifiers
}

