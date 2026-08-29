import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyReleaseFeaturePolicyTests: XCTestCase {

    private let policy = AhaKeyReleaseFeaturePolicy.current

    private var allModes: [AhaKeyProtocolMode] {
        [.negotiating, .legacy, .legacyBaseOnly, .current, .restrictedUnknown]
    }

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

    private var capabilityFixtures: [(String, AhaKeyFirmwareCapabilities?)] {
        [
            ("nil", nil),
            ("caps14", AhaKeyFirmwareCapabilities.parse(caps14Payload)),
            ("compactFactory14", AhaKeyFirmwareCapabilities.parse(compactFactory14Payload)),
            ("rhino26", AhaKeyFirmwareCapabilities.parse(rhino26Payload)),
        ]
    }

    private var truncatedPayloads: [(String, Data)] {
        [
            ("empty", Data()),
            ("13B", Data(repeating: 0, count: 13)),
            ("rhino26-prefix14", Data(rhino26Payload.prefix(14))),
            ("rhino26-prefix15", Data(rhino26Payload.prefix(15))),
            ("rhino26-prefix21", Data(rhino26Payload.prefix(21))),
            ("rhino26-prefix23", Data(rhino26Payload.prefix(23))),
            ("rhino26-prefix25", Data(rhino26Payload.prefix(25))),
        ]
    }

    // MARK: - Channel

    func testCurrentChannelIsV0_2() {
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current.channel, .v0_2)
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current, .v0_2)
    }

    // MARK: - v0.2 matrix: OLED/resource never open

    func testV0_2NeverOpensOLEDOrResourcesForAnyModeOrCapability() {
        for mode in allModes {
            for (label, capabilities) in capabilityFixtures {
                let projection = policy.projection(protocolMode: mode, capabilities: capabilities)
                assertOLEDAndResourcesClosed(
                    projection,
                    "v0.2 mode=\(mode) caps=\(label)"
                )
            }
        }
    }

    func testV0_2CurrentPlusCaps14StillDefersOLED() {
        let capabilities = AhaKeyFirmwareCapabilities.parse(caps14Payload)
        XCTAssertNotNil(capabilities)
        XCTAssertEqual(AhaKeyProtocolNegotiation.mode(forCapabilities: capabilities!), .current)
        XCTAssertTrue(AhaKeyProtocolMode.current.allowsTaskPictureConfiguration)

        let projection = policy.projection(protocolMode: .current, capabilities: capabilities)
        assertOLEDAndResourcesClosed(projection, "current+caps14")
        XCTAssertTrue(projection.allows(.keysAndLight))
        XCTAssertTrue(projection.allowsBasicConfigurationWrite)
        XCTAssertEqual(projection.deferredOLEDMessage, "需 0.3 固件")
    }

    func testV0_2KeysAndLightSeparatedFromPictureEligibility() {
        let cases: [(AhaKeyProtocolMode, Bool)] = [
            (.negotiating, false),
            (.legacy, true),
            (.legacyBaseOnly, true),
            (.current, true),
            (.restrictedUnknown, false),
        ]
        for (mode, expectBasic) in cases {
            let projection = policy.projection(protocolMode: mode, capabilities: nil)
            XCTAssertEqual(
                projection.allowsBasicConfigurationWrite,
                expectBasic,
                "keys/light write for \(mode)"
            )
            XCTAssertEqual(projection.showsKeysAndLightEditor, expectBasic, "keys/light UI for \(mode)")
            XCTAssertEqual(projection.allows(.keysAndLight), expectBasic, "keys/light surface for \(mode)")
            XCTAssertFalse(projection.allows(.defaultPictures), "default pictures must stay closed for \(mode)")
            XCTAssertFalse(projection.allows(.taskPictures), "task pictures must stay closed for \(mode)")
            XCTAssertEqual(
                projection.allowedWriteSurfaces,
                expectBasic ? [.keysAndLight] : [],
                "write surface set for \(mode)"
            )
        }
    }

    func testV0_2UnknownStatesOpenNoWrites() {
        for mode in [AhaKeyProtocolMode.negotiating, .restrictedUnknown] {
            let projection = policy.projection(protocolMode: mode, capabilities: nil)
            XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty, "\(mode) must open no write surfaces")
            XCTAssertFalse(projection.allowsBasicConfigurationWrite)
            XCTAssertFalse(projection.showsKeysAndLightEditor)
            assertOLEDAndResourcesClosed(projection, "\(mode)")
        }
    }

    // MARK: - Resolver: nil / truncated never become current

    func testResolvedModeUsesNegotiationForParsedCapabilities() {
        let caps14 = AhaKeyFirmwareCapabilities.parse(caps14Payload)!
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(parsedCapabilities: caps14),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: caps14),
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(parsedCapabilities: caps14)
        )

        let unknownVersion = AhaKeyFirmwareCapabilities(
            protocolVersion: 2, modeCount: 4, setCount: 2, stateCount: 4,
            flags: 0x3F, maxPacketSize: 244, userSlotLimit: 288, factorySlotBase: 0,
            factoryBundleVersion: 0, factoryManifestCRC: 0,
            factoryStatus: 0, factoryError: 0, reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(parsedCapabilities: unknownVersion),
            .restrictedUnknown
        )
    }

    func testNilCapabilitiesNeverResolveCurrent() {
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(parsedCapabilities: nil),
            .restrictedUnknown
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                parsedCapabilities: nil,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: true
            ),
            .legacy
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                parsedCapabilities: nil,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: false
            ),
            .legacyBaseOnly
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                parsedCapabilities: nil,
                firmwareMainVersion: 3,
                supportsLegacyTaskPictures: true
            ),
            .restrictedUnknown
        )
    }

    func testTruncatedAndMalformedCapabilityFramesFailClosed() {
        for (label, payload) in truncatedPayloads {
            XCTAssertNil(AhaKeyFirmwareCapabilities.parse(payload), "\(label) must fail parse")
            let mode = AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                parsedCapabilities: AhaKeyFirmwareCapabilities.parse(payload),
                firmwareMainVersion: 3
            )
            XCTAssertEqual(mode, .restrictedUnknown, "\(label) must not resolve current")
            let projection = policy.projection(protocolMode: mode, capabilities: nil)
            XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty, "\(label) opens no writes")
            assertOLEDAndResourcesClosed(projection, label)
        }

        var factoryBitWithoutCompactStructure = caps14Payload
        factoryBitWithoutCompactStructure[4] = 0x37
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(factoryBitWithoutCompactStructure))
        let malformedMode = AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
            parsedCapabilities: AhaKeyFirmwareCapabilities.parse(factoryBitWithoutCompactStructure)
        )
        XCTAssertEqual(malformedMode, .restrictedUnknown)
        let malformedProjection = policy.projection(protocolMode: malformedMode)
        XCTAssertTrue(malformedProjection.allowedWriteSurfaces.isEmpty)
        assertOLEDAndResourcesClosed(malformedProjection, "factory-flag-invalid-compact")
    }

    func testParsedCapabilityFixturesAreAvailableToTheMatrix() {
        XCTAssertNotNil(AhaKeyFirmwareCapabilities.parse(caps14Payload))
        XCTAssertNotNil(AhaKeyFirmwareCapabilities.parse(compactFactory14Payload))
        XCTAssertNotNil(AhaKeyFirmwareCapabilities.parse(rhino26Payload))
        XCTAssertEqual(AhaKeyFirmwareCapabilities.parse(caps14Payload)?.factorySlotBase, 0)
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: AhaKeyFirmwareCapabilities.parse(caps14Payload)!),
            .current
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
        XCTAssertEqual(projection.deferredOLEDMessage, "需 0.3 固件", context)
    }
}
