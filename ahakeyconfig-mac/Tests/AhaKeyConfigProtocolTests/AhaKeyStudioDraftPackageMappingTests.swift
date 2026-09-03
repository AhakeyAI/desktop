import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class AhaKeyStudioDraftPackageMappingTests: XCTestCase {
    func testFrozenScreenSnapshotExcludesDirtyKeysOnOtherPages() {
        var current = AhaKeyStudioDraft.default
        var synced = current
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
            fieldTrust: [
                .screenStatusLine(modeSlot: 0): .verified,
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
}
