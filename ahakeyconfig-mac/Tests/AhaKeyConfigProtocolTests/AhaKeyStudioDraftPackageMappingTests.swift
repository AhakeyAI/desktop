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
}
