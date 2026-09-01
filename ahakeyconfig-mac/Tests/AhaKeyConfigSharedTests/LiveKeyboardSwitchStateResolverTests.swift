import XCTest
@testable import AhaKeyConfigShared

final class LiveKeyboardSwitchStateResolverTests: XCTestCase {
    func testConnectedAppWithoutFirstStatusFrameDoesNotReportAutomaticApproval() {
        XCTAssertNil(LiveKeyboardSwitchStateResolver.resolve(
            optimisticOverride: nil,
            appIsConnected: true,
            appState: nil,
            runtimeState: nil
        ))
    }

    func testAgentOwnedBluetoothUsesLiveAgentLeverSequenceInsteadOfStaleAppDefault() {
        let reportedStates = [0, 1, 2, 0].map { runtimeState in
            LiveKeyboardSwitchStateResolver.resolve(
                optimisticOverride: nil,
                appIsConnected: false,
                appState: 0,
                runtimeState: runtimeState
            )
        }

        XCTAssertEqual(reportedStates, [0, 1, 2, 0])
    }
}
