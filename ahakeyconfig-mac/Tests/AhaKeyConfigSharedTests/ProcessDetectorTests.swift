import XCTest
@testable import AhaKeyConfigShared

final class ProcessDetectorTests: XCTestCase {

    func testDefaultTargetsContainSupportedIDEs() {
        let targets = ProcessDetector.defaultTargets()
        let names = Set(targets.map { $0.name })
        XCTAssertTrue(names.contains("Cursor"))
        XCTAssertTrue(names.contains("Visual Studio Code"))
        XCTAssertTrue(names.contains("Claude Code"))
        XCTAssertTrue(names.contains("Kimi Code"))
        XCTAssertTrue(names.contains("Codex"))
    }

    func testTargetEqualityByID() {
        let a = ProcessDetector.Target(name: "Cursor", bundleIdentifier: "a")
        let b = ProcessDetector.Target(name: "Cursor", bundleIdentifier: "a")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.id, a.id)
    }

    func testSafetySettingsDefaults() {
        let settings = PowerProtectionSafetySettings()
        XCTAssertEqual(settings.l3DisableBatteryThreshold, 20)
        XCTAssertEqual(settings.fullReleaseBatteryThreshold, 10)
        XCTAssertEqual(settings.thermalThresholdCelsius, 45.0, accuracy: 0.01)
        XCTAssertEqual(settings.maxLidCloseDuration, 7200, accuracy: 0.01)
        XCTAssertFalse(settings.alwaysAllow)
    }

    func testSafetySettingsEquatable() {
        let a = PowerProtectionSafetySettings()
        let b = PowerProtectionSafetySettings()
        XCTAssertEqual(a, b)
    }
}
