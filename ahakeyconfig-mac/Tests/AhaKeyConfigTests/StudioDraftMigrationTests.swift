import XCTest
@testable import AhaKeyConfig

final class StudioDraftMigrationTests: XCTestCase {
    func testChineseLegacySubmitMigratesInEveryMode() {
        for mode in AhaKeyModeSlot.allCases {
            var draft = AhaKeyStudioDraft.default
            var oldMode = draft.draft(for: mode)
            var submit = oldMode.key(for: .submit)
            submit.shortcut = ShortcutBinding(keyCode: HIDUsage.enter)
            submit.description = "回车"
            oldMode.updateKey(submit)
            draft.updateMode(oldMode)

            let migrated = AhaKeyStudioStore.migratedDraft(from: draft).draft(for: mode).key(for: .submit)
            XCTAssertEqual(migrated.shortcut, ShortcutBinding(keyCode: HIDUsage.backspace))
            XCTAssertEqual(migrated.description, "Backspace")
        }
    }

    func testChineseLegacyApprovalLabelsMigrateToCurrentBindings() {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode0)
        for (role, code, description) in [
            (AhaKeyKeyRole.approve, HIDUsage.enter, "批准"),
            (AhaKeyKeyRole.reject, HIDUsage.escape, "拒绝"),
        ] {
            var key = mode.key(for: role)
            key.shortcut = ShortcutBinding(keyCode: code)
            key.macro = []
            key.description = description
            mode.updateKey(key)
        }
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft).draft(for: .mode0)
        let expected = AhaKeyModeDraft.default(for: .mode0)
        XCTAssertEqual(migrated.key(for: .approve), expected.key(for: .approve))
        XCTAssertEqual(migrated.key(for: .reject), expected.key(for: .reject))
    }
}
