import Foundation
import XCTest
@testable import AhaKeyConfigShared

final class CodexDesktopLeverStatusTests: XCTestCase {
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
