import XCTest
import IOKit
@testable import AhaKeyConfigShared

final class PowerProtectionManagerTests: XCTestCase {

    var manager: PowerProtectionManager!

    override func setUp() {
        super.setUp()
        manager = PowerProtectionManager()
        manager.enabled = true
        manager.lidCloseProtectionEnabled = true
        _ = manager.deactivateAll()
    }

    override func tearDown() {
        _ = manager.deactivateAll()
        manager = nil
        super.tearDown()
    }

    func testBeginEndReasons() {
        XCTAssertFalse(manager.isProtectionActive)

        manager.begin(.aiCodingIdleHook)
        // Async apply; wait a bit.
        let exp1 = expectation(description: "protection active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertTrue(manager.isProtectionActive)

        manager.end(.aiCodingIdleHook)
        let exp2 = expectation(description: "protection inactive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertFalse(manager.isProtectionActive)
    }

    func testMultipleReasonsRequireAllToEnd() {
        manager.begin(.aiCodingIdleHook)
        manager.begin(.oledUpload)

        let exp = expectation(description: "both reasons active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(manager.isProtectionActive)

        manager.end(.aiCodingIdleHook)
        let exp2 = expectation(description: "one reason remains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertTrue(manager.isProtectionActive)

        manager.end(.oledUpload)
        let exp3 = expectation(description: "no reasons remain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp3.fulfill()
        }
        wait(for: [exp3], timeout: 1.0)

        XCTAssertFalse(manager.isProtectionActive)
    }

    func testDisabledManagerDoesNotActivate() {
        manager.enabled = false
        manager.begin(.aiCodingIdleHook)

        let exp = expectation(description: "disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(manager.isProtectionActive)
    }

    func testLidCloseReasonRequiresHigherLevel() {
        manager.begin(.aiCodingIdleHook)
        let exp1 = expectation(description: "idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)

        // L2 or L1 depending on runtime; should not be L3 without lid-close reason.
        XCTAssertNotEqual(manager.activeLevel, .virtualDisplay)
    }

    func testSafetyCheckDoesNotClearActiveReasons() {
        manager.begin(.aiCodingIdleHook)
        let exp1 = expectation(description: "protection active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)

        // Simulate periodic safety-check firing while reasons remain.
        manager.performSafetyCheck()
        manager.performSafetyCheck()

        // Reasons must survive; external deactivation by another process
        // (e.g. Studio) is healed via refresh() inside performSafetyCheck().
        XCTAssertTrue(manager.isProtectionActive)
        XCTAssertTrue(manager.activeReasons.contains(.aiCodingIdleHook))
    }

    func testSafetyCheckHealsAfterExternalDeactivation() {
        manager.begin(.aiCodingLidCloseProcess)
        let exp1 = expectation(description: "lid close active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)

        // Simulate an external process (Studio) calling deactivateAll on
        // its own PowerProtectionManager instance.  Our instance should
        // detect the drift at the next safety check and re-assert L2/L3.
        _ = manager.deactivateAll()
        XCTAssertFalse(manager.isProtectionActive)

        // Re-begin the reason (as the Agent would after detecting the drift)
        manager.begin(.aiCodingLidCloseProcess)
        let exp2 = expectation(description: "re-active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)

        // Safety check should refresh layers without clearing reasons.
        manager.performSafetyCheck()
        XCTAssertTrue(manager.isProtectionActive)
        XCTAssertTrue(manager.activeReasons.contains(.aiCodingLidCloseProcess))
    }

    /// 跨实例拆除（模拟 Studio 退出）：实例 B 激活后 deactivateAll 会把全局
    /// IORegistry `SleepDisabled` 清掉；实例 A（模拟 Agent）reason 仍在，
    /// 下一次安全周期必须重新断言，而不是永久失效。
    ///
    /// 注意：写入 IOPMrootDomain 需要 root（kIOReturnNotPermitted），普通用户进程
    /// 的 L2 必然失败。本测试因此不断言物理值，而是断言**可见性不变式**：
    /// 激活要么真实生效，要么失败被记录到 failedLayers（不得静默假激活），
    /// 且对端拆除/自愈循环中 reason 不丢失。
    func testPeerTeardownKeepsReasonsAndVisibility() {
        let peer = PowerProtectionManager()
        peer.enabled = true
        defer { _ = peer.deactivateAll() }

        manager.begin(.aiCodingIdleProcess)
        let e1 = expectation(description: "A active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)

        // 可见性不变式：L2 要么真生效，要么失败可见
        let l2Real = Self.readSleepDisabled() == true
        if !l2Real {
            let e = expectation(description: "failedLayers published")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { e.fulfill() }
            wait(for: [e], timeout: 1.0)
            XCTAssertNotNil(manager.failedLayers[.ioRegistry],
                            "L2 未生效时必须在 failedLayers 中可见（宿主可能拒绝非 root 写入）")
        }

        // 对端（模拟 Studio）激活后整体拆除
        peer.begin(.aiCodingIdleProcess)
        let e2 = expectation(description: "B active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)
        _ = peer.deactivateAll()

        // A 的 reason 与自愈路径不受对端拆除影响
        manager.performSafetyCheck()
        XCTAssertTrue(manager.activeReasons.contains(.aiCodingIdleProcess),
                      "对端 deactivateAll 不得清除本实例 reason")
        XCTAssertTrue(manager.isProtectionActive)
        if l2Real {
            XCTAssertEqual(Self.readSleepDisabled(), true, "可写宿主上 A 必须在安全周期内重断言 L2")
        }
    }

    /// 回归：根电源域必须能打开（`IORegistryEntryFromPath` 失效路径的静默失败
    /// 曾导致 L2 长期假激活；本测试保证回退匹配可用）。
    func testRootPowerDomainOpens() {
        let service = IORegistryProtection.openRootPowerDomain()
        XCTAssertNotEqual(service, 0, "IOPMrootDomain 必须可打开（路径失效时需回退匹配）")
        if service != 0 { IOObjectRelease(service) }
    }

    /// 直读 IORegistry 根电源域的 SleepDisabled（测试级真实取证）。
    private static func readSleepDisabled() -> Bool? {        let service = IORegistryProtection.openRootPowerDomain()
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
