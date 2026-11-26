import XCTest
@testable import AhaKeyConfigAgent

final class AgentHookStateDeliveryTests: XCTestCase {
    func testWaitingDuringApprovalReadIsSentAfterChannelRelease() {
        var delivery = AgentHookStateDelivery(), wire: [UInt8] = []
        delivery.submit(3, presentationBlocked: false, approvalBusy: false) { wire.append($0) }
        delivery.submit(1, presentationBlocked: false, approvalBusy: true) { wire.append($0) }
        XCTAssertEqual(wire, [3])
        if let state = delivery.takePending() {
            delivery.submit(state, presentationBlocked: false, approvalBusy: false) { wire.append($0) }
        }
        XCTAssertEqual(wire, [3, 1], "A pending native approval must reach the LCD and light command")
        XCTAssertNil(delivery.takePending())
    }

    func testOnlyLatestStateSurvivesAndMultiOrDisconnectClearsSingleReplay() {
        var delivery = AgentHookStateDelivery(), wire: [UInt8] = []
        delivery.submit(1, presentationBlocked: false, approvalBusy: true) { wire.append($0) }
        delivery.submit(2, presentationBlocked: false, approvalBusy: true) { wire.append($0) }
        XCTAssertEqual(delivery.takePending(), 2)
        delivery.submit(1, presentationBlocked: false, approvalBusy: true) { wire.append($0) }
        delivery.submit(7, presentationBlocked: true, approvalBusy: true) { wire.append($0) }
        XCTAssertNil(delivery.takePending())
        delivery.submit(1, presentationBlocked: false, approvalBusy: true) { wire.append($0) }
        delivery.reset()
        XCTAssertNil(delivery.takePending())
        XCTAssertTrue(wire.isEmpty)
    }
}
