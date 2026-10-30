import AppKit
import XCTest
@testable import AhaKeyConfig

@MainActor
final class LightBarLayerViewTests: XCTestCase {
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    func testAnimationUpdatesColorsWithoutReplacingOrRelayingOutSegments() throws {
        let view = LightBarLayerView(frame: CGRect(x: 0, y: 0, width: 400, height: 30))
        view.configure(framesPerSecond: nil) { [red, blue] time in Array(repeating: time < 1 ? red : blue, count: 10) }
        view.layout()
        let original = try XCTUnwrap(view.layer?.sublayers)
        let geometry = original.map(\.frame)
        XCTAssertEqual(original.count, 10)
        XCTAssertEqual(original[0].backgroundColor?.components, red.components)
        for frame in 1...100 { view.render(at: Double(frame)) }
        let updated = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(updated.map(\.frame), geometry)
        for index in 0..<10 {
            XCTAssertTrue(updated[index] === original[index])
            XCTAssertEqual(updated[index].backgroundColor?.components, blue.components)
        }
    }

    func testShortColorListHidesStaleSegmentsAndCanShowThemAgain() throws {
        let view = LightBarLayerView()
        view.configure(framesPerSecond: nil) { [red] time in Array(repeating: red, count: time == 1 ? 3 : 10) }
        view.render(at: 1)
        let bars = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(bars.filter { !$0.isHidden }.count, 3)
        view.render(at: 2)
        XCTAssertTrue(bars.allSatisfy { !$0.isHidden })
    }

    func testDismantledViewCannotResumeItsColorSource() throws {
        let view = LightBarLayerView()
        var calls = 0
        let colors: (TimeInterval) -> [CGColor] = { [red] _ in calls += 1; return [red] }
        view.configure(framesPerSecond: nil, colors: colors)
        view.render(at: 1)
        let before = calls
        view.dismantle()
        view.render(at: 2)
        view.configure(framesPerSecond: 10, colors: colors)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(calls, before)
    }

    func testResizeKeepsExistingSegmentsInsideStripBounds() throws {
        let view = LightBarLayerView(frame: CGRect(x: 0, y: 0, width: 400, height: 30))
        view.configure(framesPerSecond: nil) { [red] _ in Array(repeating: red, count: 10) }
        view.layout()
        let original = try XCTUnwrap(view.layer?.sublayers)
        view.setFrameSize(CGSize(width: 200, height: 15))
        view.layout()
        let resized = try XCTUnwrap(view.layer?.sublayers)
        for index in 0..<10 {
            XCTAssertTrue(resized[index] === original[index])
            XCTAssertGreaterThanOrEqual(resized[index].frame.minX, 0)
            XCTAssertGreaterThanOrEqual(resized[index].frame.minY, 0)
            XCTAssertLessThanOrEqual(resized[index].frame.maxX, view.bounds.width)
            XCTAssertLessThanOrEqual(resized[index].frame.maxY, view.bounds.height)
            XCTAssertEqual(resized[index].backgroundColor?.components, red.components)
        }
    }
}
