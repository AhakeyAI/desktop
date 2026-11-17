import CoreGraphics
import XCTest
@testable import AhaKeyConfig

final class FunctionKeyRelayEventTests: XCTestCase {
    func testFnRelayUsesModifierChangedEdgesAndPreservesOtherModifiers() throws {
        let tag: Int64 = 0x4148414B
        var delivered: [(CGEvent, CGEventTapLocation)] = []
        VoiceRelayService.postFunctionKeyEdge(isKeyDown: true, currentFlags: .maskShift, userData: tag) {
            delivered.append(($0, $1))
        }
        VoiceRelayService.postFunctionKeyEdge(isKeyDown: false, currentFlags: [.maskShift, .maskSecondaryFn], userData: tag) {
            delivered.append(($0, $1))
        }
        XCTAssertEqual(delivered.map(\.1), [.cghidEventTap, .cghidEventTap],
            "A downstream input method must see one Fn transition per edge, not separate HID and session copies")
        guard delivered.count == 2 else { return }
        let down = delivered[0].0, up = delivered[1].0
        for event in [down, up] {
            XCTAssertEqual(event.type, .flagsChanged)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 63)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), tag)
            XCTAssertTrue(event.flags.contains(.maskShift))
        }
        XCTAssertTrue(down.flags.contains(.maskSecondaryFn))
        XCTAssertFalse(up.flags.contains(.maskSecondaryFn))
    }
}
