import Foundation
import XCTest
@testable import AhaKeyConfig

final class TerminalSelectionQueryTests: XCTestCase {
    private func field(_ descriptor: NSAppleEventDescriptor?, _ key: String) -> NSAppleEventDescriptor? {
        descriptor?.forKeyword(TerminalSelectionQuery.code(key))
    }
    func testTerminalRequestReadsOnlyTTYOfSelectedTabInFrontWindow() throws {
        let request = try TerminalSelectionQuery.makeGetTTYEvent(processID: 123, provider: .terminal)
        XCTAssertEqual(request.eventClass, TerminalSelectionQuery.code("core"))
        XCTAssertEqual(request.eventID, TerminalSelectionQuery.code("getd"))
        let tty = request.paramDescriptor(forKeyword: TerminalSelectionQuery.code("----"))
        XCTAssertEqual(field(tty, "seld")?.typeCodeValue, TerminalSelectionQuery.code("ttty"))
        let tab = field(tty, "from")
        XCTAssertEqual(field(tab, "seld")?.typeCodeValue, TerminalSelectionQuery.code("tcnt"))
        let window = field(tab, "from")
        XCTAssertEqual(field(window, "want")?.typeCodeValue, TerminalSelectionQuery.code("cwin"))
        XCTAssertEqual(field(window, "seld")?.int32Value, 1)
        XCTAssertEqual(field(window, "from")?.descriptorType, TerminalSelectionQuery.code("null"))
        let target = try XCTUnwrap(request.attributeDescriptor(forKeyword: TerminalSelectionQuery.code("addr")))
        XCTAssertEqual(target.descriptorType, TerminalSelectionQuery.code("kpid"))
        XCTAssertThrowsError(try TerminalSelectionQuery.makeGetTTYEvent(processID: 0, provider: .terminal))
    }
    func testITermRequestUsesCurrentWindowAndCurrentSessionWithoutReadingContents() throws {
        let request = try TerminalSelectionQuery.makeGetTTYEvent(processID: 123, provider: .iTerm)
        let tty = request.paramDescriptor(forKeyword: TerminalSelectionQuery.code("----"))
        XCTAssertEqual(field(tty, "seld")?.typeCodeValue, TerminalSelectionQuery.code("Stty"))
        let session = field(tty, "from")
        XCTAssertEqual(field(session, "seld")?.typeCodeValue, TerminalSelectionQuery.code("Wcsn"))
        XCTAssertEqual(field(field(session, "from"), "seld")?.typeCodeValue, TerminalSelectionQuery.code("Crwn"))
    }
    func testReplyRejectsErrorsAndAllNonTTYContent() {
        let reply = NSAppleEventDescriptor.appleEvent(withEventClass: TerminalSelectionQuery.code("aevt"),
            eventID: TerminalSelectionQuery.code("ansr"), targetDescriptor: nil, returnID: -1, transactionID: 0)
        for invalid in ["/etc/passwd", "/dev/ttys000\n", "/dev/ttys/../secret", "terminal output"] {
            reply.setParam(NSAppleEventDescriptor(string: invalid), forKeyword: TerminalSelectionQuery.code("----"))
            XCTAssertNil(TerminalSelectionQuery.parseTTY(reply))
        }
        reply.setParam(NSAppleEventDescriptor(string: "/dev/ttys999"), forKeyword: TerminalSelectionQuery.code("----"))
        XCTAssertEqual(TerminalSelectionQuery.parseTTY(reply), "/dev/ttys999")
        reply.setParam(NSAppleEventDescriptor(int32: -1743), forKeyword: TerminalSelectionQuery.code("errn"))
        XCTAssertNil(TerminalSelectionQuery.parseTTY(reply))
    }
}
