import XCTest
@testable import AhaKeyConfigShared

final class AhaKeyTaskPictureProtocolPlanTests: XCTestCase {
    func testEditedTaskPictureSetBecomesDesiredActiveSetWithoutASecondSelection() {
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.desiredActiveSet(
                editingSet: 1,
                supportedSetIndices: [0, 1]
            ),
            1
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.desiredActiveSet(
                editingSet: 1,
                supportedSetIndices: [0]
            ),
            0
        )
    }

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
        XCTAssertFalse(AhaKeyOLEDDirtyPolicy.isDirty(
            mode: .negotiating,
            baselineNamespace: "515C.legacy-base",
            defaultPictureChanged: false,
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

    func testDefaultPictureEncodingAutomaticallyCapsFramesForDevice() {
        XCTAssertEqual(
            AhaKeyDefaultPictureEncodingPlan.make(sourceFrameCount: 40, deviceFrameLimit: 16),
            AhaKeyDefaultPictureEncodingPlan(
                transmittedFrameCount: 16,
                encodedByteCount: 16 * 25_600
            )
        )
        XCTAssertEqual(
            AhaKeyDefaultPictureEncodingPlan.make(sourceFrameCount: 1, deviceFrameLimit: 16)?.encodedByteCount,
            25_600
        )
    }

    func testNegotiatingProtocolPreservesKnownBaselineAndRestoresRecentOnLaunch() {
        XCTAssertEqual(
            AhaKeySyncBaselineLoadPolicy.decision(mode: .negotiating, hasExistingBaseline: true),
            .preserveExisting
        )
        XCTAssertEqual(
            AhaKeySyncBaselineLoadPolicy.decision(mode: .negotiating, hasExistingBaseline: false),
            .restoreMostRecent
        )
        XCTAssertEqual(
            AhaKeySyncBaselineLoadPolicy.decision(mode: .legacyBaseOnly, hasExistingBaseline: true),
            .loadConnectedDevice
        )
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
        XCTAssertNil(
            AhaKeyTaskPictureProtocolPlan.make(mode: .current, capabilities: capabilities),
            "v3 单套且未广告 session 不得猜测可写协议"
        )
    }

    func testCurrentSessionCapableSingleSetPlan() {
        let capabilities = makeCapabilities(
            setCount: 1, stateCount: 4, flags: AhaKeyFirmwareCapabilities.sessionUploadFlag
        )
        let plan = AhaKeyTaskPictureProtocolPlan.make(mode: .current, capabilities: capabilities)
        XCTAssertEqual(plan?.setIndices, [0])
        XCTAssertEqual(plan?.supportsActiveSet, false)
        XCTAssertEqual(plan?.usesSessionUpload, true)
    }

    func testUnknownModesDoNotProduceWritablePlan() {
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .negotiating, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .legacyBaseOnly, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .restrictedUnknown, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(mode: .current, capabilities: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(.make(.malformedResponse)))
        XCTAssertEqual(
            AhaKeyTaskPictureProtocolPlan.make(.standard)?.metadataFormat,
            .legacySingleSet
        )
    }

    func testSealedRhinoFactShowsDualSetWithoutSnapshotCapabilities() {
        let plan = AhaKeyTaskPictureProtocolPlan.make(
            sealedFact: .init(family: .rhinoDualSet, sessionUploadAdvertised: false)
        )
        XCTAssertEqual(plan?.setIndices, [0, 1])
        XCTAssertEqual(plan?.states, AhaKeyTaskDisplayState.allCases)
        XCTAssertEqual(plan?.supportsActiveSet, true)
        XCTAssertEqual(plan?.usesSessionUpload, false)
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 1,
                draftSet: 1,
                previousPlan: nil,
                nextPlan: plan
            ),
            1
        )
    }

    func testSealedStandardAndSessionAndMissingFactsDoNotShowDualSetPicker() {
        let standard = AhaKeyTaskPictureProtocolPlan.make(sealedFact: .init(family: .legacyStandard))
        XCTAssertEqual(standard?.setIndices, [0])
        XCTAssertEqual(standard?.supportsActiveSet, false)

        let session = AhaKeyTaskPictureProtocolPlan.make(
            sealedFact: .init(family: .currentSessionCapable, sessionUploadAdvertised: true)
        )
        XCTAssertEqual(session?.setIndices, [0])
        XCTAssertEqual(session?.supportsActiveSet, false)

        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(sealedFact: nil))
        XCTAssertNil(AhaKeyTaskPictureProtocolPlan.make(sealedFact: .init(family: .unsupported)))
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterDraftRefresh(draftSet: 1, plan: standard),
            0
        )
    }

    func testSavedDraftBSurvivesNilPlanThenSealedRhinoArrival() {
        let rhino = AhaKeyTaskPictureProtocolPlan.make(
            sealedFact: .init(family: .rhinoDualSet, sessionUploadAdvertised: false)
        )
        let standard = AhaKeyTaskPictureProtocolPlan.make(sealedFact: .init(family: .legacyStandard))
        let unsupported = AhaKeyTaskPictureProtocolPlan.make(sealedFact: .init(family: .unsupported))

        let afterAppear = AhaKeyTaskPictureSetSelection.afterDraftRefresh(draftSet: 1, plan: nil)
        XCTAssertEqual(afterAppear, 1, "无 plan 的 onAppear 不得把 saved B 写成 A")

        let afterClobberedUI = AhaKeyTaskPictureSetSelection.afterPlanChange(
            currentSelection: 0,
            draftSet: 1,
            previousPlan: nil,
            nextPlan: rhino
        )
        XCTAssertEqual(afterClobberedUI, 1, "nil→Rhino 必须从仍为 B 的 draft 恢复")

        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 1,
                draftSet: 1,
                previousPlan: rhino,
                nextPlan: rhino
            ),
            1,
            "等价 Rhino snapshot/re-render 保持 B"
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 0,
                draftSet: 0,
                previousPlan: rhino,
                nextPlan: rhino
            ),
            0,
            "用户已选 A 的等价刷新保持 A"
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 1,
                draftSet: 1,
                previousPlan: rhino,
                nextPlan: standard
            ),
            0,
            "Rhino→Standard 才收敛 A"
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.afterPlanChange(
                currentSelection: 1,
                draftSet: 1,
                previousPlan: rhino,
                nextPlan: unsupported
            ),
            1,
            "Rhino→nil/unsupported 不得把选择写成 A"
        )
        XCTAssertEqual(
            AhaKeyTaskPictureSetSelection.desiredActiveSet(editingSet: 1, supportedSetIndices: []),
            1
        )
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
