import XCTest
@testable import AhaKeyConfig

final class StudioLeverPresentationTests: XCTestCase {
    func testOnlyPhysicalCodexModeOffersManagement() {
        for mode in 0..<4 {
            let notice = StudioLeverPresentation.notice(mode: mode, automatic: true, codexManaged: false,
                                                        backgroundConnected: true, hooksInstalled: true)
            XCTAssertEqual(notice.offersCodexManagement, mode == 2)
            XCTAssertTrue(notice.title.hasPrefix(AhaKeyModeSlot(rawValue: mode)!.defaultName))
            if mode != 2 { XCTAssertFalse(notice.message.contains("Codex")) }
        }
    }

    func testMissingModeConnectionOrHooksNeverOffersManagement() {
        for mode in [nil, -1, 4] as [Int?] {
            XCTAssertFalse(StudioLeverPresentation.notice(mode: mode, automatic: true, codexManaged: false,
                backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
        }
        XCTAssertFalse(StudioLeverPresentation.notice(mode: 2, automatic: true, codexManaged: false,
            backgroundConnected: false, hooksInstalled: true).offersCodexManagement)
        XCTAssertFalse(StudioLeverPresentation.notice(mode: 2, automatic: true, codexManaged: false,
            backgroundConnected: true, hooksInstalled: false).offersCodexManagement)
    }

    func testManualAndExistingConsentDoNotOfferAgain() {
        XCTAssertFalse(StudioLeverPresentation.notice(mode: 2, automatic: false, codexManaged: false,
            backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
        XCTAssertFalse(StudioLeverPresentation.notice(mode: 2, automatic: true, codexManaged: true,
            backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
    }

    func testPendingChangeDoesNotClaimSynchronization() {
        let pending = StudioLeverPresentation.notice(mode: 2, automatic: true, codexManaged: true,
            backgroundConnected: true, hooksInstalled: true)
        XCTAssertFalse(pending.message.contains("已同步"))
        let detached = StudioLeverPresentation.notice(mode: 2, automatic: true, codexManaged: true,
            backgroundConnected: false, hooksInstalled: true)
        XCTAssertNotEqual(pending.message, detached.message)
    }
}
