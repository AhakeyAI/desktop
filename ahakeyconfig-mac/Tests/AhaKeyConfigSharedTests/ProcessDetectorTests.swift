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

    // MARK: - 去重发布（阶段 5）

    /// 两次相同检测结果：decidePublish 返回 nil（零发布）。
    func testDecidePublishSameResultPublishesNothing() {
        let target = ProcessDetector.Target(name: "Cursor", bundleIdentifier: "com.example.cursor")
        let old = ProcessDetector.DetectionSnapshot(runningTargets: [target], isAnyTargetRunning: true)
        let new = ProcessDetector.DetectionSnapshot(runningTargets: [target], isAnyTargetRunning: true)
        XCTAssertNil(ProcessDetector.decidePublish(old: old, new: new))
    }

    /// 目标集合变化：恰好发布一次新结果。
    func testDecidePublishTargetSetChangePublishesOnce() {
        let cursor = ProcessDetector.Target(name: "Cursor", bundleIdentifier: "com.example.cursor")
        let claude = ProcessDetector.Target(name: "Claude Code", processNames: ["claude"])
        let old = ProcessDetector.DetectionSnapshot(runningTargets: [cursor], isAnyTargetRunning: true)
        let new = ProcessDetector.DetectionSnapshot(runningTargets: [cursor, claude], isAnyTargetRunning: true)

        let decided = ProcessDetector.decidePublish(old: old, new: new)
        XCTAssertEqual(decided, new)
        // 已发布的新结果再评估一次：相同则零发布（一次真实变化最多发布一次）
        XCTAssertNil(ProcessDetector.decidePublish(old: new, new: new))
    }

    /// isAnyTargetRunning 翻转：发布一次。
    func testDecidePublishIsAnyTargetRunningFlipPublishes() {
        let cursor = ProcessDetector.Target(name: "Cursor", bundleIdentifier: "com.example.cursor")
        let running = ProcessDetector.DetectionSnapshot(runningTargets: [cursor], isAnyTargetRunning: true)
        let idle = ProcessDetector.DetectionSnapshot(runningTargets: [], isAnyTargetRunning: false)

        XCTAssertEqual(ProcessDetector.decidePublish(old: running, new: idle), idle)
        XCTAssertEqual(ProcessDetector.decidePublish(old: idle, new: running), running)
        // 稳态（持续空 / 持续同集合）不发布
        XCTAssertNil(ProcessDetector.decidePublish(old: idle, new: idle))
    }
}
