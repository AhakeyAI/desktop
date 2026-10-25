import XCTest
@testable import AhaKeyConfigShared

final class ApprovalBindingPolicyTests: XCTestCase {
    private var profile: FirmwareCapabilityProfile {
        .catalogResponse(Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD]))
    }
    private func binding(type: UInt8, state: UInt8 = 0, action: Data = Data()) -> SideSwitchReadback {
        .init(physicalState: state, positions: [.init(bindType: type, action: action), .init(bindType: 1, action: Data())])
    }
    func testOnlyFreshPhysicalAutoWithMatchingFactoryBindingAllows() {
        XCTAssertTrue(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: binding(type: 0)))
        for type: UInt8 in [1, 2, 3] {
            XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: binding(type: type)))
        }
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: binding(type: 0, state: 1)))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: false, profile: profile, binding: binding(type: 0)))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 1, fresh: true, profile: profile, binding: binding(type: 0)))
    }
    func testMissingUnknownOrMalformedBindingCannotApprove() {
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: nil, binding: binding(type: 0)))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: nil))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: nil, fresh: true, profile: profile, binding: binding(type: 0)))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: binding(type: 0, action: Data([1]))))
    }
    func testVerifiedLegacyRequiresFreshPhysicalAuto() {
        XCTAssertTrue(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: .legacyAfterStatusReadback(), binding: nil))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: false, profile: .legacyAfterStatusReadback(), binding: nil))
    }
    func testWireProofCannotBeReplacedByRawOrCachedGPIO() {
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(["switchState": 0]), 1)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(nil), 1)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(["switchState": 0, "approvalPolicyVersion": 1, "approvalAutoVerified": false]), 1)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(["switchState": 1, "approvalPolicyVersion": 1, "approvalAutoVerified": true]), 1)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(["switchState": 0, "physicalSwitchState": 0, "approvalPolicyVersion": 1, "approvalAutoVerified": true]), 0)
    }
    func testMalformedJSONProofCannotAuthorize() throws {
        let valid = #"{"approvalPolicyVersion":1,"physicalSwitchState":0,"switchState":0,"approvalAutoVerified":true}"#
        let mutations: [(String, [String])] = [
            ("approvalPolicyVersion", ["true", "false", "1.5", #""1""#, "null"]),
            ("physicalSwitchState", ["false", "true", "0.5", "-1", "2", #""0""#, "null"]),
            ("switchState", ["false", "true", "0.5", "-1", "2", #""0""#, "null"]),
            ("approvalAutoVerified", ["1", "0", #""true""#, "null"]),
        ]
        for (field, values) in mutations {
            for value in values {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [String: Any])
                let replacement = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
                object[field] = replacement
                XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(object), 1, "\(field)=\(value)")
            }
        }
        let validObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(valid.utf8)) as? [String: Any])
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(validObject), 0)
        var floating = validObject
        floating["switchState"] = NSNumber(value: 0.0)
        XCTAssertEqual(ApprovalBindingPolicy.effectiveSwitchState(floating), 1)
    }

}
