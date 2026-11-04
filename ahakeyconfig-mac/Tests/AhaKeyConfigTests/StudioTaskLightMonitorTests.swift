import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioTaskLightMonitorTests: XCTestCase {
    private func overview(state: UInt8 = 1, reference: String = "a", mode: UInt8 = 1) -> WS3TaskOverview {
        WS3TaskOverview.decode(Data("""
        {"connected":true,"tasks":[{"slot":1,"client":"codex","reference":"\(String(repeating: reference, count: 64))","state":\(state)}],"unrepresentedEvents":0,"requestedMode":\(mode)}
        """.utf8))!
    }
    func testRealSlotMappingRemainsSteadyAcrossStateAndSessionChanges() throws {
        let model = StudioTaskLightMonitor()
        model.observe(overview(), revision: 1, at: 0)
        XCTAssertNil(model.animation?.snapshot.slots[0])
        XCTAssertEqual(model.animation?.snapshot.slots[1]?.state, .running)
        model.observe(overview(state: 2), revision: 1, at: 5)
        model.observe(overview(state: 2), revision: 1, at: 5.2)
        XCTAssertEqual(try XCTUnwrap(model.animation).intensity(slot: 1, at: 5.3), 1)
        model.observe(overview(state: 2, reference: "b"), revision: 1, at: 10)
        XCTAssertEqual(try XCTUnwrap(model.animation).intensity(slot: 1, at: 10.3), 1)
    }
    func testDisconnectedOrSingleModeCannotLeaveStaleMultitaskLights() {
        let model = StudioTaskLightMonitor()
        model.observe(overview(), revision: 1, at: 0)
        model.observe(nil, revision: 1, at: 1)
        XCTAssertNil(model.animation)
        model.observe(overview(), revision: 2, at: 2)
        model.observe(overview(mode: 0), revision: 2, at: 3)
        XCTAssertNil(model.animation)
    }
    func testLateExitFromOldForegroundTaskCannotClearNewForegroundSnapshot() {
        let model = StudioTaskLightMonitor()
        let old = model.beginObservation()
        let current = model.beginObservation()
        model.observe(overview(), revision: 1, at: 1)
        model.endObservation(old)
        XCTAssertNotNil(model.animation)
        model.endObservation(current)
        XCTAssertNil(model.animation)
    }

}
