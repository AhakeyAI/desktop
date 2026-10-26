import XCTest
@testable import AhaKeyConfig

final class StudioLegacyComponentPlanTests: XCTestCase {
    func testOrdinaryKeyPlanNeverContainsOtherKeysLightsOrArtwork() throws {
        for mode in AhaKeyModeSlot.allCases {
            let draft = AhaKeyModeDraft.default(for: mode)
            for part in [AhaKeyStudioPart.key2, .key3, .key4] {
                let plan = try StudioLegacyComponentPlan(mode: mode, part: part, submitted: draft)
                XCTAssertFalse(plan.uploadsArtwork)
                XCTAssertEqual(plan.commands.count, 4)
                for command in plan.commands.dropLast() {
                    let bytes = [UInt8](command.data)
                    XCTAssertEqual(bytes[2], 0x73)
                    XCTAssertEqual(bytes[4], UInt8(mode.rawValue))
                    XCTAssertEqual(bytes[5], UInt8(part.keyRole!.rawValue))
                }
                XCTAssertEqual(plan.commands.last?.data, AhaKeyCommand.saveConfig())
            }
        }
    }
    func testBaselineAcknowledgesOnlySelectedComponent() throws {
        let baseline = AhaKeyStudioDraft.default
        var submitted = baseline.draft(for: .mode2)
        var key = submitted.key(for: .approve)
        key.description = "Changed"
        submitted.updateKey(key)
        submitted.lightBar.brightness = 76
        let plan = try StudioLegacyComponentPlan(mode: .mode2, part: .key2, submitted: submitted)
        let updated = plan.updatingBaseline(baseline)
        XCTAssertEqual(updated.draft(for: .mode2).key(for: .approve).description, "Changed")
        XCTAssertEqual(updated.draft(for: .mode2).lightBar, baseline.draft(for: .mode2).lightBar)
        XCTAssertEqual(updated.draft(for: .mode0), baseline.draft(for: .mode0))
        XCTAssertEqual(updated.draft(for: .mode2).key(for: .voice), baseline.draft(for: .mode2).key(for: .voice))
    }
    func testLightPlanContainsOnlyMappingBrightnessAndSave() throws {
        let draft = AhaKeyModeDraft.default(for: .mode1)
        let plan = try StudioLegacyComponentPlan(mode: .mode1, part: .lightBar, submitted: draft)
        XCTAssertEqual(plan.commands.count, 3)
        XCTAssertFalse(plan.uploadsArtwork)
        XCTAssertFalse(plan.commands.contains { $0.data[2] == 0x73 })
    }
    func testUnsupportedComponentsAndMissingArtworkCannotFallBackToFullSave() {
        var draft = AhaKeyModeDraft.default(for: .mode0)
        draft.oled.localAssetPath = nil
        for part in [AhaKeyStudioPart.toggleSwitch, .modeButton, .oledDisplay] {
            XCTAssertThrowsError(try StudioLegacyComponentPlan(mode: .mode0, part: part, submitted: draft))
        }
    }
}
