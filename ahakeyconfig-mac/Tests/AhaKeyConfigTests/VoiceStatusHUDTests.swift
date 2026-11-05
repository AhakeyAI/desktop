import AppKit
import XCTest
@testable import AhaKeyConfig

@MainActor
final class VoiceStatusHUDTests: XCTestCase {
    private func fixture() -> (VoiceStatusHUDController, NSPanel) {
        _ = NSApplication.shared
        let panel = NonActivatingVoiceHUDPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        return (VoiceStatusHUDController(makePanel: { panel }), panel)
    }

    func testStreamingTranscriptExpandsCapsuleWithoutTakingFocusAndShrinksAfterDone() {
        let (hud, panel) = fixture()
        defer { panel.orderOut(nil) }
        let originalKeyWindow = NSApp.keyWindow
        hud.show(.recording.showingTranscript("first phrase, then another phrase"))
        let shortHeight = panel.frame.height
        XCTAssertEqual(panel.frame.width, 360)
        XCTAssertGreaterThan(shortHeight, 58)
        XCTAssertLessThan(shortHeight, 120)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(NSApp.keyWindow === originalKeyWindow)
        hud.show(.recording.showingTranscript(String(repeating: "wrapped transcript ", count: 100)))
        XCTAssertEqual(panel.frame.width, 360, "Long recognition must wrap, never widen the capsule")
        XCTAssertGreaterThan(panel.frame.height, shortHeight)
        XCTAssertLessThanOrEqual(panel.frame.height, 120, "Transcript height must stop after three lines")
        let cappedHeight = panel.frame.height
        hud.show(.recognizing.showingTranscript(String(repeating: "wrapped transcript ", count: 1000)))
        XCTAssertEqual(panel.frame.height, cappedHeight)
        hud.show(.done)
        XCTAssertEqual(panel.frame.size, NSSize(width: 360, height: 58))
    }

    func testPendingOfferCanBeShownAgainWithoutInvokingConsent() {
        let (hud, panel) = fixture()
        defer { panel.orderOut(nil) }
        hud.offerCodexApproval { _ in XCTFail("Opening an offer is not a consent action") }
        XCTAssertTrue(panel.isVisible)
        panel.orderOut(nil)
        hud.offerCodexApproval { _ in XCTFail("An existing consent callback must not be replaced") }
        XCTAssertTrue(panel.isVisible, "An explicit setup action should reopen a hidden pending offer")
    }

    func testControllerExplicitReopenRestoresTheOfferWithoutWritingPermissions() {
        let (hud, panel) = fixture()
        defer { panel.orderOut(nil) }
        var writes = 0
        let model = CodexApprovalSetupModel(readChoice: { .undecided }, saveChoice: { _ in },
            configure: { writes += 1; return true })
        let controller = CodexApprovalSetupController(model: model, hud: hud)
        controller.requestOffer()
        XCTAssertTrue(panel.isVisible)
        panel.orderOut(nil)
        controller.requestOffer(force: true)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(panel.collectionBehavior.contains(.transient))
    }

    func testOfferWaitsForVoiceAndReturnsAfterProcessingWithoutTakingKeyFocus() {
        let (hud, panel) = fixture()
        defer { panel.orderOut(nil) }
        let originalKeyWindow = NSApp.keyWindow
        hud.show(.recording)
        hud.offerCodexApproval { _ in XCTFail("No choice was made") }
        XCTAssertEqual(panel.frame.width, 360)
        XCTAssertTrue(panel.ignoresMouseEvents)
        hud.show(.recognizing)
        XCTAssertEqual(panel.frame.width, 360)
        hud.hide()
        XCTAssertEqual(panel.frame.width, 390)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(NSApp.keyWindow === originalKeyWindow)
        XCTAssertEqual(panel.contentView?.acceptsFirstMouse(for: nil), true,
            "A nonactivating setup prompt needs to accept the first click")
    }

    func testCancelledOldHideDoesNotHideNewRecordingOrShowOfferOverIt() async throws {
        let (hud, panel) = fixture()
        defer { panel.orderOut(nil) }
        hud.show(.done, autoHideAfter: 0.01)
        hud.offerCodexApproval { _ in XCTFail("No choice was made") }
        hud.show(.recording)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.width, 360)
        XCTAssertTrue(panel.ignoresMouseEvents)
        hud.hide()
        XCTAssertEqual(panel.frame.width, 390)
    }
}
