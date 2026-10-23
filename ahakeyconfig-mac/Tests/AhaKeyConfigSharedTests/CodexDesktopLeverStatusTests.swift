import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexDesktopLeverStatusTests: XCTestCase {
    func testExplicitPauseIsUnmanagedWhileUnverifiedAutomaticIsNotSynchronized() {
        XCTAssertEqual(CodexDesktopLeverStatus.resolvePhase(working: false, capacityLimited: false,
            managementEnabled: true, controlEnabled: false, hint: .verifiedAutomatic, outcomes: [.unmanaged]), .notManaged)
        XCTAssertEqual(CodexDesktopLeverStatus.resolvePhase(working: false, capacityLimited: false,
            managementEnabled: true, controlEnabled: true, hint: .verifiedAutomatic, outcomes: [.unmanaged]), .notSynchronized)
    }
    func testPendingRecoveryFailureCannotBeHiddenByThePausedLabel() {
        XCTAssertEqual(CodexDesktopLeverStatus.resolvePhase(working: false, capacityLimited: false,
            managementEnabled: true, controlEnabled: false, hint: .unmanaged, outcomes: [.notSynchronized]), .notSynchronized)
        XCTAssertEqual(CodexDesktopLeverStatus.resolvePhase(working: true, capacityLimited: false,
            managementEnabled: true, controlEnabled: true, hint: .manual, outcomes: [.nextTurn]), .working)
    }
    func testOnlyOriginalSessionNextTurnSummariesAreAccepted() throws {
        let good: [String: Any] = ["phase": "synchronized", "pendingRecovery": 0, "managedSessions": 2, "appliesTo": "nextTurn"]
        XCTAssertEqual(CodexDesktopLeverStatus.decode(try JSONSerialization.data(withJSONObject: good))?.phase, .synchronized)
        for replacement: [String: Any] in [["phase": "futureUnsupported"], ["pendingRecovery": -1], ["managedSessions": 33], ["appliesTo": "currentTurn"]] {
            let bad = good.merging(replacement, uniquingKeysWith: { _, new in new })
            XCTAssertNil(CodexDesktopLeverStatus.decode(try JSONSerialization.data(withJSONObject: bad)))
        }
        XCTAssertNil(CodexDesktopLeverStatus.decode(Data("{\"error\":\"unknown cmd\"}".utf8)))
    }
}
