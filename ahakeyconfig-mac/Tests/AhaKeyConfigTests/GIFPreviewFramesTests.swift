import XCTest
import ImageIO
@testable import AhaKeyConfig

@MainActor
final class GIFPreviewFramesTests: XCTestCase {
    private var artwork: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/DefaultOLED/claude_0.gif")
    }

    func testSmallRetinaPreviewDecodesAtDisplayedResolutionAndReusesWholeAnimation() throws {
        let frames = GIFPreviewFrames()
        frames.load(path: artwork.path, maximumPixelSize: 320)
        XCTAssertEqual(frames.count, 120)
        frames.updateViewport(size: CGSize(width: 140, height: 70), backingScale: 2)
        let firstCycle = try (0..<frames.count).map { try XCTUnwrap(frames.image(at: $0)) }
        XCTAssertLessThanOrEqual(firstCycle[0].width, 280)
        XCTAssertEqual(firstCycle[0].height, 140)
        XCTAssertLessThan(firstCycle.reduce(0) { $0 + $1.bytesPerRow * $1.height }, 32 * 1024 * 1024)
        for index in 0..<frames.count {
            XCTAssertTrue(try XCTUnwrap(frames.image(at: index)) === firstCycle[index], "Frame \(index) was decoded again")
        }
    }

    func testResizeAndBackingScaleRefreshWithoutLosingFramesOrChangingSource() throws {
        let original = try Data(contentsOf: artwork)
        let frames = GIFPreviewFrames()
        frames.load(path: artwork.path, maximumPixelSize: 320)
        frames.updateViewport(size: CGSize(width: 140, height: 70), backingScale: 1)
        XCTAssertEqual(try XCTUnwrap(frames.image(at: 0)).height, 70)
        XCTAssertTrue(frames.updateViewport(size: CGSize(width: 140, height: 70), backingScale: 2))
        XCTAssertEqual(try XCTUnwrap(frames.image(at: 0)).height, 140)
        XCTAssertTrue(frames.updateViewport(size: CGSize(width: 1000, height: 1000), backingScale: 2))
        XCTAssertEqual(try XCTUnwrap(frames.image(at: 0)).width, 320)
        XCTAssertEqual(frames.count, 120)
        XCTAssertEqual(try Data(contentsOf: artwork), original)
    }

    func testRepeatedLayoutAndZeroSizedLayoutKeepCachedImage() throws {
        let frames = GIFPreviewFrames()
        frames.load(path: artwork.path, maximumPixelSize: 320)
        frames.updateViewport(size: CGSize(width: 140, height: 70), backingScale: 2)
        let original = try XCTUnwrap(frames.image(at: 7))
        XCTAssertFalse(frames.updateViewport(size: CGSize(width: 140, height: 70), backingScale: 2))
        XCTAssertFalse(frames.updateViewport(size: .zero, backingScale: 2))
        XCTAssertFalse(frames.updateViewport(size: CGSize(width: CGFloat.infinity, height: 70), backingScale: 2))
        XCTAssertTrue(try XCTUnwrap(frames.image(at: 7)) === original)
        XCTAssertFalse(frames.load(path: artwork.path, maximumPixelSize: 320))
    }

    func testChangingOrInvalidatingSourceDoesNotReuseOldFrames() throws {
        let frames = GIFPreviewFrames()
        frames.load(path: artwork.path, maximumPixelSize: 320)
        let old = try XCTUnwrap(frames.image(at: 0))
        let codex = artwork.deletingLastPathComponent().appendingPathComponent("codex.gif")
        XCTAssertTrue(frames.load(path: codex.path, maximumPixelSize: 320))
        XCTAssertEqual(frames.count, 1)
        XCTAssertFalse(try XCTUnwrap(frames.image(at: 0)) === old)
        XCTAssertNil(frames.image(at: 1))
        XCTAssertNil(frames.image(at: -1))
        XCTAssertTrue(frames.load(path: "/nonexistent/ahakey-preview.gif", maximumPixelSize: 320))
        XCTAssertEqual(frames.count, 0)
        XCTAssertNil(frames.image(at: 0))
    }

    func testLayerUsesViewportAndRefreshesFrameAfterResize() throws {
        let view = AnimatedGIFLayerView(frame: CGRect(x: 0, y: 0, width: 140, height: 70))
        view.configure(path: artwork.path, fps: 10, maxPixelSize: 320, plays: false)
        let initial = try XCTUnwrap(view.layer?.contents) as! CGImage
        XCTAssertEqual(initial.height, 140)
        view.setFrameSize(CGSize(width: 140, height: 140))
        view.layout()
        let resized = try XCTUnwrap(view.layer?.contents) as! CGImage
        XCTAssertEqual(resized.width, 280)
        XCTAssertGreaterThan(resized.height, initial.height)
    }
}
