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
}
