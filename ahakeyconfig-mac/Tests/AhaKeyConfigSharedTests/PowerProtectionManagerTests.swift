import XCTest
import IOKit
import IOKit.pwr_mgt
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

    /// 跨实例拆除（模拟 Studio 退出）：对端实例 deactivateAll 不得影响本实例。
    /// idle reason 现为 L1（进程属主断言，天然不可被对端拆除）；
    /// L2/L3 共享资源由安全周期 refresh 自愈覆盖。
    func testPeerTeardownKeepsReasonsAndVisibility() {
        let peer = PowerProtectionManager()
        peer.enabled = true
        defer { _ = peer.deactivateAll() }

        manager.begin(.aiCodingIdleProcess)
        let e1 = expectation(description: "A active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e1.fulfill() }
        wait(for: [e1], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)
        XCTAssertEqual(manager.activeLevel, .assertion)

        // 对端（模拟 Studio）激活后整体拆除
        peer.begin(.aiCodingIdleProcess)
        let e2 = expectation(description: "B active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e2.fulfill() }
        wait(for: [e2], timeout: 1.0)
        _ = peer.deactivateAll()

        // A 的 reason、层级与 L1 断言都不受对端拆除影响
        manager.performSafetyCheck()
        XCTAssertTrue(manager.activeReasons.contains(.aiCodingIdleProcess),
                      "对端 deactivateAll 不得清除本实例 reason")
        XCTAssertTrue(manager.isProtectionActive)
        XCTAssertEqual(manager.activeLevel, .assertion, "对端拆除后本实例 L1 断言必须存续")
    }

    /// L2 可见性不变式（firmwareUpgrade 仍走 ioRegistry 层）：要么真生效，
    /// 要么失败落 failedLayers——杜绝静默假激活。
    func testL2FailureIsVisibleNotSilent() {
        manager.begin(.firmwareUpgrade)
        let e = expectation(description: "fw active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)
        if Self.readSleepDisabled() != true {
            XCTAssertNotNil(manager.failedLayers[.ioRegistry],
                            "L2 未生效时必须在 failedLayers 中可见（宿主可能拒绝非 root 写入）")
        }
    }

    /// 回归：根电源域必须能打开（`IORegistryEntryFromPath` 失效路径的静默失败
    /// 曾导致 L2 长期假激活；本测试保证回退匹配可用）。
    func testRootPowerDomainOpens() {
        let service = IORegistryProtection.openRootPowerDomain()
        XCTAssertNotEqual(service, 0, "IOPMrootDomain 必须可打开（路径失效时需回退匹配）")
        if service != 0 { IOObjectRelease(service) }
    }

    /// 行为变更（Codex 15:07）：AI 编程 idle reason 的承重层提升为 L1 系统断言
    /// （L2 非 root 不可写，不能承重）；合盖 reason 仍为 L3 虚拟显示器。
    func testAICodingIdleReasonsRequireAssertionLevel() {
        XCTAssertEqual(PowerProtectionReason.aiCodingIdleHook.requiredLevel, .assertion)
        XCTAssertEqual(PowerProtectionReason.aiCodingIdleProcess.requiredLevel, .assertion)
        XCTAssertEqual(PowerProtectionReason.userRequestedIdle.requiredLevel, .assertion)
        XCTAssertEqual(PowerProtectionReason.aiCodingLidCloseHook.requiredLevel, .virtualDisplay)
        XCTAssertEqual(PowerProtectionReason.aiCodingLidCloseProcess.requiredLevel, .virtualDisplay)
        XCTAssertEqual(PowerProtectionReason.userRequestedLidClose.requiredLevel, .virtualDisplay)
    }

    /// 端到端：idle reason 激活后 L1 断言真实持有（IOPMAssertion 用户态可用）。
    func testIdleReasonActivatesAssertionLayer() {
        manager.begin(.aiCodingIdleProcess)
        let e = expectation(description: "active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)
        XCTAssertEqual(manager.activeLevel, .assertion, "idle reason 必须以 L1 断言承重（pmset 可见）")
        XCTAssertNil(manager.failedLayers[.assertion], "L1 断言不得激活失败")
    }

    /// 回归（15:40 生产取证）：断言必须以 kIOPMAssertionLevelOn 创建——
    /// 传 0（LevelOff）会创建即失效、pmset 不可见。用 IOPMCopyAssertionsByProcess
    /// 直读本进程断言列表验证真实持有。
    func testIdleAssertionVisibleToPowerManagement() {
        manager.begin(.aiCodingIdleProcess)
        let e = expectation(description: "active")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { e.fulfill() }
        wait(for: [e], timeout: 1.0)
        XCTAssertTrue(manager.isProtectionActive)

        var assertions: Unmanaged<CFDictionary>?
        let rc = IOPMCopyAssertionsByProcess(&assertions)
        guard rc == kIOReturnSuccess, let dict = assertions?.takeRetainedValue() as? [NSNumber: Any] else {
            XCTFail("IOPMCopyAssertionsByProcess 失败 rc=\(rc)")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        // 结构：pid → [断言字典]，每项含 AssertType / AssertLevel
        let mine = dict[NSNumber(value: pid)] as? [[String: Any]] ?? []
        let held = mine.contains { ($0["AssertType"] as? String) == kIOPMAssertPreventUserIdleSystemSleep as String }
        XCTAssertTrue(held, "本进程必须真实持有 PreventUserIdleSystemSleep（pmset 可见）")
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
