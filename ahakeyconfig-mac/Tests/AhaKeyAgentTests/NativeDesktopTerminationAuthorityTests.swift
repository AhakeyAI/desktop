import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

final class NativeDesktopTerminationAuthorityTests: XCTestCase {
    private let auto: [String: Any] = ["approvalPolicyVersion": 1, "physicalSwitchState": 0,
        "switchState": 0, "approvalAutoVerified": true]
    func testTerminationInvalidatesEvenFreshAutomaticProof() {
        XCTAssertEqual(AhaKeyAgent.desktopAuthority(terminating: false, enabled: true, reply: auto), .verifiedAutomatic)
        XCTAssertEqual(AhaKeyAgent.desktopAuthority(terminating: true, enabled: true, reply: auto), .unmanaged)
    }
    func testLateManualOrAutoCallbackCannotRegrantDuringTermination() {
        for reply in [auto, ["physicalSwitchState": 1]] {
            XCTAssertEqual(AhaKeyAgent.desktopAuthority(terminating: true, enabled: true, reply: reply), .unmanaged)
            XCTAssertEqual(AhaKeyAgent.desktopAuthority(terminating: false, enabled: false, reply: reply), .unmanaged)
        }
    }
    func testLateApprovalCannotRegrantOrClaimAutomaticWhileExiting() {
        let status = AgentDeviceStatus(battery: 80, signal: 0, firmwareMain: 1, firmwareSub: 0,
            workMode: 0, lightMode: 1, switchState: 0)
        let profile = FirmwareCapabilityProfile.legacyAfterStatusReadback()
        let active = AhaKeyAgent.approvalReply(status, profile: profile, binding: nil, fresh: true)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(active), 0)
        let exiting = AhaKeyAgent.approvalReply(status, profile: profile, binding: nil, fresh: true, terminating: true)
        XCTAssertEqual(exiting["switchState"] as? Int, 1)
        XCTAssertEqual(exiting["approvalAutoVerified"] as? Bool, false)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(exiting), 1)
    }

}
