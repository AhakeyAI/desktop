import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyTaskPictureProtocolPlanTests: XCTestCase {
    func testLegacyBaseOnlyKeepsDefaultPictureEditorWhileHidingTaskPictures() {
        let sections = AhaKeyOLEDInspectorSections.make(mode: .legacyBaseOnly)

        XCTAssertTrue(sections.showsDefaultPictureEditor)
        XCTAssertFalse(sections.showsTaskPictureEditor)
    }

    func testDefaultPictureSyncUploadsChangesAndClearsRemovedAsset() {
        XCTAssertEqual(
            AhaKeyDefaultPictureSyncDecision.decide(
                hasLocalAsset: true, assetChanged: true, deviceFrameCount: 4
            ),
            .upload
        )
        XCTAssertEqual(
            AhaKeyDefaultPictureSyncDecision.decide(
                hasLocalAsset: false, assetChanged: true, deviceFrameCount: 4
            ),
            .clear
        )
        XCTAssertEqual(
            AhaKeyDefaultPictureSyncDecision.decide(
                hasLocalAsset: true, assetChanged: false, deviceFrameCount: 0
            ),
            .upload
        )
        XCTAssertEqual(
            AhaKeyDefaultPictureSyncDecision.decide(
                hasLocalAsset: true, assetChanged: false, deviceFrameCount: 4
            ),
            .skip
        )
    }

    func testDefaultPictureSyncRepairsNonEmptyDeviceBindingAtWrongSlot() {
        XCTAssertEqual(
            AhaKeyDefaultPictureSyncDecision.decide(
                hasLocalAsset: true,
                assetChanged: false,
                deviceStartIndex: 276,
                expectedStartIndex: 10,
                deviceFrameCount: 4
            ),
            .upload
        )
    }

    func testLegacyDefaultPictureLayoutUsesDeviceReportedCapacity() {
        XCTAssertEqual(
            AhaKeyLegacyDefaultPictureLayout.make(modeIndex: 0, totalCapacity: 74),
            AhaKeyLegacyDefaultPictureLayout(startIndex: 10, maxFrames: 16)
        )
        XCTAssertEqual(
            AhaKeyLegacyDefaultPictureLayout.make(modeIndex: 3, totalCapacity: 74),
            AhaKeyLegacyDefaultPictureLayout(startIndex: 58, maxFrames: 16)
        )
        XCTAssertNil(AhaKeyLegacyDefaultPictureLayout.make(modeIndex: 0, totalCapacity: 10))
    }

    func testBaseOnlyDirtyStateIgnoresUnsupportedTaskPictureFields() {
        XCTAssertFalse(AhaKeyOLEDDirtyPolicy.isDirty(
            mode: .legacyBaseOnly,
            defaultPictureChanged: false,
            completeOLEDChanged: true
        ))
        XCTAssertTrue(AhaKeyOLEDDirtyPolicy.isDirty(
            mode: .legacyBaseOnly,
            defaultPictureChanged: true,
            completeOLEDChanged: true
        ))
    }

    func testBaseOnlyUsesIndependentBaselineAndRetriesExternalAssets() {
        XCTAssertEqual(AhaKeySyncBaselineNamespace.suffix(for: .legacy), "legacy")
        XCTAssertEqual(AhaKeySyncBaselineNamespace.suffix(for: .legacyBaseOnly), "legacy-base")
        XCTAssertEqual(AhaKeySyncBaselineNamespace.suffix(for: .current), "current")
        XCTAssertNil(AhaKeyLegacyBaseInitialBaselinePolicy.assetPath(
            "/tmp/custom.gif", isBundledAsset: false
        ))
        XCTAssertEqual(
            AhaKeyLegacyBaseInitialBaselinePolicy.assetPath(
                "/Applications/AhaKey Studio.app/Contents/Resources/DefaultOLED/codex.gif",
                isBundledAsset: true
            ),
            "/Applications/AhaKey Studio.app/Contents/Resources/DefaultOLED/codex.gif"
        )
    }

    func testDefaultPictureWriteMustMatchDeviceReadback() {
        XCTAssertTrue(AhaKeyDefaultPictureWriteVerification.matches(
            expectedStartIndex: 26,
            expectedFrameCount: 6,
            expectedFrameIntervalMs: 83,
            deviceStartIndex: 26,
            deviceFrameCount: 6,
            deviceFrameIntervalMs: 83
        ))
        XCTAssertFalse(AhaKeyDefaultPictureWriteVerification.matches(
            expectedStartIndex: 26,
            expectedFrameCount: 6,
            expectedFrameIntervalMs: 83,
            deviceStartIndex: 10,
            deviceFrameCount: 6,
            deviceFrameIntervalMs: 83
        ))
    }

    func testLegacyUsesSingleSetThreeStateCommandsWithoutSessionFinish() {
        let plan = AhaKeyTaskPictureProtocolPlan.make(mode: .legacy, capabilities: nil)

        XCTAssertEqual(plan?.metadataFormat, .legacySingleSet)
        XCTAssertEqual(plan?.setIndices, [0])
        XCTAssertEqual(plan?.states, [.working, .waiting, .done])
        XCTAssertEqual(plan?.finishesRawUpload, false)
        XCTAssertEqual(plan?.supportsActiveSet, false)
        XCTAssertEqual(plan?.usesSessionUpload, false)
    }

    func testCurrentUsesNegotiatedDualSetFourStateSessionProtocol() {
        let capabilities = makeCapabilities(setCount: 2, stateCount: 4, flags: 0x09)
        let plan = AhaKeyTaskPictureProtocolPlan.make(mode: .current, capabilities: capabilities)

        XCTAssertEqual(plan?.metadataFormat, .currentSetAware)
        XCTAssertEqual(plan?.setIndices, [0, 1])
        XCTAssertEqual(plan?.states, [.idle, .working, .waiting, .done])
        XCTAssertEqual(plan?.finishesRawUpload, true)
        XCTAssertEqual(plan?.supportsActiveSet, true)
        XCTAssertEqual(plan?.usesSessionUpload, true)
    }

    func testCurrentHonorsReducedCapabilityCounts() {
        let capabilities = makeCapabilities(setCount: 1, stateCount: 3, flags: 0)
        let plan = AhaKeyTaskPictureProtocolPlan.make(mode: .current, capabilities: capabilities)

        XCTAssertEqual(plan?.setIndices, [0])
        XCTAssertEqual(plan?.states, [.working, .waiting, .done])
        XCTAssertEqual(plan?.supportsActiveSet, false)
        XCTAssertEqual(plan?.usesSessionUpload, false)
    }

    func testUnknownModesDoNotProduceWritablePlan() {
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .negotiating, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .legacyBaseOnly, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .restrictedUnknown, capabilities: nil))
    }

    func testSessionPacketizerPrefixesEveryPacketAndKeepsNegotiatedLimit() {
        let packets = AhaKeyPictureDataPacketizer.packets(
            for: Data([0, 1, 2, 3, 4, 5, 6]),
            maxPacketLength: 5,
            sessionID: 0x1234
        )

        XCTAssertEqual(packets, [
            Data([0x34, 0x12, 0, 1, 2]),
            Data([0x34, 0x12, 3, 4, 5]),
            Data([0x34, 0x12, 6]),
        ])
        XCTAssertTrue(packets.allSatisfy { $0.count <= 5 })
    }

    func testLegacyPacketizerDoesNotReserveSessionBytes() {
        XCTAssertEqual(
            AhaKeyPictureDataPacketizer.packets(
                for: Data([0, 1, 2, 3, 4]),
                maxPacketLength: 3,
                sessionID: nil
            ),
            [Data([0, 1, 2]), Data([3, 4])]
        )
    }

    func testSlotAllocatorUsesPrimaryGapBeforeReclaimRange() {
        XCTAssertEqual(AhaKeyPictureSlotAllocator.allocate(
            frameCount: 3,
            primaryRange: 10 ..< 20,
            reclaimRange: 30 ..< 35,
            occupiedRanges: [10 ..< 14, 17 ..< 20]
        ), 14)
    }

    func testSlotAllocatorFallsBackToReclaimAndNeverCrossesFactoryGap() {
        XCTAssertEqual(AhaKeyPictureSlotAllocator.allocate(
            frameCount: 3,
            primaryRange: 10 ..< 20,
            reclaimRange: 30 ..< 35,
            occupiedRanges: [10 ..< 19]
        ), 30)
        XCTAssertNil(AhaKeyPictureSlotAllocator.allocate(
            frameCount: 6,
            primaryRange: 10 ..< 20,
            reclaimRange: 30 ..< 35,
            occupiedRanges: [10 ..< 19]
        ))
    }

    func testSyncDecisionPreservesFactoryAssetWhenDraftIsEmpty() {
        XCTAssertEqual(AhaKeyTaskPictureSyncDecision.decide(
            hasLocalAsset: false, assetChanged: true,
            deviceStartIndex: 304, deviceFrameCount: 1,
            factorySlotBase: 304, reclaimRange: 296 ..< 304,
            overlapsDefaultPicture: false, deviceSchemaVersion: nil
        ), .markSynchronizedWithoutWrite)
    }

    func testSyncDecisionReuploadsCustomDraftWhenDevicePointsAtFactory() {
        XCTAssertEqual(AhaKeyTaskPictureSyncDecision.decide(
            hasLocalAsset: true, assetChanged: false,
            deviceStartIndex: 304, deviceFrameCount: 1,
            factorySlotBase: 304, reclaimRange: 296 ..< 304,
            overlapsDefaultPicture: false, deviceSchemaVersion: 3
        ), .upload([.deviceUsesFactoryAsset]))
    }

    func testSyncDecisionClearsOnlyNonFactoryDeviceSlot() {
        XCTAssertEqual(AhaKeyTaskPictureSyncDecision.decide(
            hasLocalAsset: false, assetChanged: false,
            deviceStartIndex: 20, deviceFrameCount: 2,
            factorySlotBase: 304, reclaimRange: 296 ..< 304,
            overlapsDefaultPicture: false, deviceSchemaVersion: 3
        ), .clear)
        XCTAssertEqual(AhaKeyTaskPictureSyncDecision.decide(
            hasLocalAsset: false, assetChanged: false,
            deviceStartIndex: 0, deviceFrameCount: 0,
            factorySlotBase: 304, reclaimRange: 296 ..< 304,
            overlapsDefaultPicture: false, deviceSchemaVersion: 3
        ), .skip)
    }

    private func makeCapabilities(setCount: Int, stateCount: Int, flags: UInt16) -> AhaKeyFirmwareCapabilities {
        AhaKeyFirmwareCapabilities(
            protocolVersion: 3, modeCount: 4, setCount: setCount, stateCount: stateCount,
            flags: flags, maxPacketSize: 244, userSlotLimit: 288, factorySlotBase: 304,
            factoryBundleVersion: 2, factoryManifestCRC: 0x822C5DF6,
            factoryStatus: 2, factoryError: 0, reclaimSlotBase: 296, reclaimSlotLimit: 304
        )
    }
}
