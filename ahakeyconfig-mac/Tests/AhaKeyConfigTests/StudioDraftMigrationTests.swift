import XCTest
@testable import AhaKeyConfig

final class StudioDraftMigrationTests: XCTestCase {
    func testCurrentSavedShortcutDoesNotTurnBackIntoClaudeMacro() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode0)
        var reject = mode.key(for: .reject)
        reject.macro = []
        reject.shortcut = ShortcutBinding(keyCode: HIDUsage.enter)
        mode.updateKey(reject)
        draft.updateMode(mode)
        AhaKeyStudioStore.save(draft, to: defaults)
        AhaKeyStudioStore.saveSynced(draft, to: defaults)
        for _ in 0..<2 {
            let loaded = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults))
            let baseline = try XCTUnwrap(AhaKeyStudioStore.loadSynced(from: defaults))
            XCTAssertEqual(loaded.draft(for: .mode0).key(for: .reject), reject)
            XCTAssertEqual(baseline.draft(for: .mode0).key(for: .reject), reject)
            AhaKeyStudioStore.save(loaded, to: defaults)
        }
    }

    func testCurrentSavedEnterAndFiftyPercentBrightnessRemainUserChoices() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode3)
        var key = mode.key(for: .submit)
        key.shortcut = ShortcutBinding(keyCode: HIDUsage.enter)
        key.description = "Enter"
        mode.updateKey(key)
        mode.lightBar.brightness = 50
        draft.updateMode(mode)
        AhaKeyStudioStore.save(draft, to: defaults)
        let loaded = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults)).draft(for: .mode3)
        XCTAssertEqual(loaded.key(for: .submit), key)
        XCTAssertEqual(loaded.lightBar.brightness, 50)
    }

    func testCurrentSavedDraftStillRepairsInterruptedUpload() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode3)
        mode.oled.localAssetPath = "/tmp/owner-artwork.gif"
        mode.oled.statusLine = "正在上传动图到 Mode 4…"
        draft.updateMode(mode)
        AhaKeyStudioStore.save(draft, to: defaults)
        let oled = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults)).draft(for: .mode3).oled
        XCTAssertEqual(oled.statusLine, AhaKeyOLEDDraft.interruptedUploadStatusLine)
        XCTAssertTrue(oled.needsDeviceUpload)
        XCTAssertEqual(oled.localAssetPath, mode.oled.localAssetPath)
    }

    func testUntaggedLegacyDraftStillMigratesAndCurrentEncodingKeepsModesReadable() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode3)
        var key = mode.key(for: .submit)
        key.shortcut = ShortcutBinding(keyCode: HIDUsage.enter)
        key.description = "回车"
        mode.updateKey(key)
        draft.updateMode(mode)
        defaults.set(try JSONEncoder().encode(draft), forKey: "ahakey.studio.draft.v1")
        let loaded = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults))
        XCTAssertEqual(loaded.draft(for: .mode3).key(for: .submit).shortcut.keyCode, HIDUsage.backspace)
        AhaKeyStudioStore.save(loaded, to: defaults)
        let data = try XCTUnwrap(defaults.data(forKey: "ahakey.studio.draft.v1"))
        XCTAssertEqual(try JSONDecoder().decode(AhaKeyStudioDraft.self, from: data), loaded)
    }

    func testCursorRejectMacroCreatedFromDefaultShortcutSurvivesRepeatedLoads() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode1)
        var key = mode.key(for: .reject)
        XCTAssertEqual(key.shortcut, ShortcutBinding(keyCode: HIDUsage.backspace))
        // This is exactly what switching the default key to Macro produces.
        key.macro = [MacroStep(action: .downKey, param: HIDUsage.backspace),
                     MacroStep(action: .upKey, param: HIDUsage.backspace)]
        mode.updateKey(key)
        draft.updateMode(mode)
        AhaKeyStudioStore.save(draft, to: defaults)
        for _ in 0..<2 {
            let loaded = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults))
            XCTAssertEqual(loaded.draft(for: .mode1).key(for: .reject), key)
            AhaKeyStudioStore.save(loaded, to: defaults)
        }
    }

    func testCursorPlainDefaultAndLegacyCommandShortcutMigrationRemainPlain() {
        var draft = AhaKeyStudioDraft.default
        let expected = draft.draft(for: .mode1)
        XCTAssertTrue(AhaKeyStudioStore.migratedDraft(from: draft).draft(for: .mode1).key(for: .reject).macro.isEmpty)
        var mode = expected
        var approve = mode.key(for: .approve)
        var reject = mode.key(for: .reject)
        approve.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        reject.shortcut = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.backspace)
        mode.updateKey(approve)
        mode.updateKey(reject)
        draft.updateMode(mode)
        let migrated = AhaKeyStudioStore.migratedDraft(from: draft).draft(for: .mode1)
        XCTAssertEqual(migrated.key(for: .approve), expected.key(for: .approve))
        XCTAssertEqual(migrated.key(for: .reject), expected.key(for: .reject))
    }

    func testSavedRejectMacroSurvivesRepeatedLoadsWithLegacyShortcutAndLabel() throws {
        let suite = "StudioDraftMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for slot in [AhaKeyModeSlot.mode0, .mode2, .mode3] {
            var draft = AhaKeyStudioDraft.default
            var mode = draft.draft(for: slot)
            var key = mode.key(for: .reject)
            key.shortcut = ShortcutBinding(keyCode: HIDUsage.escape)
            key.description = "Reject"
            key.macro = [MacroStep(action: .downKey, param: HIDUsage.escape),
                         MacroStep(action: .upKey, param: HIDUsage.escape)]
            mode.updateKey(key)
            draft.updateMode(mode)
            AhaKeyStudioStore.save(draft, to: defaults)
            for _ in 0..<2 {
                let loaded = try XCTUnwrap(AhaKeyStudioStore.load(from: defaults))
                XCTAssertEqual(loaded.draft(for: slot).key(for: .reject).macro, key.macro, "\(slot)")
                AhaKeyStudioStore.save(loaded, to: defaults)
            }
        }
    }

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
