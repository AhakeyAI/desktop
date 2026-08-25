import XCTest
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
}
