import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class WS2SettingsReadbackTests: XCTestCase {
    func testStandbyQueryRequiresValueRatherThanWriteAck() {
        XCTAssertEqual(WS2SettingsReadback.standbyMinutes(Data([
            0xAA, 0xBB, 0x95, 0, 120, 0, 0xCC, 0xDD,
        ])), 120)
        XCTAssertNil(WS2SettingsReadback.standbyMinutes(Data([0xAA, 0xBB, 0x95, 0, 0xCC, 0xDD])))
        XCTAssertNil(WS2SettingsReadback.standbyMinutes(Data([
            0xAA, 0xBB, 0x95, 0, 15, 0, 0xCC, 0xDD,
        ])))
    }

    func testVoiceOnboardingQueryRequiresStateRatherThanWriteAck() {
        XCTAssertEqual(WS2SettingsReadback.voiceOnboardingState(Data([
            0xAA, 0xBB, 0x96, 0, 2, 0xCC, 0xDD,
        ])), 2)
        XCTAssertNil(WS2SettingsReadback.voiceOnboardingState(Data([0xAA, 0xBB, 0x96, 0, 0xCC, 0xDD])))
        XCTAssertNil(WS2SettingsReadback.voiceOnboardingState(Data([
            0xAA, 0xBB, 0x96, 0, 5, 0xCC, 0xDD,
        ])))
    }

    func testSideSwitchQueryPreservesBinaryActionsAndPositionOrder() {
        let frame = Data([
            0xAA, 0xBB, 0x97, 0, 1, 2,
            3, 4, 0x73, 2, 0xCC, 0xDD,
            0, 0, 0xCC, 0xDD,
        ])
        XCTAssertEqual(WS2SettingsReadback.sideSwitch(frame), SideSwitchReadback(
            physicalState: 1,
            positions: [
                .init(bindType: 3, action: Data([0x73, 2, 0xCC, 0xDD])),
                .init(bindType: 0, action: Data()),
            ]
        ))
        XCTAssertNil(WS2SettingsReadback.sideSwitch(Data([0xAA, 0xBB, 0x97, 0, 0xCC, 0xDD])))
        XCTAssertNil(WS2SettingsReadback.sideSwitch(Data([
            0xAA, 0xBB, 0x97, 0, 1, 2, 0, 1, 0x73, 0, 0, 0xCC, 0xDD,
        ])))
    }
}
