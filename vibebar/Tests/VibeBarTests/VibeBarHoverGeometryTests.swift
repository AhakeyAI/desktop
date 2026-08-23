import CoreGraphics
import XCTest
@testable import VibeBar

final class VibeBarHoverGeometryTests: XCTestCase {
    func testTopHotZoneUsesEachScreensGlobalCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let secondary = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)

        XCTAssertEqual(
            VibeBarHoverGeometry.topHotZone(in: primary),
            CGRect(x: 536, y: 924, width: 440, height: 58)
        )
        XCTAssertEqual(
            VibeBarHoverGeometry.screenIndex(
                withTopHotZoneContaining: CGPoint(x: -960, y: 1_070),
                screenFrames: [primary, secondary]
            ),
            1
        )
        XCTAssertEqual(
            VibeBarHoverGeometry.screenIndex(
                withExpandedInteractionZoneContaining: CGPoint(x: -960, y: 900),
                screenFrames: [primary, secondary]
            ),
            1
        )
    }

    func testScreenContainingPointerSupportsNegativeOrigins() {
        let primary = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let secondary = CGRect(x: -1_920, y: -200, width: 1_920, height: 1_080)
        let frames = [primary, secondary]

        XCTAssertEqual(
            VibeBarHoverGeometry.screenIndex(
                containing: CGPoint(x: -100, y: 400),
                screenFrames: frames
            ),
            1
        )
        XCTAssertNil(
            VibeBarHoverGeometry.screenIndex(
                withTopHotZoneContaining: CGPoint(x: 200, y: 200),
                screenFrames: frames
            )
        )
        XCTAssertNil(
            VibeBarHoverGeometry.screenIndex(
                withExpandedInteractionZoneContaining: CGPoint(x: 200, y: 200),
                screenFrames: frames
            )
        )
    }
}
