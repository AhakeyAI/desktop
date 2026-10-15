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

    func testQueryTimeoutDoesNotReuseCachedAutoForEitherClaudeHook() throws {
        let display = AhaKeyAgent.statusReply(nil, cachedSwitch: 0, cachedLight: 16)
        XCTAssertEqual(display["switchState"] as? Int, 0)
        var queries = AgentStatusQueries()
        var result: [String: Any]?
        let id = queries.append { result = AhaKeyAgent.permissionReply($0) }
        queries.timeOut(id)

        let reply = try XCTUnwrap(result)
        XCTAssertTrue(reply["switchState"] is NSNull)
        XCTAssertNil(ClaudeHookHandler.preToolUseOutput(reply: reply))
        let output = ClaudeHookHandler.permissionRequestOutput(reply: reply)
        let hook = output["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "ask")
    }
}
