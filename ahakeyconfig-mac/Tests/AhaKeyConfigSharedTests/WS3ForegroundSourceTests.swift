import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class WS3ForegroundSourceTests: XCTestCase {
    private let origin = WS3ProcessInstance(pid: 100, seconds: 10, microseconds: 20)!
    private let app = WS3ProcessInstance(pid: 200, seconds: 11, microseconds: 30)!
    private let context = WS3ForegroundContext(generation: 5, presentation: 7)
    private let terminal = WS3TerminalTaskIdentity(device: 123, processGroup: 300,
        leaderStartedSeconds: 12, leaderStartedMicroseconds: 40)!
    private func update(_ sequence: UInt64 = 1, focus: Bool = true) -> WS3ForegroundUpdate {
        .init(origin: origin, sequence: sequence, context: context,
            focus: focus ? .init(application: app, terminal: terminal) : nil)
    }
    func testNumericIPCRoundTripAndMalformedFields() throws {
        let original = update()
        let encoded = try JSONSerialization.data(withJSONObject: XCTUnwrap(original.parameters))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(WS3ForegroundUpdate(parameters: body), original)
        for (key, invalid) in [("sequence", true as Any), ("generation", -1), ("presentation", 1.25),
            ("originPID", 1), ("appMicros", 1_000_000), ("terminalGroup", -1),
            ("terminalLeaderSeconds", "12"), ("focused", 2)] {
            var corrupt = body; corrupt[key] = invalid
            XCTAssertNil(WS3ForegroundUpdate(parameters: corrupt), key)
        }
        let clear = update(2, focus: false)
        XCTAssertEqual(WS3ForegroundUpdate(parameters: try XCTUnwrap(clear.parameters)), clear)
        XCTAssertNil(WS3ForegroundUpdate(parameters: [:]))
        XCTAssertNil(WS3ForegroundUpdate(origin: origin, sequence: UInt64.max, context: context, focus: nil).parameters)
    }
    func testStaleSequenceAndConnectionContextCannotReplaceFocus() {
        var current: WS3ForegroundContext? = context
        var applications: [WS3TerminalTaskIdentity?] = []
        let receiver = WS3ForegroundReceiver(context: { current }, apply: { applications.append($0) },
            observeSystem: false, originIsValid: { _ in true }, focusIsValid: { _ in true })
        XCTAssertTrue(receiver.receive(update(2)))
        XCTAssertFalse(receiver.receive(update(2, focus: false)))
        XCTAssertFalse(receiver.receive(update(1, focus: false)))
        current = .init(generation: 6, presentation: 7)
        XCTAssertFalse(receiver.receive(update(3, focus: false)))
        receiver.revalidate()
        XCTAssertEqual(applications.count, 2)
        XCTAssertEqual(applications.first!, terminal)
        XCTAssertNil(applications.last!)
    }
    func testRevocationDoesNotAllowOldSequenceToRestoreFocus() {
        var validFocus = true
        var applied: WS3TerminalTaskIdentity?
        let receiver = WS3ForegroundReceiver(context: { self.context }, apply: { applied = $0 },
            observeSystem: false, originIsValid: { _ in true }, focusIsValid: { _ in validFocus })
        XCTAssertTrue(receiver.receive(update(3))); XCTAssertEqual(applied, terminal)
        validFocus = false; receiver.revalidate(); XCTAssertNil(applied)
        validFocus = true
        XCTAssertFalse(receiver.receive(update(3))); XCTAssertNil(applied)
        XCTAssertTrue(receiver.receive(update(4))); XCTAssertEqual(applied, terminal)
        validFocus = false
        XCTAssertTrue(receiver.receive(update(5))); XCTAssertNil(applied)
    }
    func testLiveOriginCannotBeReplacedButNewProcessBirthCanTakeOverAfterExit() {
        var live = Set([origin.pid])
        let receiver = WS3ForegroundReceiver(context: { self.context }, apply: { _ in }, observeSystem: false,
            originIsValid: { live.contains($0.pid) }, focusIsValid: { _ in true })
        XCTAssertTrue(receiver.receive(update()))
        let other = WS3ProcessInstance(pid: 101, seconds: 20, microseconds: 0)!
        live.insert(other.pid)
        let replacement = WS3ForegroundUpdate(origin: other, sequence: 1, context: context, focus: nil)
        XCTAssertFalse(receiver.receive(replacement))
        live.remove(origin.pid)
        XCTAssertTrue(receiver.receive(replacement))
        XCTAssertFalse(receiver.receive(update(100)))
    }
}
