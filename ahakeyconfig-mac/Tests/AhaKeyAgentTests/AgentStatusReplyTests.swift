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

    func testPermissionRepliesAuthorizeOnlyFreshPhysicalAuto() {
        let auto = AhaKeyAgent.permissionReply(physicalAuto)
        XCTAssertEqual(auto["approvalPolicyVersion"] as? Int, 1)
        XCTAssertEqual(auto["physicalSwitchState"] as? Int, 0)
        XCTAssertEqual(auto["approvalAutoVerified"] as? Bool, true)
        XCTAssertNotNil(ClaudeHookHandler.preToolUseOutput(reply: auto))

        for switchState in [1, 2, 255] {
            let status = AgentDeviceStatus(
                battery: 62, signal: 0, firmwareMain: 1, firmwareSub: 0,
                workMode: 0, lightMode: 16, switchState: switchState
            )
            let reply = AhaKeyAgent.permissionReply(status)
            XCTAssertEqual(reply["approvalAutoVerified"] as? Bool, false)
            XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply))
        }
    }

    func testQueryTimeoutDoesNotReuseCachedAutoForEitherClaudeHook() {
        // The UI can still display the last observed auto value, while the
        // permission request must complete as unknown without a fresh response.
        let display = AhaKeyAgent.statusReply(nil, cachedSwitch: 0, cachedLight: 16)
        XCTAssertEqual(display["switchState"] as? Int, 0)
        var queries = AgentStatusQueries()
        var calls = 0
        let id = queries.append { status in
            calls += 1
            XCTAssertNil(status)
            let reply = AhaKeyAgent.permissionReply(status)
            XCTAssertTrue(reply["switchState"] is NSNull)
            XCTAssertEqual(reply["approvalAutoVerified"] as? Bool, false)
            XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply))
            let fallback = ClaudeHookHandler.permissionRequestOutput(reply: reply)
            let hook = fallback["hookSpecificOutput"] as? [String: Any]
            let decision = hook?["decision"] as? [String: Any]
            XCTAssertEqual(decision?["behavior"] as? String, "ask")
        }
        queries.timeOut(id)
        queries.resolveAll(with: physicalAuto)
        XCTAssertEqual(calls, 1)
    }

    func testExpiredDeadlineDoesNotResolveANewerQuery() {
        var queries = AgentStatusQueries()
        let old = queries.append { status in XCTAssertEqual(status, self.physicalAuto) }
        queries.resolveAll(with: physicalAuto)
        var received: AgentDeviceStatus?
        _ = queries.append { received = $0 }
        queries.timeOut(old)
        XCTAssertFalse(queries.isEmpty)
        queries.resolveAll(with: physicalAuto)
        XCTAssertEqual(received, physicalAuto)
    }

    func testDisconnectResolvesAllPendingQueriesAsUnknown() {
        var queries = AgentStatusQueries()
        var calls = 0
        for _ in 0..<2 {
            _ = queries.append { status in
                calls += 1
                XCTAssertNil(status)
            }
        }
        queries.resolveAll(with: nil)
        XCTAssertTrue(queries.isEmpty)
        XCTAssertEqual(calls, 2)
    }
}
