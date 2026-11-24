import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class StudioLeverPresentationTests: XCTestCase {
    func testOnlyPhysicalCodexModeOffersManagement() {
        for mode in 0..<4 {
            let notice = StudioLeverPresentation.notice(position: 1, action: .automatic, mode: mode, codexManaged: false,
                                                        backgroundConnected: true, hooksInstalled: true)
            XCTAssertEqual(notice.offersCodexManagement, mode == 2)
            XCTAssertEqual(notice.title, "拨杆在下")
            XCTAssertEqual(notice.subtitle, "自动批准")
            if mode != 2 { XCTAssertFalse(notice.message.contains("Codex")) }
        }
    }

    func testMissingModeConnectionOrHooksNeverOffersManagement() {
        for mode in [nil, -1, 4] as [Int?] {
            XCTAssertFalse(StudioLeverPresentation.notice(position: 1, action: .automatic, mode: mode, codexManaged: false,
                backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
        }
        XCTAssertFalse(StudioLeverPresentation.notice(position: 1, action: .automatic, mode: 2, codexManaged: false,
            backgroundConnected: false, hooksInstalled: true).offersCodexManagement)
        XCTAssertFalse(StudioLeverPresentation.notice(position: 1, action: .automatic, mode: 2, codexManaged: false,
            backgroundConnected: true, hooksInstalled: false).offersCodexManagement)
    }

    func testManualAndExistingConsentDoNotOfferAgain() {
        XCTAssertFalse(StudioLeverPresentation.notice(position: 0, action: .manual, mode: 2, codexManaged: false,
            backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
        XCTAssertFalse(StudioLeverPresentation.notice(position: 1, action: .automatic, mode: 2, codexManaged: true,
            backgroundConnected: true, hooksInstalled: true).offersCodexManagement)
    }

    func testCustomNotificationsUsePhysicalPositionAndActualAction() {
        let shortcut = StudioLeverPresentation.notice(position: 0, action: .shortcut,
            bytes: Data([0x73, 2, 0xE3, 4]), mode: 2, codexManaged: false,
            backgroundConnected: true, hooksInstalled: true)
        XCTAssertEqual(shortcut.title, "拨杆在上")
        XCTAssertEqual(shortcut.subtitle, "快捷键")
        XCTAssertEqual(shortcut.message, "\(HIDUsage.name(for: 0xE3)) + \(HIDUsage.name(for: 4))")
        XCTAssertFalse(shortcut.offersCodexManagement)

        let macro = StudioLeverPresentation.notice(position: 1, action: .macro,
            bytes: Data([0x74, 6, 1, 4, 3, 17, 2, 4]), mode: 2, codexManaged: false,
            backgroundConnected: true, hooksInstalled: true)
        XCTAssertEqual(macro.title, "拨杆在下")
        XCTAssertEqual(macro.subtitle, "宏")
        XCTAssertEqual(macro.message, "按下 A → 延时 51 ms → 松开 A")
        XCTAssertFalse(macro.offersCodexManagement)
    }

    func testDisabledAndUnreadableActionsHaveDistinctDetails() {
        let disabled = StudioLeverPresentation.notice(position: 1, action: .disabled, mode: nil,
            codexManaged: false, backgroundConnected: false, hooksInstalled: false)
        XCTAssertEqual(disabled.subtitle, "不执行")
        XCTAssertEqual(disabled.message, "此档位没有绑定动作。")
        let unreadable = StudioLeverPresentation.notice(position: 0, action: .macro,
            bytes: Data([0x73, 1, 4]), mode: nil, codexManaged: false,
            backgroundConnected: false, hooksInstalled: false)
        XCTAssertEqual(unreadable.message, "未能读取此绑定的动作详情。")
    }

    func testPendingChangeDoesNotClaimSynchronization() {
        let pending = StudioLeverPresentation.notice(position: 1, action: .automatic, mode: 2, codexManaged: true,
            backgroundConnected: true, hooksInstalled: true)
        XCTAssertFalse(pending.message.contains("已同步"))
        let detached = StudioLeverPresentation.notice(position: 1, action: .automatic, mode: 2, codexManaged: true,
            backgroundConnected: false, hooksInstalled: true)
        XCTAssertNotEqual(pending.message, detached.message)
    }
}
