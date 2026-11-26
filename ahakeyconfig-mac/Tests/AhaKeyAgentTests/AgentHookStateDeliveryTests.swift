import XCTest
@testable import AhaKeyConfigAgent

final class AgentHookStateDeliveryTests: XCTestCase {
    func testLifecycleReceiptRequiresMatchingEventAndSession() {
        for (argument, event, sessionField, client) in [
            ("SessionStart", "SessionStart", "session_id", "claude"),
            ("sessionStart", "sessionStart", "conversation_id", "cursor"),
            ("KimiSessionStart", "SessionStart", "session_id", "kimi"),
        ] {
            let payload = Data(#"{"hook_event_name":"\#(event)","\#(sessionField)":"fixture"}"#.utf8)
            let unrelated = Data(#"{"hook_event_name":"Unknown","\#(sessionField)":"fixture"}"#.utf8)
            XCTAssertEqual(HookClient.verifiedLifecycleClient(event: argument, stdin: payload)?.rawValue, client)
            XCTAssertNil(HookClient.verifiedLifecycleClient(event: argument, stdin: unrelated))
            XCTAssertNil(HookClient.verifiedLifecycleClient(event: argument, stdin: Data("{}".utf8)))
        }
    }

    func testWorkBuddyLifecycleSendsOnlyTaskStateAndIdentity() {
        for (event, state) in [("WorkBuddyUserPromptSubmit", 7), ("WorkBuddyStop", 5), ("WorkBuddySessionEnd", 8)] {
            let hookName = String(event.dropFirst("WorkBuddy".count))
            let stdin = Data(#"{"hook_event_name":"\#(hookName)","session_id":"workbuddy-1","prompt":"private","tool_input":{"command":"private"}}"#.utf8)
            let request = HookClient.stateRequest(event: event, stdin: stdin)
            XCTAssertEqual(request?["cmd"] as? String, "state")
            XCTAssertEqual(request?["value"] as? Int, state)
            XCTAssertEqual(request?["task"] as? [String: String],
                           ["client": "workBuddy", "session": "workbuddy-1", "event": event])
            XCTAssertEqual(request?.count, 3)
        }
        XCTAssertNil(HookClient.stateRequest(event: "WorkBuddyPermissionRequest", stdin: Data()))
        XCTAssertNil(HookClient.stateRequest(event: "WorkBuddyStop", stdin: Data(#"{"hook_event_name":"SessionEnd","session_id":"workbuddy-1"}"#.utf8)))
    }

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
