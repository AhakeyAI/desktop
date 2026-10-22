import XCTest
@testable import AhaKeyConfig

final class StudioModeSelectionTests: XCTestCase {
    func testLightingEditorKeepsChosenModeAcrossHandoffAndReconnect() {
        // Captured HIL pattern: browsing Kimi, App gives BLE back to Agent,
        // live mode disappears then reports the unchanged physical Codex mode.
        var selected = AhaKeyModeSlot.mode3
        for report: Int? in [nil, 2] {
            selected = StudioModeSelection.followingDevice(current: selected, reportedMode: report,
                                                           isEditing: true, hasFixedKeyTarget: false)
        }
        XCTAssertEqual(selected, .mode3)
    }

    func testAllComponentEditorsRetainTheirModeWhenPhysicalModeChanges() {
        for selected in AhaKeyModeSlot.allCases {
            for reported in AhaKeyModeSlot.allCases {
                XCTAssertEqual(StudioModeSelection.followingDevice(current: selected, reportedMode: reported.rawValue,
                               isEditing: true, hasFixedKeyTarget: false), selected)
            }
        }
    }

    func testReadOnlyViewStillFollowsValidDeviceModes() {
        for reported in AhaKeyModeSlot.allCases {
            XCTAssertEqual(StudioModeSelection.followingDevice(current: .mode0, reportedMode: reported.rawValue,
                           isEditing: false, hasFixedKeyTarget: false), reported)
        }
        for report: Int? in [nil, -1, 4] {
            XCTAssertEqual(StudioModeSelection.followingDevice(current: .mode3, reportedMode: report,
                           isEditing: false, hasFixedKeyTarget: false), .mode3)
        }
    }

    func testPendingFixedKeyTargetStaysPinnedAfterEditorCloses() {
        XCTAssertEqual(StudioModeSelection.followingDevice(current: .mode1, reportedMode: 2,
                       isEditing: false, hasFixedKeyTarget: true), .mode1)
    }
}
