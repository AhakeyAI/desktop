import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class FirmwareCapabilityProfileTests: XCTestCase {
    func testHW1SaveRepairIdentityPreservesReadbackGatedProtocol() throws {
        let key = "x1-c582-hw1-p1-1.0.1-r001"
        let frame = Data([0xAA, 0xBB, 0x9F, 0]) + Data(key.utf8) + Data([0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: true)
        XCTAssertTrue(profile.isVerifiedProtocol)
        XCTAssertTrue(profile.mayQueryOrdinaryKeys)
        XCTAssertTrue(profile.mayQueryVoiceOnboarding)
        XCTAssertTrue(profile.mayQuerySideSwitchBindings)
        XCTAssertTrue(profile.mayQueryStandby)
        XCTAssertTrue(profile.mayQueryWS3Resources)
        XCTAssertTrue(profile.mayUseWS3Presentation)
        XCTAssertFalse(profile.canWriteWithoutReadback)
        XCTAssertFalse(profile.canUseWS3Presentation)
        XCTAssertFalse(profile.canWriteWS3Resources)
        XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: false).identity, .unknown(nil))
        let entry = try XCTUnwrap(VerifiedFirmwareCatalog.builtin?.value.entries.first { $0.key == key })
        XCTAssertEqual(entry.hardware, "x1-c582-hw1")
        XCTAssertEqual(entry.visibility, .engineering)
        XCTAssertEqual(entry.channel, .engineering)
        XCTAssertFalse(entry.recommended)
        XCTAssertFalse(entry.recoverySafe)
        XCTAssertNil(entry.artifact)
    }

    func testHW2IdentityIsNotAcceptedAsHW1Repair() {
        let key = "x1-c582-hw2-p1-1.0.1-r001"
        let frame = Data([0xAA, 0xBB, 0x9F, 0]) + Data(key.utf8) + Data([0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: true)
        XCTAssertEqual(profile.identity, .unknown(key))
        XCTAssertFalse(profile.isVerifiedProtocol)
    }

    @MainActor
    func testHW2RuntimeAllowsOnlyConfirmedKeyEditWithMatchingReadback() async throws {
        let key = "x1-c582-hw2-p1-1.0.1-r001"
        func frame(_ key: String) -> Data {
            Data([0xAA, 0xBB, 0x9F, 0]) + Data(key.utf8) + Data([0xCC, 0xDD])
        }
        let context = FirmwareDesktopContext(version: FirmwareDesktopVersion("0.2.3")!)
        let runtime = FirmwareRuntimeCatalog.Snapshot(catalog: .builtin, context: context)
        let profile = runtime.profile(frame(key), hasValidStatus: true)
        let query = Data([0xAA, 0xBB, 0x87, 1, 3, 0xCC, 0xDD])
        let readback = { (usage: UInt8) in
            OrdinaryKeyReadbackResult.parse(Data([0xAA, 0xBB, 0x87, 0, 1, 3, 0x73, 1, usage, 0, 0xCC, 0xDD]),
                requestedMode: 1, requestedKeyIndex: 3)
        }
        guard case .value(let baseline) = readback(0x2A), case .value(let target) = readback(0x29) else {
            return XCTFail("HW2 ordinary-key fixture did not parse")
        }
        let action = try XCTUnwrap(OrdinaryKeyConfiguration.actionRequest(target))
        XCTAssertTrue(ConfigurationCommandPolicy.permits(query, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(action, profile: profile))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(query, profile: runtime.profile(frame(key), hasValidStatus: false)))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(query,
            profile: runtime.profile(frame("x1-c582-hw2-p1-1.0.1-r002"), hasValidStatus: true)))
        XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: nil))
        XCTAssertFalse(profile.mayQueryWS3Resources)
        XCTAssertFalse(runtime.permitsPresentation(key: key))
        let catalog = try XCTUnwrap(runtime.catalog)
        let hw2 = try XCTUnwrap(catalog.value.entries.first { $0.key == key })
        XCTAssertEqual(hw2.hardware, "x1-c582-hw2")
        XCTAssertEqual(hw2.visibility, .engineering)
        XCTAssertNil(hw2.artifact)
        XCTAssertFalse(hw2.recoverySafe)
        XCTAssertEqual(FirmwareCatalogDecision.evaluate(identity: .key(key), catalog: catalog, context: context).state,
            .unsupportedHardware)

        var writes: [Data] = []
        let actual = try await ConfirmedOrdinaryKeySetting.run(baseline: baseline, target: target, checkSession: {},
            read: { writes.isEmpty ? baseline : target }, voiceState: { XCTFail("not Voice"); return 0 }, write: {
                XCTAssertTrue(ConfigurationCommandPolicy.permits($0, profile: profile, confirmedWrite: .ordinaryKey))
                writes.append($0)
            })
        XCTAssertEqual(actual, target)
        XCTAssertEqual(writes, [action, Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])])
    }

    func testAcceptedCatalogEnablesOnlyVerifiedWS2Capabilities() {
        let frame = Data([0xAA, 0xBB, 0x9F, 0x00]
            + Array(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + [0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.catalogResponse(frame)
        XCTAssertEqual(profile.identity, .knownWS2Catalog)
        XCTAssertTrue(profile.mayQueryOrdinaryKeys)
        XCTAssertFalse(profile.canWriteWithoutReadback)
        XCTAssertFalse(profile.canUseWS3Presentation)
        XCTAssertFalse(profile.canWriteWS3Resources)
    }

    func testUnknownCatalogDoesNotOpenWrites() {
        let frame = Data([0xAA, 0xBB, 0x9F, 0x00]
            + Array("x1-c582-hw1-p1-1.0.1-r002".utf8) + [0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.catalogResponse(frame)
        XCTAssertEqual(profile.identity, .unknown("x1-c582-hw1-p1-1.0.1-r002"))
        XCTAssertFalse(profile.canWriteWithoutReadback)
        XCTAssertFalse(profile.canWriteWS3Resources)
    }

    func testOnlyExactSuccessAckWithIndependentStatusOpensLegacyWrites() {
        let ack = Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD])
        let profile = FirmwareCapabilityProfile.probeResponse(ack, hasValidStatusReadback: true)
        XCTAssertEqual(profile.identity, .legacy)
        XCTAssertTrue(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: profile))
        let noStatus = FirmwareCapabilityProfile.probeResponse(ack, hasValidStatusReadback: false)
        XCTAssertEqual(noStatus.identity, .unknown(nil))
        XCTAssertFalse(ConfigurationCommandPolicy.permits(Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD]), profile: noStatus))
    }

    func testAllCatalogErrorStatusesCannotEnableLegacyWritesOrAutoApproval() {
        let save = Data([0xAA, 0xBB, 0x04, 0xCC, 0xDD])
        for status: UInt8 in 1...255 {
            let error = Data([0xAA, 0xBB, 0x9F, status, 0xCC, 0xDD])
            let profile = FirmwareCapabilityProfile.probeResponse(error, hasValidStatusReadback: true)
            XCTAssertEqual(profile.identity, .unknown(nil), "status=\(status)")
            XCTAssertFalse(ConfigurationCommandPolicy.permits(save, profile: profile), "status=\(status)")
            XCTAssertFalse(ApprovalBindingPolicy.mayAutoApprove(physicalState: 0, fresh: true, profile: profile, binding: nil))
        }
    }

    func testMalformedOrWrongCommandAckAndMissingStatusRemainUnknown() {
        for frame in [Data(), Data([0xAA, 0xBB, 0x9F, 0, 0xCC]),
                      Data([0xAA, 0xBB, 0x95, 0, 0xCC, 0xDD]),
                      Data([0xAA, 0xBB, 0x9F, 0, 0xCC, 0xDD, 0])] {
            XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(frame, hasValidStatusReadback: true).identity, .unknown(nil))
        }
        let known = Data([0xAA, 0xBB, 0x9F, 0]) + Data(FirmwareCapabilityProfile.ws2CatalogKey.utf8) + Data([0xCC, 0xDD])
        XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(known, hasValidStatusReadback: false).identity, .unknown(nil))
        XCTAssertEqual(FirmwareCapabilityProfile.probeResponse(known, hasValidStatusReadback: true).identity, .knownWS2Catalog)
    }

    func testLegacyIsOnlyAnExplicitFallback() {
        let error = Data([0xAA, 0xBB, 0x9F, 0x01, 0xCC, 0xDD])
        XCTAssertEqual(FirmwareCapabilityProfile.catalogResponse(error).identity, .unknown(nil))
        XCTAssertEqual(FirmwareCapabilityProfile.legacyAfterStatusReadback().identity, .legacy)
    }
}
