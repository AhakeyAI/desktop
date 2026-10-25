import XCTest
@testable import AhaKeyConfig

final class StudioKeyBaselinesTests: XCTestCase {
    func testUpgradeWithoutFactsPreservesEveryDraft() {
        let record = StudioKeyBaselines()
        for mode in AhaKeyModeSlot.allCases {
            for role in AhaKeyKeyRole.allCases {
                let key = AhaKeyStudioDraft.default.draft(for: mode).key(for: role)
                XCTAssertTrue(record.preservesDraft(key, deviceID: "device", mode: mode))
            }
        }
    }
    func testCurrentComponentBaselineSurvivesRelaunchWithoutConfirmingOtherDrafts() throws {
        let suite = "StudioKeyBaselinesTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mode = AhaKeyModeSlot.mode3
        var first = AhaKeyStudioDraft.default.draft(for: mode).key(for: .voice)
        first.description = "confirmed"
        let other = AhaKeyStudioDraft.default.draft(for: mode).key(for: .submit)
        var record = StudioKeyBaselines()
        record.observe(first, deviceID: "device", mode: mode)
        record.save(to: defaults)
        let reloaded = StudioKeyBaselines.load(from: defaults)
        XCTAssertFalse(reloaded.preservesDraft(first, deviceID: "device", mode: mode))
        XCTAssertTrue(reloaded.preservesDraft(other, deviceID: "device", mode: mode))
        first.description = "new local edit"
        XCTAssertTrue(reloaded.preservesDraft(first, deviceID: "device", mode: mode))
    }
    func testFactsFromAnotherDeviceOrModeCannotReplaceDraft() {
        let mode = AhaKeyModeSlot.mode3
        let key = AhaKeyStudioDraft.default.draft(for: mode).key(for: .voice)
        var record = StudioKeyBaselines()
        record.observe(key, deviceID: "first", mode: mode)
        XCTAssertTrue(record.preservesDraft(key, deviceID: "second", mode: mode))
        XCTAssertTrue(record.preservesDraft(key, deviceID: "first", mode: .mode0))
    }
}
