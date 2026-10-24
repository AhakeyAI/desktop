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

    func testInterruptedOLEDUploadStatusIsRepairedAndMarkedForReupload() {
        // ≤0.2.3 上传中断后重启会停在「正在上传动图到 Mode 4…」（AHK-065）。
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode3)
        mode.oled.localAssetPath = "/tmp/custom.gif"
        mode.oled.statusLine = "正在上传动图到 Mode 4…"
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft).draft(for: .mode3).oled
        XCTAssertEqual(migrated.statusLine, AhaKeyOLEDDraft.interruptedUploadStatusLine)
        XCTAssertTrue(migrated.needsDeviceUpload)
        XCTAssertEqual(migrated.localAssetPath, "/tmp/custom.gif")
    }

    func testOLEDDraftWithoutPendingFlagDecodesAsUploaded() throws {
        let legacy = Data(#"{"localAssetPath":"/tmp/a.gif","statusLine":"x","framesPerSecond":12}"#.utf8)
        let decoded = try JSONDecoder().decode(AhaKeyOLEDDraft.self, from: legacy)
        XCTAssertFalse(decoded.needsDeviceUpload)

        var pending = decoded
        pending.needsDeviceUpload = true
        let roundTrip = try JSONDecoder().decode(AhaKeyOLEDDraft.self, from: JSONEncoder().encode(pending))
        XCTAssertTrue(roundTrip.needsDeviceUpload)
    }
}
