import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfigAgent

final class AgentStatusReplyTests: XCTestCase {
    func testVerifiedAutoReplySurvivesJSONAndRawStatusIsNotApprovalProof() throws {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let factory = SideSwitchReadback(physicalState: 0, positions: [.init(bindType: 0, action: Data()), .init(bindType: 1, action: Data())])
        let reply = AhaKeyAgent.approvalReply(physicalAuto, profile: profile, binding: factory, fresh: true)
        let wire = try JSONSerialization.data(withJSONObject: reply)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(decoded), 0)
        let raw = AhaKeyAgent.statusReply(physicalAuto, cachedSwitch: nil, cachedLight: nil)
        XCTAssertEqual(raw["switchState"] as? Int, 0)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(raw), 1)
    }
    func testApprovalEndpointCannotGrantFromRawGPIOOrLegacyClientParsing() {
        let profile = FirmwareCapabilityProfile.catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
        let custom = SideSwitchReadback(physicalState: 0, positions: [.init(bindType: 3, action: Data([0x73, 0x28])), .init(bindType: 1, action: Data())])
        let reply = AhaKeyAgent.approvalReply(physicalAuto, profile: profile, binding: custom, fresh: true)
        XCTAssertEqual(reply["physicalSwitchState"] as? Int, 0)
        XCTAssertEqual(reply["switchState"] as? Int, 1)
        XCTAssertEqual(reply["approvalAutoVerified"] as? Bool, false)
        let unavailable = AhaKeyAgent.approvalReply(nil, profile: nil, binding: nil, fresh: false)
        XCTAssertEqual(unavailable["switchState"] as? Int, 1)
        XCTAssertTrue(unavailable["physicalSwitchState"] is NSNull)
    }
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

    func testTimeoutRejectsLateAutoUntilNewConnectionAndStaleDeadlineDoesNotInvalidate() {
        var queries = AgentStatusQueries()
        let completed = queries.append { _ in }
        queries.resolveAll(with: physicalAuto)
        XCTAssertFalse(queries.timeOut(completed))
        XCTAssertTrue(queries.acceptsResponses)
        let timedOut = queries.append { XCTAssertNil($0) }
        XCTAssertTrue(queries.timeOut(timedOut))
        XCTAssertFalse(queries.acceptsResponses)
        var late: AgentDeviceStatus?
        _ = queries.append { late = $0 }
        queries.resolveAll(with: physicalAuto)
        XCTAssertNil(late)
        queries = AgentStatusQueries() // production replaces the tracker only on didConnect
        _ = queries.append { late = $0 }
        queries.resolveAll(with: physicalAuto)
        XCTAssertEqual(late, physicalAuto)
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
