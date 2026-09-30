import XCTest
@testable import AhaKeyConfigAgent

final class AgentStatusReplyTests: XCTestCase {
    private let physicalAuto = AgentDeviceStatus(
        battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
        workMode: 0, lightMode: 16, switchState: 0
    )

    func testFreshPhysicalAutoStatusWinsOverStaleManualCache() {
        let reply = AhaKeyAgent.statusReply(
            physicalAuto, cachedSwitch: 1, cachedLight: 6
        )
        XCTAssertEqual(reply["switchState"] as? Int, 0)
        XCTAssertEqual(reply["lightMode"] as? Int, 16)
    }

    func testFreshPhysicalManualStatusWinsOverStaleAutoCache() {
        let physicalManual = AgentDeviceStatus(
            battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
            workMode: 0, lightMode: 16, switchState: 1
        )
        let reply = AhaKeyAgent.statusReply(
            physicalManual, cachedSwitch: 0, cachedLight: 6
        )
        XCTAssertEqual(reply["switchState"] as? Int, 1)
        XCTAssertEqual(reply["lightMode"] as? Int, 16)
    }

    func testFallbackUsesPhysicalCacheOrUnknown() {
        let cached = AhaKeyAgent.statusReply(
            nil, cachedSwitch: 1, cachedLight: nil
        )
        XCTAssertEqual(cached["switchState"] as? Int, 1)

        let unknown = AhaKeyAgent.statusReply(
            nil, cachedSwitch: nil, cachedLight: nil
        )
        XCTAssertTrue(unknown["switchState"] is NSNull)
    }
}
