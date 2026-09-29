import AppKit
import XCTest
@testable import VibeBar

final class VibeBarControllerTests: XCTestCase {
    func testRenderedScreenBecomesThePresentationScreenAfterWindowRecreation() async throws {
        try await MainActor.run {
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let controller = VibeBarController()
            // A newly reported window may be on a different screen than the stored presentation.
            // No expansion request should be required to accept its screen first.
            controller.compactFrameChanged(
                CGRect(x: screen.frame.midX - 120, y: screen.frame.maxY - 26, width: 50, height: 20),
                screen: screen, leading: true)
            XCTAssertEqual(controller.presentationScreen?.frame, screen.frame)
            controller.stop()
        }
    }
}
