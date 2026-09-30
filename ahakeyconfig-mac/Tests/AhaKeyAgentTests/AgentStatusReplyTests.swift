import XCTest
@testable import AhaKeyConfigAgent

final class AgentStatusReplyTests: XCTestCase {
    private let physicalAuto = AgentDeviceStatus(
        battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
        workMode: 0, lightMode: 16, switchState: 0
    )

    func testSoftwareManualOverrideWinsOverFreshPhysicalAutoStatus() {
        let reply = AhaKeyAgent.statusReply(
            physicalAuto, overrideSwitch: 1, cachedSwitch: 0, cachedLight: 6
        )
        XCTAssertEqual(reply["switchState"] as? Int, 1)
        XCTAssertEqual(reply["lightMode"] as? Int, 16)
    }

    func testFreshPhysicalStatusWinsOverStaleCacheWithoutOverride() {
        let reply = AhaKeyAgent.statusReply(
            physicalAuto, overrideSwitch: nil, cachedSwitch: 1, cachedLight: 6
        )
        XCTAssertEqual(reply["switchState"] as? Int, 0)
        XCTAssertEqual(reply["lightMode"] as? Int, 16)
    }

    func testDisconnectedFallbackRetainsOverrideAndUnknownState() {
        let overridden = AhaKeyAgent.statusReply(
            nil, overrideSwitch: 1, cachedSwitch: nil, cachedLight: nil
        )
        XCTAssertEqual(overridden["switchState"] as? Int, 1)

        let unknown = AhaKeyAgent.statusReply(
            nil, overrideSwitch: nil, cachedSwitch: nil, cachedLight: nil
        )
        XCTAssertTrue(unknown["switchState"] is NSNull)
    }
}
