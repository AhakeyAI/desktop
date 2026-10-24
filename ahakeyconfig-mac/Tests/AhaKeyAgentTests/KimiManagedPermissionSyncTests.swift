import XCTest
@testable import AhaKeyConfigAgent
@testable import AhaKeyConfigShared

final class KimiManagedPermissionSyncTests: XCTestCase {
    private var directory: URL!
    private var config: URL!
    private let hooks = "\n[[hooks]]\ncommand = \"ahakeyconfig-agent hook KimiPreToolUse\"\n"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        config = directory.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testStartupAndDisconnectResetManagedDefaultsAndReconnectRestoresAuto() throws {
        try write("default_permission_mode = \"yolo\"" + hooks)
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: nil, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "manual")
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: 0, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "yolo")
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: nil, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "manual")
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: 0, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "yolo")
    }

    func testManualAndUnknownStatesDoNotLeaveAutoEnabled() throws {
        for state in [1, 2, 255] {
            try write("default_permission_mode = \"auto\"" + hooks)
            XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: state, configURL: config))
            XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "manual")
        }
    }

    func testFailedSyncIsRetriedWithoutAnotherLeverChange() throws {
        try write("default_permission_mode = \"manual\"\ndefault_permission_mode = \"manual\"" + hooks)
        XCTAssertFalse(KimiConfigLeverSync.synchronizeManaged(switchState: 0, configURL: config))
        try write("default_permission_mode = \"manual\"" + hooks)
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: 0, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "yolo")
    }

    func testUnmanagedConfigIsUntouchedAndHookInstallationIsDetected() throws {
        let original = "default_permission_mode = \"auto\"\n"
        try write(original)
        XCTAssertFalse(KimiConfigLeverSync.synchronizeManaged(switchState: nil, configURL: config))
        XCTAssertEqual(try String(contentsOf: config), original)
        try write(original + hooks)
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: nil, configURL: config))
        XCTAssertEqual(KimiPermissionModeSync.configuredMode(configURL: config), "manual")
    }

    func testRepeatedAutoKeepsUserAutoModeWithoutRewriting() throws {
        let original = "default_permission_mode = \"auto\"" + hooks
        try write(original)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: config.path)
        XCTAssertTrue(KimiConfigLeverSync.synchronizeManaged(switchState: 0, configURL: config))
        XCTAssertEqual(try String(contentsOf: config), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: config.path)[.modificationDate] as? Date, oldDate)
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: config, options: .atomic)
    }
}
