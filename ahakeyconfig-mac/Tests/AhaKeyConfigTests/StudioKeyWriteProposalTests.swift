import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class StudioKeyWriteProposalTests: XCTestCase {
    func testProposalContainsOnlySelectedKeyAndNoLossyDescription() throws {
        var key = AhaKeyModeDraft.default(for: .mode2).key(for: .submit)
        key.shortcut = ShortcutBinding(keyCode: HIDUsage.backspace)
        key.description = "UI-SAVE"
        let target = try StudioKeyWriteProposal.make(key: key, mode: .mode2)
        XCTAssertEqual(target.mode, 2); XCTAssertEqual(target.keyIndex, 3)
        XCTAssertEqual(target.actionType, 0x73); XCTAssertEqual(target.action, Data([0x2A]))
        XCTAssertEqual(target.description, Data("UI-SAVE".utf8))
        key.description = "中文"
        XCTAssertThrowsError(try StudioKeyWriteProposal.make(key: key, mode: .mode2))
        key.description = String(repeating: "X", count: 21)
        XCTAssertThrowsError(try StudioKeyWriteProposal.make(key: key, mode: .mode2))
        key.description = "X  "
        XCTAssertEqual(try StudioKeyWriteProposal.make(key: key, mode: .mode2).description, Data([0x58]))
    }
    func testLongOrUnreleasedMacroIsNotTruncatedIntoProposal() {
        var key = AhaKeyModeDraft.default(for: .mode2).key(for: .submit)
        key.macro = [MacroStep(action: .downKey, param: HIDUsage.leftGUI)]
        XCTAssertThrowsError(try StudioKeyWriteProposal.make(key: key, mode: .mode2))
        key.macro = Array(repeating: MacroStep(action: .delay, param: 1), count: 26)
        key.description = "X"
        XCTAssertNoThrow(try StudioKeyWriteProposal.make(key: key, mode: .mode2))
        key.description = "XX"
        XCTAssertThrowsError(try StudioKeyWriteProposal.make(key: key, mode: .mode2))
    }
    func testReceiptOnlyClearsExactCurrentKeyAndPreservesOtherPendingWork() throws {
        let baseline = AhaKeyStudioDraft.default
        var pending = baseline
        var mode = pending.draft(for: .mode2)
        var key = mode.key(for: .submit); key.description = "UI-SAVE"; mode.updateKey(key)
        var peer = mode.key(for: .reject); peer.description = "Pending peer"; mode.updateKey(peer)
        pending.updateMode(mode)
        let actual = try StudioKeyWriteProposal.make(key: key, mode: .mode2)
        let reconciled = StudioKeyWriteProposal.reconcile(baseline: baseline, current: pending, actual: actual)
        XCTAssertEqual(reconciled.draft(for: .mode2).key(for: .submit), key)
        XCTAssertEqual(reconciled.draft(for: .mode2).key(for: .reject), baseline.draft(for: .mode2).key(for: .reject))
        XCTAssertNotEqual(reconciled.draft(for: .mode2).key(for: .reject), peer)
        XCTAssertEqual(reconciled.draft(for: .mode0), baseline.draft(for: .mode0))
        XCTAssertEqual(reconciled.draft(for: .mode2).oled, baseline.draft(for: .mode2).oled)
        key.description = "Different"
        XCTAssertEqual(StudioKeyWriteProposal.reconcile(baseline: baseline, current: pending, actual: try StudioKeyWriteProposal.make(key: key, mode: .mode2)), baseline)
    }
}
