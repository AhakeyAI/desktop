import AppKit
import SwiftUI
import XCTest
@testable import AhaKeyConfig

final class KeyCaptureLockTests: XCTestCase {
    @MainActor
    func testDisabledEditorCannotCaptureAKeyOrStartRecording() throws {
        var shortcut = ShortcutBinding(modifiers: [], keyCode: 0xE6)
        var recording = false
        let overlay = KeyCaptureOverlay(shortcut: Binding(get: { shortcut }, set: { shortcut = $0 }),
            isRecording: Binding(get: { recording }, set: { recording = $0 }), onActivate: {})
        let host = NSHostingView(rootView: overlay.disabled(true))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 50)
        host.layoutSubtreeIfNeeded()
        let capture = try XCTUnwrap(findCapture(in: host))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        capture.mouseDown(with: event)
        capture.keyDown(with: event)
        XCTAssertFalse(recording, "A disabled editor must not enter capture mode")
        XCTAssertEqual(shortcut.keyCode, 0xE6, "Writing must retain the submitted Right Alt draft")
        XCTAssertFalse(capture.acceptsFirstResponder)
    }

    @MainActor
    func testLockCancelsModifierAlreadyWaitingToBeCaptured() async throws {
        let capture = KeyCaptureOverlay.KeyCaptureNSView()
        var captured: [UInt16] = []
        capture.onCaptureModifier = { captured.append($0) }
        let shift = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.shift],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
        capture.flagsChanged(with: shift)
        capture.isCaptureEnabled = false
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(captured.isEmpty, "A delayed Left Shift callback must not change a submitted Right Alt")
        capture.isCaptureEnabled = true
        capture.flagsChanged(with: shift)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(captured, [56], "Capture must work again after writing finishes")
    }

    @MainActor
    func testEnabledEditorStillCapturesAKey() throws {
        var shortcut = ShortcutBinding(modifiers: [], keyCode: 0xE6)
        let overlay = KeyCaptureOverlay(shortcut: Binding(get: { shortcut }, set: { shortcut = $0 }),
            isRecording: .constant(false), onActivate: {})
        let host = NSHostingView(rootView: overlay)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 50)
        host.layoutSubtreeIfNeeded()
        let capture = try XCTUnwrap(findCapture(in: host))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        capture.keyDown(with: event)
        XCTAssertEqual(shortcut.keyCode, 4)
    }

    @MainActor
    private func findCapture(in view: NSView) -> KeyCaptureOverlay.KeyCaptureNSView? {
        if let capture = view as? KeyCaptureOverlay.KeyCaptureNSView { return capture }
        return view.subviews.lazy.compactMap { self.findCapture(in: $0) }.first
    }
}
