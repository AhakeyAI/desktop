import XCTest
@testable import AhaKeyConfigShared

final class LiveKeyboardSwitchStateResolverTests: XCTestCase {
    func testConnectedAppWithoutFirstStatusFrameDoesNotReportAutomaticApproval() {
        XCTAssertNil(LiveKeyboardSwitchStateResolver.resolve(
            optimisticOverride: nil,
            appIsConnected: true,
            appState: nil,
            agentState: nil
        ))
    }

    func testAgentOwnedBluetoothUsesLiveAgentLeverSequenceInsteadOfStaleAppDefault() {
        let reportedStates = [0, 1, 2, 0].map { agentState in
            LiveKeyboardSwitchStateResolver.resolve(
                optimisticOverride: nil,
                appIsConnected: false,
                appState: 0,
                agentState: agentState
            )
        }

        XCTAssertEqual(reportedStates, [0, 1, 2, 0])
    }
}
