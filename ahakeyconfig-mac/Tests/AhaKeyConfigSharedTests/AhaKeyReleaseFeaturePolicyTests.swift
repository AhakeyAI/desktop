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

    private func capabilities(protocolVersion: Int) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: protocolVersion, modeCount: 4, setCount: 2, stateCount: 4,
            flags: 0x3F, maxPacketSize: 244, userSlotLimit: 288, factorySlotBase: 0,
            factoryBundleVersion: 0, factoryManifestCRC: 0,
            factoryStatus: 0, factoryError: 0, reclaimSlotBase: 0, reclaimSlotLimit: 0
        )
    }

    private var capabilityFixtures: [(String, AhaKeyFirmwareCapabilities?)] {
        [
            ("nil", nil),
            ("caps14", AhaKeyFirmwareCapabilities.parse(caps14Payload)),
            ("compactFactory14", AhaKeyFirmwareCapabilities.parse(compactFactory14Payload)),
            ("rhino26", AhaKeyFirmwareCapabilities.parse(rhino26Payload)),
            ("protocolV2", capabilities(protocolVersion: 2)),
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

    /// 与生产实现分开的期望表：只有一致的安全终态才开放键位/灯效。
    private func expectedAllowsBasic(mode: AhaKeyProtocolMode, capsLabel: String) -> Bool {
        switch (mode, capsLabel) {
        case (.legacy, "nil"), (.legacyBaseOnly, "nil"):
            return true
        case (.current, "caps14"), (.current, "compactFactory14"), (.current, "rhino26"):
            return true
        default:
            return false
        }
    }

    // MARK: - Channel

    func testCurrentChannelIsV0_2() {
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current.channel, .v0_2)
        XCTAssertEqual(AhaKeyReleaseFeaturePolicy.current, .v0_2)
    }

    // MARK: - Full v0.2 matrix: OLED closed and keys/light eligibility

    func testV0_2MatrixClosesOLEDAndGatesBasicWritesForEveryModeAndCapability() {
        for mode in allModes {
            for (label, capabilities) in capabilityFixtures {
                let projection = policy.projection(protocolMode: mode, capabilities: capabilities)
                let context = "v0.2 mode=\(mode) caps=\(label)"
                assertOLEDAndResourcesClosed(projection, context)

                let expectBasic = expectedAllowsBasic(mode: mode, capsLabel: label)
                XCTAssertEqual(
                    projection.allowsBasicConfigurationWrite,
                    expectBasic,
                    "keys/light write \(context)"
                )
                XCTAssertEqual(projection.showsKeysAndLightEditor, expectBasic, "keys/light UI \(context)")
                XCTAssertEqual(projection.allows(.keysAndLight), expectBasic, "keys/light surface \(context)")
                XCTAssertEqual(
                    projection.allowedWriteSurfaces,
                    expectBasic ? [.keysAndLight] : [],
                    "write surface set \(context)"
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
        XCTAssertEqual(projection.deferredOLEDReason, .requiresFirmwareV0_3)
    }

    func testV0_2DoesNotGuessNilCapabilitiesAsCurrent() {
        let projection = policy.projection(protocolMode: .current, capabilities: nil)
        XCTAssertFalse(projection.allowsBasicConfigurationWrite)
        XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty)
        assertOLEDAndResourcesClosed(projection, "current+nil")
    }

    func testV0_2RejectsContradictoryModeAndCapabilityPairs() {
        let caps14 = AhaKeyFirmwareCapabilities.parse(caps14Payload)
        XCTAssertNotNil(caps14)
        let protocolV2 = capabilities(protocolVersion: 2)

        let closed: [(AhaKeyProtocolMode, AhaKeyFirmwareCapabilities?, String)] = [
            (.current, nil, "current+nil"),
            (.current, protocolV2, "current+protocolV2"),
            (.legacy, caps14, "legacy+caps14"),
            (.legacyBaseOnly, caps14, "legacyBaseOnly+caps14"),
            (.negotiating, caps14, "negotiating+caps14"),
            (.restrictedUnknown, caps14, "restrictedUnknown+caps14"),
        ]
        for (mode, capabilities, label) in closed {
            let projection = policy.projection(protocolMode: mode, capabilities: capabilities)
            XCTAssertFalse(projection.allowsBasicConfigurationWrite, label)
            XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty, label)
            assertOLEDAndResourcesClosed(projection, label)
        }
    }

    func testV0_2UnknownStatesOpenNoWrites() {
        for mode in [AhaKeyProtocolMode.negotiating, .restrictedUnknown] {
            for (label, capabilities) in capabilityFixtures {
                let projection = policy.projection(protocolMode: mode, capabilities: capabilities)
                XCTAssertTrue(
                    projection.allowedWriteSurfaces.isEmpty,
                    "\(mode) caps=\(label) must open no write surfaces"
                )
                XCTAssertFalse(projection.allowsBasicConfigurationWrite)
                XCTAssertFalse(projection.showsKeysAndLightEditor)
                assertOLEDAndResourcesClosed(projection, "\(mode)/\(label)")
            }
        }
    }

    // MARK: - Resolver: malformed vs no-response

    func testResolvedModeUsesNegotiationForParsedCapabilities() {
        let caps14 = AhaKeyFirmwareCapabilities.parse(caps14Payload)!
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.parsed(caps14)),
            .current
        )
        XCTAssertEqual(
            AhaKeyProtocolNegotiation.mode(forCapabilities: caps14),
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.parsed(caps14))
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.parsed(capabilities(protocolVersion: 2))),
            .restrictedUnknown
        )
    }

    func testNoResponseFallsBackByFirmwareVersion() {
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.noResponse),
            .restrictedUnknown
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .noResponse,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: true
            ),
            .legacy
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .noResponse,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: false
            ),
            .legacyBaseOnly
        )
        XCTAssertEqual(
            AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .noResponse,
                firmwareMainVersion: 3,
                supportsLegacyTaskPictures: true
            ),
            .restrictedUnknown
        )
    }

    func testMalformedResponseNeverFallsBackToLegacyOnFirmware1x() {
        for supportsLegacy in [true, false] {
            let mode = AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .malformedResponse,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: supportsLegacy
            )
            XCTAssertEqual(mode, .restrictedUnknown, "supportsLegacy=\(supportsLegacy)")
            let projection = policy.projection(protocolMode: mode, capabilities: nil)
            XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty)
            XCTAssertFalse(projection.allowsBasicConfigurationWrite)
            assertOLEDAndResourcesClosed(projection, "malformed+fw1")
        }
    }

    func testTruncatedAndMalformedCapabilityFramesFailClosed() {
        for (label, payload) in truncatedPayloads {
            XCTAssertNil(AhaKeyFirmwareCapabilities.parse(payload), "\(label) must fail parse")
            let mode = AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(
                .malformedResponse,
                firmwareMainVersion: 1,
                supportsLegacyTaskPictures: true
            )
            XCTAssertEqual(mode, .restrictedUnknown, "\(label) must not resolve legacy/current")
            let projection = policy.projection(protocolMode: mode, capabilities: nil)
            XCTAssertTrue(projection.allowedWriteSurfaces.isEmpty, "\(label) opens no writes")
            assertOLEDAndResourcesClosed(projection, label)
        }

        var factoryBitWithoutCompactStructure = caps14Payload
        factoryBitWithoutCompactStructure[4] = 0x37
        XCTAssertNil(AhaKeyFirmwareCapabilities.parse(factoryBitWithoutCompactStructure))
        let malformedMode = AhaKeyReleaseFeaturePolicy.resolvedProtocolMode(.malformedResponse)
        XCTAssertEqual(malformedMode, .restrictedUnknown)
        let malformedProjection = policy.projection(protocolMode: malformedMode, capabilities: nil)
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
