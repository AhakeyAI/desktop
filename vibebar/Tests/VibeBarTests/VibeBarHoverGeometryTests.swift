import CoreGraphics
import XCTest
@testable import VibeBar

final class VibeBarHoverGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
    private func frame(in screen: CGRect) -> CGRect? {
        VibeBarHoverGeometry.compactFrame(
            leading: CGRect(x: screen.midX - 120, y: screen.maxY - 26, width: 50, height: 20),
            trailing: CGRect(x: screen.midX + 50, y: screen.maxY - 26, width: 70, height: 20),
            screen: screen, height: 32)
    }
    func testWindowDragMarginOutsideCollapsedIslandDoesNotTriggerExpansion() {
        XCTAssertFalse(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: screen.midX + 219, y: screen.maxY - 57), compactFrame: frame(in: screen), pressedMouseButtons: 0))
    }
    func testMeasuredWidthAndScreenTopDefineCompactFrame() {
        XCTAssertEqual(frame(in: screen), CGRect(x: 622.5, y: 950, width: 267, height: 32))
        XCTAssertTrue(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: screen.midX, y: screen.maxY - 16), compactFrame: frame(in: screen), pressedMouseButtons: 0))
    }
    func testCornersAndAllExteriorSidesDoNotTrigger() throws {
        let f = try XCTUnwrap(frame(in: screen))
        for p in [CGPoint(x: f.minX - 1, y: f.midY), CGPoint(x: f.maxX + 1, y: f.midY),
                  CGPoint(x: f.midX, y: f.minY - 1), CGPoint(x: f.midX, y: f.maxY + 1),
                  CGPoint(x: f.minX + 1, y: f.minY + 1), CGPoint(x: f.maxX - 1, y: f.minY + 1)] {
            XCTAssertFalse(VibeBarHoverGeometry.shouldExpand(at: p, compactFrame: f, pressedMouseButtons: 0))
        }
    }
    func testWindowDraggingEvenInsideIslandDoesNotExpand() {
        for buttons in [1, 2, 4] {
            XCTAssertFalse(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: screen.midX, y: screen.maxY - 16), compactFrame: frame(in: screen), pressedMouseButtons: buttons))
        }
    }
    func testUnmeasuredOrOtherScreenGeometryFailsClosed() {
        XCTAssertFalse(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: 756, y: 970), compactFrame: nil, pressedMouseButtons: 0))
        XCTAssertNil(VibeBarHoverGeometry.compactFrame(leading: CGRect(x: -500, y: 960, width: 50, height: 20), trailing: CGRect(x: 800, y: 960, width: 70, height: 20), screen: screen, height: 32))
    }
    func testNegativeOriginsAndOtherScreens() {
        let other = CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080)
        XCTAssertTrue(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: other.midX, y: other.maxY - 16), compactFrame: frame(in: other), pressedMouseButtons: 0))
        XCTAssertFalse(VibeBarHoverGeometry.shouldExpand(at: CGPoint(x: screen.midX, y: screen.maxY - 16), compactFrame: frame(in: other), pressedMouseButtons: 0))
        XCTAssertEqual(VibeBarHoverGeometry.screenIndex(containing: CGPoint(x: -100, y: 400), screenFrames: [screen, other]), 1)
    }
}
