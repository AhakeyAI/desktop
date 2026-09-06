import CoreGraphics
import ImageIO
import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class AhaKeyStudioDraftPackageMappingTests: XCTestCase {
    func testFrozenScreenSnapshotExcludesDirtyKeysOnOtherPages() {
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.statusLine = "screen-dirty"
        mode.updateKey(AhaKeyKeyDraft(
            role: .voice,
            shortcut: mode.key(for: .voice).shortcut,
            description: "key-dirty",
            voicePreset: mode.key(for: .voice).voicePreset
        ))
        current.updateMode(mode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: [
                .screenStatusLine(modeSlot: 0): AhaKeyStudioFieldAuthority(
                    value: .text(""),
                    trust: .verified,
                    provenance: .deviceReadback
                ),
            ],
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        XCTAssertEqual(snapshot.pageID, .screen(modeSlot: 0))
        XCTAssertTrue(snapshot.fields.allSatisfy {
            AhaKeyStudioFieldOwnership.page(for: $0.id) == .screen(modeSlot: 0)
        })
        XCTAssertFalse(snapshot.fields.contains { field in
            if case .keyAction = field.id { return true }
            return false
        })
        let status = snapshot.fields.first { $0.id == .screenStatusLine(modeSlot: 0) }
        XCTAssertEqual(status?.isDirty, true)
        XCTAssertEqual(status?.value, .text("screen-dirty"))
    }

    func testFrozenKeyPageDoesNotIncludeScreenFields() {
        let draft = AhaKeyStudioDraft.default
        let snapshot = draft.frozenPageSnapshot(
            pageID: .key(modeSlot: 0, role: .approve),
            lastSyncedDraft: draft,
            profile: .legacyStandard
        )
        XCTAssertTrue(snapshot.fields.allSatisfy {
            AhaKeyStudioFieldOwnership.page(for: $0.id) == .key(modeSlot: 0, role: .approve)
        })
        XCTAssertTrue(snapshot.fields.contains { $0.id == .keyAction(modeSlot: 0, role: .approve) })
        XCTAssertFalse(snapshot.fields.contains { $0.id == .screenStatusLine(modeSlot: 0) })
    }

    func testNilLastSyncedDraftDoesNotTreatUnknownCurrentAsClean() {
        let draft = AhaKeyStudioDraft.default
        let snapshot = draft.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: nil,
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        XCTAssertTrue(snapshot.fields.contains { $0.isDirty })
        XCTAssertTrue(snapshot.fields.allSatisfy { $0.baseline.trust == .unknown })
        XCTAssertNotEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
            .noOp
        )
    }

    func testDeviceBaselineWinsWhenLocalCacheDiverges() {
        var current = AhaKeyStudioDraft.default
        var synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.statusLine = "from-device"
        current.updateMode(mode)
        var syncedMode = synced.draft(for: .mode0)
        syncedMode.oled.statusLine = "stale-cache"
        synced.updateMode(syncedMode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: [
                .screenStatusLine(modeSlot: 0): AhaKeyStudioFieldAuthority(
                    value: .text("from-device"),
                    trust: .verified,
                    provenance: .deviceReadback
                ),
            ],
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        let status = snapshot.fields.first { $0.id == .screenStatusLine(modeSlot: 0) }
        XCTAssertEqual(status?.isDirty, true)
        XCTAssertEqual(status?.baseline.trust, .verified)
        XCTAssertEqual(status?.baseline.value, .text("from-device"))
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(
                AhaKeyStudioPageSnapshot(
                    pageID: .screen(modeSlot: 0),
                    profile: .rhinoDualSet(sessionUploadAdvertised: false),
                    fields: [status!]
                )
            ),
            .noOp
        )
    }

    func testLeverAndPowerMappingYieldsNoFields() {
        let draft = AhaKeyStudioDraft.default
        let lever = draft.frozenPageSnapshot(
            pageID: .lever,
            lastSyncedDraft: draft,
            profile: .legacyStandard
        )
        XCTAssertTrue(lever.fields.isEmpty)
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(lever),
            .unsupportedPage
        )
    }

    func testMappingStatusOnlyDirtyDoesNotCarryUneditedUnknownFields() {
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.statusLine = "only-status"
        current.updateMode(mode)

        let pending = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(pending),
            .requiresOverwriteConfirmation
        )

        let confirmed = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            profile: .rhinoDualSet(sessionUploadAdvertised: false),
            overwriteConfirmed: true
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(confirmed) else {
            return XCTFail("确认后应只写 status")
        }
        XCTAssertEqual(plan.fieldMask, [.screenStatusLine(modeSlot: 0)])
        XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
        XCTAssertEqual(plan.statusLine, "only-status")
        XCTAssertTrue(confirmed.fields.contains { !$0.isDirty && $0.baseline.trust == .unknown })
    }

    func testMappingStandardActiveSetOnlyDoesNotCreateAWrite() {
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.activeGIFSet = 1
        current.updateMode(mode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: [
                .screenActiveSet(modeSlot: 0): AhaKeyStudioFieldAuthority(
                    value: .integer(0),
                    trust: .verified,
                    provenance: .deviceReadback
                ),
            ],
            profile: .legacyStandard
        )
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
            .noOp
        )
    }

    func testMappingRhinoActiveSetOnlyEmitsSetActiveSet() {
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.activeGIFSet = 1
        current.updateMode(mode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: [
                .screenActiveSet(modeSlot: 0): AhaKeyStudioFieldAuthority(
                    value: .integer(0),
                    trust: .verified,
                    provenance: .deviceReadback
                ),
            ],
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot) else {
            return XCTFail("Rhino activeSet dirty 应发 0x97")
        }
        XCTAssertEqual(plan.fieldMask, [.screenActiveSet(modeSlot: 0)])
        XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertTrue(plan.emitsSetActiveSetOpcode)
        XCTAssertTrue(plan.resources.isEmpty)
    }

    func testMappingCurrentActiveSetOnlyEmitsSetActiveSet() {
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.activeGIFSet = 1
        current.updateMode(mode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: [
                .screenActiveSet(modeSlot: 0): AhaKeyStudioFieldAuthority(
                    value: .integer(0),
                    trust: .verified,
                    provenance: .deviceReadback
                ),
            ],
            profile: .currentSessionCapable
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot) else {
            return XCTFail("current activeSet dirty 应发 0x97")
        }
        XCTAssertEqual(plan.fieldMask, [.screenActiveSet(modeSlot: 0)])
        XCTAssertEqual(Set(plan.values.keys), plan.fieldMask)
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertTrue(plan.emitsSetActiveSetOpcode)
        XCTAssertTrue(plan.resources.isEmpty)
    }

    func testMappingStandardPictureAndActiveSetUsesImplicitActivation() throws {
        let gif = try writeTestGIF()
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.activeGIFSet = 1
        for state in AhaKeyTaskDisplayState.legacyStates {
            mode.oled.updateTaskAsset(
                set: 1,
                asset: AhaKeyTaskGIFAssetDraft(
                    state: state,
                    localAssetPath: gif.path,
                    framesPerSecond: 12
                )
            )
        }
        current.updateMode(mode)

        let snapshot = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: pictureAuthorities(set: 1, oldPath: "/tmp/old.gif"),
            profile: .legacyStandard,
            overwriteConfirmed: true
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot) else {
            return XCTFail("Standard picture+active 应变为隐式激活 write")
        }
        XCTAssertFalse(plan.fieldMask.contains(.screenActiveSet(modeSlot: 0)))
        XCTAssertEqual(plan.fieldMask, Set(plan.values.keys))
        XCTAssertEqual(plan.activateTaskSet, 1)
        XCTAssertFalse(plan.emitsSetActiveSetOpcode)
        XCTAssertEqual(plan.resources.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertTrue(plan.resources.allSatisfy { $0.logicalIdentifier.rawValue.contains("-set0-") })
        XCTAssertTrue(plan.overwriteSemantic)
    }

    func testMappingMalformedTypedValuesFromDraftSnapshotFailClosed() throws {
        let gif = try writeTestGIF()
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.statusLine = "dirty-status"
        mode.oled.framesPerSecond = 15
        mode.oled.activeGIFSet = 1
        mode.oled.updateTaskAsset(
            set: 0,
            asset: AhaKeyTaskGIFAssetDraft(
                state: .working,
                localAssetPath: gif.path,
                framesPerSecond: 12
            )
        )
        mode.updateKey(AhaKeyKeyDraft(
            role: .approve,
            shortcut: mode.key(for: .approve).shortcut,
            description: "dirty-desc",
            voicePreset: mode.key(for: .approve).voicePreset
        ))
        var voice = mode.key(for: .voice)
        voice.voicePreset = voice.voicePreset == .macOSNative ? .typeless : .macOSNative
        mode.updateKey(voice)
        mode.lightBar.brightness = 80
        if let index = mode.lightBar.stateMappings.firstIndex(where: { $0.state.rawValue == 1 }) {
            mode.lightBar.stateMappings[index].effect =
                mode.lightBar.stateMappings[index].effect == .off ? .singleMove : .off
        }
        current.updateMode(mode)

        let mutations: [(AhaKeyStudioPageID, AhaKeyOLEDCompatibilityProfile, AhaKeyStudioFieldID, AhaKeyStudioFieldValue)] = [
            (.screen(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .screenStatusLine(modeSlot: 0), .integer(1)),
            (.screen(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .screenFramesPerSecond(modeSlot: 0), .text("15")),
            (.screen(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .screenActiveSet(modeSlot: 0), .text("1")),
            (.screen(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .working), .text("not-an-asset")),
            (.key(modeSlot: 0, role: .approve), .rhinoDualSet(sessionUploadAdvertised: false), .keyAction(modeSlot: 0, role: .approve), .text("x")),
            (.key(modeSlot: 0, role: .approve), .rhinoDualSet(sessionUploadAdvertised: false), .keyDescription(modeSlot: 0, role: .approve), .integer(1)),
            (.key(modeSlot: 0, role: .voice), .rhinoDualSet(sessionUploadAdvertised: false), .keyVoicePreset(modeSlot: 0, role: .voice), .integer(1)),
            (.lights(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .lightBrightness(modeSlot: 0), .text("80")),
            (.lights(modeSlot: 0), .rhinoDualSet(sessionUploadAdvertised: false), .lightMapping(modeSlot: 0, state: 1), .integer(1)),
        ]
        for (page, profile, fieldID, badValue) in mutations {
            let syncedSnapshot = synced.frozenPageSnapshot(
                pageID: page,
                lastSyncedDraft: synced,
                profile: profile
            )
            var authorities: [AhaKeyStudioFieldID: AhaKeyStudioFieldAuthority] = [:]
            for field in syncedSnapshot.fields {
                authorities[field.id] = AhaKeyStudioFieldAuthority(
                    value: field.value,
                    trust: .verified,
                    provenance: .deviceReadback
                )
            }
            var snapshot = current.frozenPageSnapshot(
                pageID: page,
                lastSyncedDraft: synced,
                fieldAuthorities: authorities,
                profile: profile
            )
            guard let index = snapshot.fields.firstIndex(where: { $0.id == fieldID }) else {
                return XCTFail("mapping 必须产出 \(fieldID)")
            }
            snapshot.fields[index].value = badValue
            snapshot.fields[index].isDirty = true
            XCTAssertEqual(
                AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
                .missingTrustedPageCache,
                "\(fieldID)"
            )
        }
    }

    func testMappingPictureOnlyRejectsOutOfRangeSelectedSet() throws {
        let gif = try writeTestGIF()
        var current = AhaKeyStudioDraft.default
        let synced = current
        var mode = current.draft(for: .mode0)
        mode.oled.updateTaskAsset(
            set: 0,
            asset: AhaKeyTaskGIFAssetDraft(
                state: .working,
                localAssetPath: gif.path,
                framesPerSecond: 12
            )
        )
        current.updateMode(mode)

        for selected in [-1, 2] {
            let snapshot = current.frozenPageSnapshot(
                pageID: .screen(modeSlot: 0),
                lastSyncedDraft: synced,
                profile: .legacyStandard,
                selectedTaskSet: selected,
                overwriteConfirmed: true
            )
            XCTAssertEqual(
                AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
                .missingTrustedPageCache,
                "selected=\(selected)"
            )
        }
    }

    func testMappingUnknownSiblingsRequireConfirmationThenOverwrite() throws {
        let gif = try writeTestGIF()
        var synced = AhaKeyStudioDraft.default
        var syncedMode = synced.draft(for: .mode0)
        for state in AhaKeyTaskDisplayState.legacyStates {
            syncedMode.oled.updateTaskAsset(
                set: 0,
                asset: AhaKeyTaskGIFAssetDraft(
                    state: state,
                    localAssetPath: gif.path,
                    framesPerSecond: 12
                )
            )
        }
        synced.updateMode(syncedMode)

        var current = synced
        var mode = current.draft(for: .mode0)
        mode.oled.updateTaskAsset(
            set: 0,
            asset: AhaKeyTaskGIFAssetDraft(
                state: .working,
                localAssetPath: gif.path,
                framesPerSecond: 13
            )
        )
        current.updateMode(mode)

        var authorities = pictureAuthorities(set: 0, oldPath: gif.path)
        authorities[.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .waiting)] = .unknown
        authorities[.screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done)] = .unknown

        let pending = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: authorities,
            profile: .legacyStandard
        )
        XCTAssertEqual(
            AhaKeyStudioPackageAssembler.assembleScopedPage(pending),
            .requiresOverwriteConfirmation
        )

        let confirmed = current.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: synced,
            fieldAuthorities: authorities,
            profile: .legacyStandard,
            overwriteConfirmed: true
        )
        guard case .write(let plan) = AhaKeyStudioPackageAssembler.assembleScopedPage(confirmed) else {
            return XCTFail("确认后应覆盖 unknown siblings")
        }
        XCTAssertTrue(plan.overwriteSemantic)
        XCTAssertEqual(plan.values.count, AhaKeyTaskDisplayState.legacyStates.count)
        XCTAssertEqual(plan.fieldMask, Set(plan.values.keys))
    }

    func testMappingStandardNonEmittedPicturesAreZeroOperation() throws {
        let gif = try writeTestGIF()
        var current = AhaKeyStudioDraft.default
        let synced = current
        var idleMode = current.draft(for: .mode0)
        idleMode.oled.updateTaskAsset(
            set: 0,
            asset: AhaKeyTaskGIFAssetDraft(
                state: .idle,
                localAssetPath: gif.path,
                framesPerSecond: 12
            )
        )
        current.updateMode(idleMode)
        for overwriteConfirmed in [false, true] {
            let snapshot = current.frozenPageSnapshot(
                pageID: .screen(modeSlot: 0),
                lastSyncedDraft: synced,
                profile: .legacyStandard,
                overwriteConfirmed: overwriteConfirmed
            )
            XCTAssertEqual(
                AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
                .noOp,
                "idle-only confirmed=\(overwriteConfirmed)"
            )
        }

        current = AhaKeyStudioDraft.default
        var unselectedMode = current.draft(for: .mode0)
        for state in AhaKeyTaskDisplayState.legacyStates {
            unselectedMode.oled.updateTaskAsset(
                set: 1,
                asset: AhaKeyTaskGIFAssetDraft(
                    state: state,
                    localAssetPath: gif.path,
                    framesPerSecond: 12
                )
            )
        }
        current.updateMode(unselectedMode)
        for overwriteConfirmed in [false, true] {
            let snapshot = current.frozenPageSnapshot(
                pageID: .screen(modeSlot: 0),
                lastSyncedDraft: synced,
                profile: .legacyStandard,
                selectedTaskSet: 0,
                overwriteConfirmed: overwriteConfirmed
            )
            XCTAssertEqual(
                AhaKeyStudioPackageAssembler.assembleScopedPage(snapshot),
                .noOp,
                "unselected-set confirmed=\(overwriteConfirmed)"
            )
        }
    }

    private func pictureAuthorities(
        set: Int,
        oldPath: String
    ) -> [AhaKeyStudioFieldID: AhaKeyStudioFieldAuthority] {
        var authorities: [AhaKeyStudioFieldID: AhaKeyStudioFieldAuthority] = [
            .screenActiveSet(modeSlot: 0): AhaKeyStudioFieldAuthority(
                value: .integer(0),
                trust: .verified,
                provenance: .deviceReadback
            ),
        ]
        for state in AhaKeyTaskDisplayState.legacyStates.compactMap({
            AhaKeyDesiredConfiguration.TaskDisplayState(rawValue: UInt8($0.rawValue))
        }) {
            authorities[.screenTaskAsset(modeSlot: 0, setIndex: set, state: state)] =
                AhaKeyStudioFieldAuthority(
                    value: .asset(
                        path: oldPath, framesPerSecond: 12, declaredFrameCount: 3,
                        pixelWidth: 160, pixelHeight: 80
                    ),
                    trust: .verified,
                    provenance: .deviceReadback
                )
        }
        return authorities
    }

    private func writeTestGIF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-c2r4-\(UUID().uuidString).gif")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "com.compuserve.gif" as CFString,
            3,
            nil
        ))
        for _ in 0..<3 {
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: 160,
                height: 80,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 80))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testPNGDraftIdentityUsesSealedGIF() throws {
        let png = try writeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let sealed = try AhaKeyStudioCanonicalTaskAsset.seal(source: png)
        defer {
            if let temp = sealed.ownedTemporaryFile {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode0)
        mode.oled.updateTaskAsset(
            set: 0,
            asset: AhaKeyTaskGIFAssetDraft(
                state: .done,
                localAssetPath: png.path,
                framesPerSecond: 12
            )
        )
        draft.updateMode(mode)
        let snapshot = draft.frozenPageSnapshot(
            pageID: .screen(modeSlot: 0),
            lastSyncedDraft: AhaKeyStudioDraft.default,
            profile: .rhinoDualSet(sessionUploadAdvertised: false)
        )
        let field = snapshot.fields.first {
            $0.id == .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done)
        }
        XCTAssertEqual(field?.value.taskAssetValue?.mediaType, AhaKeyStudioCanonicalTaskAsset.gifMediaType)
        XCTAssertEqual(field?.value.taskAssetValue?.sha256, sealed.sha256)
        XCTAssertEqual(field?.value.taskAssetValue?.byteCount, sealed.byteCount)
        XCTAssertEqual(field?.value.taskAssetValue?.pixelWidth, 160)
        XCTAssertEqual(field?.value.taskAssetValue?.pixelHeight, 80)
        let synced = AhaKeyStudioFrozenField(
            id: .screenTaskAsset(modeSlot: 0, setIndex: 0, state: .done),
            value: field!.value,
            isDirty: true,
            baseline: .init(trust: .writeConfirmed, value: field!.value)
        )
        XCTAssertTrue(AhaKeyStudioPageDiffer.isStrictNoOp(synced))
    }

    private func writeTestPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahakey-c4r2-\(UUID().uuidString).png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 800,
            height: 400,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let image = try XCTUnwrap(context.makeImage())
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
