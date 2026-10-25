import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class KimiManagedPermissionSyncTests: XCTestCase {
    private var directory: URL!
    private var config: URL!
    private var control: URL { directory.appendingPathComponent("control") }
    private let hooks = "\n[[hooks]]\ncommand = \"ahakeyconfig-agent hook KimiPreToolUse\"\n"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        config = directory.appendingPathComponent("config.toml")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func write(_ text: String) throws { try Data(text.utf8).write(to: config, options: .atomic) }
    @discardableResult
    private func sync(_ state: Int?) -> Bool {
        KimiConfigLeverSync.synchronizeManaged(switchState: state, configURL: config, controlDirectory: control)
    }
    private var mode: String? { KimiPermissionModeSync.configuredMode(configURL: config) }

    func testStartupDoesNotRewriteAndDisconnectRestoresOriginal() throws {
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertFalse(sync(nil))
        XCTAssertEqual(mode, "yolo")
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "auto")
        XCTAssertTrue(sync(1)); XCTAssertEqual(mode, "manual")
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "auto")
        XCTAssertTrue(sync(nil)); XCTAssertEqual(mode, "yolo")
        XCTAssertFalse(sync(nil)); XCTAssertEqual(mode, "yolo")
    }
    func testManualTakesEffectButUnknownStateRestoresOriginal() throws {
        for state in [2, 255] {
            try write("default_permission_mode = \"auto\"" + hooks)
            XCTAssertTrue(sync(1)); XCTAssertEqual(mode, "manual")
            XCTAssertTrue(sync(state)); XCTAssertEqual(mode, "auto")
        }
    }
    func testFailedParseCanBeRetriedWithoutAnotherLeverChange() throws {
        try write("default_permission_mode = \"manual\"\ndefault_permission_mode = \"manual\"" + hooks)
        XCTAssertFalse(sync(0))
        try write("default_permission_mode = \"manual\"" + hooks)
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "auto")
        XCTAssertTrue(sync(nil)); XCTAssertEqual(mode, "manual")
    }
    func testUnmanagedOrMentionOnlyConfigIsUntouched() throws {
        for text in ["default_permission_mode = \"auto\"\n",
                     "default_permission_mode = \"auto\"\n# ahakeyconfig-agent hook KimiPreToolUse\n"] {
            try write(text)
            XCTAssertFalse(sync(1))
            XCTAssertEqual(try String(contentsOf: config), text)
        }
    }
    func testUserChangeIsKeptOnPollingAndDisconnect() throws {
        try write("default_permission_mode = \"manual\"" + hooks)
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "auto")
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "yolo")
        XCTAssertTrue(sync(nil)); XCTAssertEqual(mode, "yolo")
    }
    func testNewLeverActionUsesLatestUserChoiceAsRestorationBaseline() throws {
        try write("default_permission_mode = \"manual\"" + hooks)
        XCTAssertTrue(sync(0))
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertTrue(sync(0))
        XCTAssertTrue(sync(1)); XCTAssertEqual(mode, "manual")
        XCTAssertTrue(sync(nil)); XCTAssertEqual(mode, "yolo")
    }
    func testRepeatedStatusDoesNotRewriteConfigOrJournal() throws {
        try write("default_permission_mode = \"auto\"" + hooks)
        XCTAssertTrue(sync(0))
        let journal = KimiManagedPermissionDefaults.journalURL(config)
        let old = Date(timeIntervalSince1970: 1_000)
        for file in [config!, journal] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        }
        XCTAssertTrue(sync(0))
        for file in [config!, journal] {
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, old)
        }
    }
    func testAbsentScalarAndUnrelatedChangesSurviveRestoration() throws {
        try write("telemetry = true\n" + hooks)
        XCTAssertTrue(sync(0)); XCTAssertEqual(mode, "auto")
        let changed = try String(contentsOf: config).replacingOccurrences(of: "telemetry = true", with: "telemetry = false # user edit")
        try write(changed)
        XCTAssertTrue(sync(nil)); XCTAssertNil(mode)
        XCTAssertTrue(try String(contentsOf: config).contains("telemetry = false # user edit"))
    }
    func testCrashBetweenWriteIntentAndScalarUpdateCanRestoreOriginal() throws {
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertTrue(sync(0))
        let file = KimiManagedPermissionDefaults.journalURL(config)
        var intent = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        intent["applied"] = "manual"; intent["lever"] = 1
        intent["pending"] = true; intent["beforeWrite"] = "auto"
        try JSONSerialization.data(withJSONObject: intent).write(to: file)
        XCTAssertTrue(sync(nil)); XCTAssertEqual(mode, "yolo")
    }
    func testPauseRestoresNativeDefaultAndRegisteredCustomHome() throws {
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertTrue(sync(0))
        let unrelated = directory.appendingPathComponent("missing.toml")
        XCTAssertTrue(ApprovalAutomationControl.revoke(.kimi, directory: control,
            codexURL: unrelated, kimiURL: unrelated, cursorDirectory: directory.appendingPathComponent("cursor")))
        XCTAssertEqual(mode, "yolo")
        XCTAssertFalse(sync(0)); XCTAssertEqual(mode, "yolo")
    }
    func testLegacyDefaultsAlsoRestoreOriginalWithoutClearingOtherSettings() throws {
        try write("default_yolo = true # user baseline\ntelemetry = true\n" + hooks)
        XCTAssertEqual(KimiManagedPermissionDefaults.synchronize(switchState: 1, configURL: config,
            controlDirectory: control, layout: .legacyPython), .updated)
        XCTAssertTrue(try String(contentsOf: config).contains("default_yolo = false # user baseline"))
        XCTAssertEqual(KimiManagedPermissionDefaults.synchronize(switchState: nil, configURL: config,
            controlDirectory: control, layout: .legacyPython), .restored)
        XCTAssertTrue(try String(contentsOf: config).contains("default_yolo = true # user baseline"))
        XCTAssertTrue(try String(contentsOf: config).contains("telemetry = true"))
    }
    func testLegacyMissingScalarIsRemovedOnRestore() throws {
        try write("telemetry = true\n" + hooks)
        XCTAssertEqual(KimiManagedPermissionDefaults.synchronize(switchState: 0, configURL: config,
            controlDirectory: control, layout: .legacyPython), .updated)
        XCTAssertTrue(try String(contentsOf: config).contains("default_yolo = true"))
        XCTAssertEqual(KimiManagedPermissionDefaults.synchronize(switchState: nil, configURL: config,
            controlDirectory: control, layout: .legacyPython), .restored)
        XCTAssertFalse(try String(contentsOf: config).contains("default_yolo"))
    }

}
