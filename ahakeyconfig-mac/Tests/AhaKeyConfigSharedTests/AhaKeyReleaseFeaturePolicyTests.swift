import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleaseFeaturePolicyTests: XCTestCase {

    private let policy = AhaKeyReleaseFeaturePolicy.current

    /// 固件 1.3 `tp_write_caps14` 精确 fixture（factory-off 14B）。
    private let caps14Payload = Data([
        0x03, 0x04, 0x02, 0x04,
        0x33, 0x00,
        0xC8, 0x00,
        0x20, 0x01,
        0x00, 0x00, 0x00, 0x00,
    ])

    /// HIL 真机 compact factory 14B。
    private let compactFactory14Payload = Data([
        0x03, 0x04, 0x02, 0x04,
        0x3F, 0x00,
        0xC8, 0x00,
        0x14, 0x01,
        0x14, 0x01,
        0x1C, 0x01,
    ])

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

    private var truncatedPayloads: [Data] {
        [
            Data(),
            Data(repeating: 0, count: 13),
            Data(rhino26Payload.prefix(14)),
            Data(rhino26Payload.prefix(15)),
            Data(rhino26Payload.prefix(21)),
            Data(rhino26Payload.prefix(23)),
            Data(rhino26Payload.prefix(25)),
        ]
    }

    private func capabilities(protocolVersion: Int) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: protocolVersion, modeCount: 4, setCount: 2, stateCount: 4,
            flags: 0x3F, maxPacketSize: 244, userSlotLimit: 288, factorySlotBase: 0,
            factoryBundleVersion: 0, factoryManifestCRC: 0,
            factoryStatus: 0, factoryError: 0, reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private func parsed(_ payload: Data) throws -> AhaKeyFirmwareCapabilities {
        try XCTUnwrap(AhaKeyFirmwareCapabilities.parse(payload))
    }

    /// Typed case：协商状态直接携带预期协议模式与写入资格，不用字符串标签查表。
    private struct ProjectionFixture: Equatable {
        let state: AhaKeyReleaseNegotiationState
        let expectedMode: AhaKeyProtocolMode
        let allowsBasicConfigurationWrite: Bool
    }

    private func projectionFixtures() throws -> [ProjectionFixture] {
        [
            ProjectionFixture(
                state: .negotiating,
                expectedMode: .negotiating,
                allowsBasicConfigurationWrite: false
            ),
            ProjectionFixture(
                state: .malformedResponse,
                expectedMode: .restrictedUnknown,
                allowsBasicConfigurationWrite: false
            ),
            ProjectionFixture(
                state: .noResponse(firmwareMainVersion: nil, supportsLegacyTaskPictures: false),
                expectedMode: .restrictedUnknown,
                allowsBasicConfigurationWrite: false
            ),
            ProjectionFixture(
                state: .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: true),
                expectedMode: .legacy,
                allowsBasicConfigurationWrite: true
            ),
            ProjectionFixture(
                state: .noResponse(firmwareMainVersion: 1, supportsLegacyTaskPictures: false),
                expectedMode: .legacyBaseOnly,
                allowsBasicConfigurationWrite: true
            ),
            ProjectionFixture(
                state: .noResponse(firmwareMainVersion: 3, supportsLegacyTaskPictures: true),
                expectedMode: .restrictedUnknown,
                allowsBasicConfigurationWrite: false
            ),
            ProjectionFixture(
                state: .parsed(try parsed(caps14Payload)),
                expectedMode: .current,
                allowsBasicConfigurationWrite: true
            ),
            ProjectionFixture(
                state: .parsed(try parsed(compactFactory14Payload)),
                expectedMode: .current,
                allowsBasicConfigurationWrite: true
            ),
            ProjectionFixture(
                state: .parsed(try parsed(rhino26Payload)),
                expectedMode: .current,
                allowsBasicConfigurationWrite: true
            ),
            ProjectionFixture(
                state: .parsed(capabilities(protocolVersion: 2)),
                expectedMode: .restrictedUnknown,
                allowsBasicConfigurationWrite: false
            ),
        ]
    }

    // MARK: - Channel / Sendable

    func testCurrentChannelIsV0_2() {
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current.channel, .v0_2)
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current, .v0_2)
    }

    func testPolicyValuesAreSendableAndEquatable() throws {
        func requireSendableEquatable<T: Sendable & Equatable>(_ value: T) {
            _ = value
        }
        requireSendableEquatable(AhaKeyReleaseChannel.v0_2)
        requireSendableEquatable(AhaKeyWriteSurface.keysAndLight)
        requireSendableEquatable(AhaKeyDeferredOLEDReason.requiresFirmwareV0_3)
        requireSendableEquatable(AhaKeyReleaseNegotiationState.negotiating)
        requireSendableEquatable(AhaKeyReleaseNegotiationState.malformedResponse)
        requireSendableEquatable(
            AhaKeyReleaseNegotiationState.noResponse(
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: true
            )
        )
        requireSendableEquatable(AhaKeyProtocolMode.current)
        requireSendableEquatable(try parsed(caps14Payload))
        requireSendableEquatable(AhaKeyReleaseNegotiationState.parsed(try parsed(caps14Payload)))
        requireSendableEquatable(AhaKeyReleaseFeaturePolicy.current)
        requireSendableEquatable(policy.projection(.negotiating))
    }

    // MARK: - Full v0.2 matrix

    func testV0_2ProjectionFixturesCloseOLEDAndMatchWriteEligibility() throws {
        for fixture in try projectionFixtures() {
            XCTAssertEqual(
                AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(fixture.state),
                fixture.expectedMode,
                "\(fixture.state)"
            )

            let projection = policy.projection(fixture.state)
            assertOLEDAndResourcesClosed(projection, "\(fixture.state)")
            XCTAssertEqual(
                projection.allowsBasicConfigurationWrite,
                fixture.allowsBasicConfigurationWrite,
                "keys/light write \(fixture.state)"
            )
            XCTAssertEqual(
                projection.showsKeysAndLightEditor,
                fixture.allowsBasicConfigurationWrite,
                "keys/light UI \(fixture.state)"
            )
            XCTAssertEqual(
                projection.allows(.keysAndLight),
                fixture.allowsBasicConfigurationWrite,
                "keys/light surface \(fixture.state)"
            )
            XCTAssertEqual(
                projection.allowedWriteSurfaces,
                fixture.allowsBasicConfigurationWrite ? [.keysAndLight] : [],
                "write surface set \(fixture.state)"
            )
        }
    }

    func testV0_2ParsedCurrentStillDefersOLED() throws {
        let capabilities = try parsed(caps14Payload)
        XCTAssertEqual(AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities), .current)
        XCTAssertTrue(AhaKeyProtocolMode.current.allowsTaskPictureConfiguration)

        let projection = policy.projection(.parsed(capabilities))
        assertOLEDAndResourcesClosed(projection, "parsed-caps14")
        XCTAssertTrue(projection.allowsBasicConfigurationWrite)
        XCTAssertEqual(projection.deferredOLEDReason, .requiresFirmwareV0_3)
    }

    // MARK: - Resolver: malformed vs no-response

    func testResolvedModeUsesNegotiationForParsedCapabilities() throws {
        let caps14 = try parsed(caps14Payload)
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.parsed(caps14)),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: caps14),
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.parsed(caps14))
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .parsed(capabilities(protocolVersion: 2))
            ),
            .restrictedUnknown
        )
    }

    func testTruncatedAndMalformedCapabilityFramesFailClosed() {
        for payload in truncatedPayloads {
            XCTAssertNil(AhaKeyFirmwareCapabilities.parse(payload))
        }

        var factoryBitWithoutCompactStructure = caps14Payload
        factoryBitWithoutCompactStructure[4] = 0x37
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(factoryBitWithoutCompactStructure))

        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.malformedResponse),
            .restrictedUnknown
        )
        let projection = policy.projection(.malformedResponse)
        XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty)
        XCTAssertFalse(projection.allowsBasicConfigurationWrite)
        assertOLEDAndResourcesClosed(projection, "malformed")
    }

    func testParsedCapabilityFixturesAreAvailableToTheMatrix() throws {
        XCTAssertEqual(try parsed(caps14Payload).factorySlotBase, 0)
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: try parsed(caps14Payload)),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: try parsed(compactFactory14Payload)),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: try parsed(rhino26Payload)),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities(protocolVersion: 2)),
            .restrictedUnknown
        )
    }

    // MARK: - Helpers

    private func assertOLEDAndResourcesClosed(
        _ projection: AhaKeyReleaseFeatureProjection,
        _ context: String
    ) {
        XCTAssertEqual(projection.channel, .v0_2, context)
        XCTAssertFalse(projection.showsDefaultPictureEditor, context)
        XCTAssertFalse(projection.showsTaskPictureEditor, context)
        XCTAssertFalse(projection.showsOLEDInspector, context)
        XCTAssertFalse(projection.allowsResourcePackage, context)
        XCTAssertFalse(projection.allows(.defaultPictures), context)
        XCTAssertFalse(projection.allows(.taskPictures), context)
        XCTAssertEqual(projection.deferredOLEDReason, .requiresFirmwareV0_3, context)
    }
}
