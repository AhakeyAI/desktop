import XCTest
@testable import AhaKeyConfig

final class StudioSyncedBaselineTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "StudioSyncedBaselineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUnsyncedEditSurvivesRelaunchAsDifferenceFromBaseline() {
        let synced = AhaKeyStudioDraft.default
        AhaKeyStudioStore.saveSynced(synced, to: defaults)

        var edited = synced
        var mode3 = edited.draft(for: .mode3)
        var key = mode3.key(for: .voice)
        key.description = "AHK-021 temp"
        mode3.updateKey(key)
        edited.updateMode(mode3)
        AhaKeyStudioStore.save(edited, to: defaults)

        let reloadedDraft = AhaKeyStudioStore.load(from: defaults)
        let reloadedBaseline = AhaKeyStudioStore.loadSynced(from: defaults)
        XCTAssertEqual(reloadedDraft?.draft(for: .mode3).key(for: .voice).description, "AHK-021 temp")
        XCTAssertNotEqual(reloadedDraft, reloadedBaseline)
    }

    func testMissingBaselineReturnsNilForLegacyUpgrade() {
        AhaKeyStudioStore.save(.default, to: defaults)
        XCTAssertNil(AhaKeyStudioStore.loadSynced(from: defaults))
    }
}
