import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyOLEDCompatibilityProfileTests: XCTestCase {

    /// Gitee Rhino 实抓 26B：protocol v3、双套、factory+session flags。
    private let rhino26Payload = Data([
        3, 4, 2, 4,
        0x3F, 0x00,
        0xF4, 0x00,
        0x20, 0x01,
        0x30, 0x01,
        0x02, 0x00, 0x00, 0x00,
        0xF6, 0x5D, 0x2C, 0x82,
        2, 0,
        0x28, 0x01,
        0x30, 0x01,
    ])

    private let compact14Payload = Data([
        0x03, 0x04, 0x02, 0x04,
        0x3F, 0x00,
        0xC8, 0x00,
        0x14, 0x01,
        0x14, 0x01,
        0x1C, 0x01,
    ])

    private func caps(
        protocolVersion: Int = 3,
        modeCount: Int = 4,
        setCount: Int = 2,
        stateCount: Int = 4,
        flags: UInt16 = 0,
        userSlotLimit: Int = 64
    ) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: protocolVersion, modeCount: modeCount, setCount: setCount,
            stateCount: stateCount, flags: flags, maxPacketSize: 200,
            userSlotLimit: userSlotLimit, factorySlotBase: 0,
            factoryBundleVersion: 0, factoryManifestCRC: 0,
            factoryStatus: 0, factoryError: 0, reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    // MARK: - 无 0x99 / 短帧 / 14/22/26B

    func testNoResponseFirmware1WithTaskPicturesIsLegacyStandard() {
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(
                .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true)
            ),
            .legacyStandard
        )
    }

    func testNoResponseWithoutTaskPicturesOrUnknownVersionIsUnsupported() {
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(
                .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false)
            ),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(
                .noResponse(firmwareMainVersion: nil, supportsLegacyTaskPictures: true)
            ),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(
                .noResponse(firmwareMainVersion: 2, supportsLegacyTaskPictures: true)
            ),
            .unsupported
        )
    }

    func testNegotiatingAndMalformedAreUnsupported() {
        XCTAssertEqual(AhaKeyOLEDCompatibilityProfile.resolve(.negotiating), .unsupported)
        XCTAssertEqual(AhaKeyOLEDCompatibilityProfile.resolve(.malformedResponse), .unsupported)
    }

    func testShortAndAmbiguousFramesDoNotParseAndStayUnsupported() {
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data()))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(repeating: 0, count: 13)))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(15))))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(21))))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(23))))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(25))))
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(14))))
        XCTAssertEqual(AhaKeyOLEDCompatibilityProfile.resolve(.malformedResponse), .unsupported)
    }

    func testParsed14_22_26ByteRhinoFramesAreDualSet() {
        let parsed14 = AhaKeyFirmwareCapabilities.parse(compact14Payload)!
        let parsed22 = AhaKeyFirmwareCapabilities.parse(Data(rhino26Payload.prefix(22)))!
        let parsed26 = AhaKeyFirmwareCapabilities.parse(rhino26Payload)!
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(parsed14)),
            .rhinoDualSet(sessionUploadAdvertised: true)
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(parsed22)),
            .rhinoDualSet(sessionUploadAdvertised: true)
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(parsed26)),
            .rhinoDualSet(sessionUploadAdvertised: true)
        )
    }

    func testCurrentSessionRequiresExplicitSessionAdvertisementWithoutDualSet() {
        let sessionOnly = caps(
            setCount: 1,
            flags: AhaKeyFirmwareCapabilities.sessionUploadFlag
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(sessionOnly)),
            .currentSessionCapable
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(caps(setCount: 1, flags: 0))),
            .unsupported
        )
    }

    func testAbnormalZeroCountsAreUnsupported() {
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolveParsed(caps(modeCount: 0)),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolveParsed(caps(setCount: 0)),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolveParsed(caps(userSlotLimit: 0)),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolveParsed(caps(protocolVersion: 4, flags: 0x3F)),
            .unsupported
        )
    }

    func testLegacyProtocolModeRejectsIndependentCapabilityMixing() {
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(caps(protocolVersion: 3))),
            .rhinoDualSet(sessionUploadAdvertised: false)
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityContext.standard.profile,
            .legacyStandard
        )
        XCTAssertNil(AhaKeyOLEDCompatibilityContext.standard.capabilities)
    }

    func testCurrentWithoutAdvertisedCapabilitiesIsUnsupported() {
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityContext.make(.noResponse(
                firmwareMainVersion: 1, supportsLegacyTaskPictures: false
            )).profile,
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(
                .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false)
            ),
            .unsupported
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityProfile.resolve(.parsed(caps(setCount: 1, flags: 0))),
            .unsupported
        )
    }

    // MARK: - opcode 策略

    func testStandardForbidsRhinoAndSessionOpcodes() {
        let policy = AhaKeyOLEDCompatibilityProfile.legacyStandard.pictureOpcodes
        XCTAssertTrue(policy.allowsPrepareWrite)
        XCTAssertTrue(policy.allowsBindLegacyTaskPicture)
        XCTAssertTrue(policy.allowsBindDefaultPicture)
        XCTAssertFalse(policy.allowsSessionPrepare)
        XCTAssertFalse(policy.allowsSessionAbort)
        XCTAssertFalse(policy.allowsBindTaskPicture)
        XCTAssertFalse(policy.allowsSetActiveSet)
        XCTAssertFalse(policy.allowsFinishTaskPicture)
    }

    func testRhinoDualSetUsesProvenBindAndOptionalSession() {
        let withSession = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: true).pictureOpcodes
        XCTAssertTrue(withSession.allowsPrepareWrite)
        XCTAssertTrue(withSession.allowsSessionPrepare)
        XCTAssertTrue(withSession.allowsBindTaskPicture)
        XCTAssertTrue(withSession.allowsSetActiveSet)
        XCTAssertFalse(withSession.allowsFinishTaskPicture)
        XCTAssertFalse(withSession.allowsBindDefaultPicture)
        XCTAssertFalse(withSession.allowsBindLegacyTaskPicture)

        let withoutSession = AhaKeyOLEDCompatibilityProfile.rhinoDualSet(sessionUploadAdvertised: false).pictureOpcodes
        XCTAssertTrue(withoutSession.allowsPrepareWrite)
        XCTAssertFalse(withoutSession.allowsSessionPrepare)
        XCTAssertFalse(withoutSession.allowsSessionAbort)
        XCTAssertTrue(withoutSession.allowsBindTaskPicture)
    }

    func testCurrentSessionCapableRequiresSessionOpcodes() {
        let policy = AhaKeyOLEDCompatibilityProfile.currentSessionCapable.pictureOpcodes
        XCTAssertFalse(policy.allowsPrepareWrite)
        XCTAssertTrue(policy.allowsSessionPrepare)
        XCTAssertTrue(policy.allowsSessionAbort)
        XCTAssertTrue(policy.allowsBindTaskPicture)
        XCTAssertTrue(policy.allowsSetActiveSet)
        XCTAssertFalse(policy.allowsFinishTaskPicture)
        XCTAssertFalse(policy.allowsBindDefaultPicture)
    }

    func testUnsupportedAllowsNoPictureOpcodesAndNoPlan() {
        XCTAssertEqual(AhaKeyOLEDCompatibilityProfile.unsupported.pictureOpcodes, .none)
        XCTAssertFalse(AhaKeyOLEDCompatibilityProfile.unsupported.allowsConfigurationPlan)
        XCTAssertTrue(AhaKeyOLEDCompatibilityProfile.legacyStandard.allowsConfigurationPlan)
    }

    func testLegacyTaskPictureProbeClassifiesRealPayloadAndEmptyAck() {
        let real = Data([
            0xAA, 0xBB, 0x94, 0x00,
            2, 3, 0x34, 0x12, 5, 0, 83, 0, 0x24, 0x01,
            0xCC, 0xDD,
        ])
        XCTAssertEqual(AhaKeyLegacyTaskPictureProbe.classify(frame: real), .supportsTaskPictures)
        XCTAssertEqual(
            AhaKeyLegacyTaskPictureProbe.classify(frame: Data([0xAA, 0xBB, 0x94, 0x00, 0xCC, 0xDD])),
            .genericUnknownCommandAck
        )
        XCTAssertEqual(
            AhaKeyLegacyTaskPictureProbe.classify(frame: Data([0xAA, 0xBB, 0x94, 0x00, 1, 2, 0xCC, 0xDD])),
            .malformed
        )
        XCTAssertEqual(
            AhaKeyOLEDLegacyProbe.negotiationState(
                firmwareMainVersion: 1, taskPicture: .supportsTaskPictures
            ),
            .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true)
        )
        XCTAssertEqual(
            AhaKeyOLEDLegacyProbe.negotiationState(
                firmwareMainVersion: 1, taskPicture: .genericUnknownCommandAck
            ),
            .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false)
        )
        XCTAssertEqual(
            AhaKeyOLEDCompatibilityContext.make(
                AhaKeyOLEDLegacyProbe.negotiationState(firmwareMainVersion: 2, taskPicture: .supportsTaskPictures)
            ).profile,
            .unsupported
        )
    }
}
