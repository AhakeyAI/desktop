import XCTest
@testable import AhaKeyConfig

final class AgentBLEConnectionStateTests: XCTestCase {
    func testUsesExplicitAgentConnectionFields() {
        let state = AgentBLEConnectionState(socketReply: [
            "isConnected": true,
            "deviceName": "AhaKey 517C",
            "deviceUUID": "5AB949F0-B932-537A-BCFB-1B973C74B5A1",
            "commandReady": true,
            "notifyReady": true,
        ])

        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.deviceName, "AhaKey 517C")
        XCTAssertEqual(state.deviceUUID, "5AB949F0-B932-537A-BCFB-1B973C74B5A1")
        XCTAssertTrue(state.commandReady)
        XCTAssertTrue(state.notifyReady)
    }

    func testFallsBackToLegacySwitchStateReply() {
        let state = AgentBLEConnectionState(socketReply: ["switchState": 0])

        XCTAssertTrue(state.isConnected)
        XCTAssertNil(state.deviceName)
        XCTAssertFalse(state.commandReady)
        XCTAssertFalse(state.notifyReady)
    }

    func testTreatsNullLegacySwitchStateAsDisconnected() {
        let state = AgentBLEConnectionState(socketReply: ["switchState": NSNull()])

        XCTAssertFalse(state.isConnected)
    }
}
