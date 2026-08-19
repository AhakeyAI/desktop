import XCTest
@testable import AhaKeyConfig

final class AhaKeyLightBarDefaultsTests: XCTestCase {
    func testLegacyAllApprovalDefaultsMigrateToStateSpecificEffects() {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode2)
        mode.lightBar.stateMappings = IDEState.allCases.map {
            AhaKeyLightStateDraft(state: $0, effect: .approvalWait)
        }
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft)
        let lightBar = migrated.draft(for: .mode2).lightBar

        XCTAssertEqual(lightBar.effect(for: .preToolUse), .singleMove)
        XCTAssertEqual(lightBar.effect(for: .taskCompleted), .successSweep)
        XCTAssertEqual(lightBar.effect(for: .stop), .middleLight)
        XCTAssertEqual(lightBar.effect(for: .permissionRequest), .approvalWait)
    }

    func testSyncBaselineCanRetainLegacyEffectsSoMigrationStaysDirty() {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode2)
        mode.lightBar.stateMappings = IDEState.allCases.map {
            AhaKeyLightStateDraft(state: $0, effect: .approvalWait)
        }
        draft.updateMode(mode)

        let baseline = AhaKeyStudioStore.migratedDraft(
            from: draft,
            migrateLegacyLightDefaults: false
        )

        XCTAssertTrue(baseline.draft(for: .mode2).lightBar.usesLegacyAllApprovalDefaults)
    }

    func testMigrationPreservesAnyUserCustomizedLighting() {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode2)
        mode.lightBar.stateMappings = IDEState.allCases.map {
            AhaKeyLightStateDraft(state: $0, effect: .approvalWait)
        }
        mode.lightBar.stateMappings[Int(IDEState.stop.rawValue)].effect = .warningBlink
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft)

        XCTAssertEqual(migrated.draft(for: .mode2).lightBar.stateMappings, mode.lightBar.stateMappings)
    }

    func testMigrationPreservesAllApprovalEffectsWhenBrightnessWasCustomized() {
        var draft = AhaKeyStudioDraft.default
        var mode = draft.draft(for: .mode2)
        mode.lightBar.stateMappings = IDEState.allCases.map {
            AhaKeyLightStateDraft(state: $0, effect: .approvalWait)
        }
        mode.lightBar.brightness = 60
        draft.updateMode(mode)

        let migrated = AhaKeyStudioStore.migratedDraft(from: draft)

        let migratedLightBar = migrated.draft(for: .mode2).lightBar
        XCTAssertTrue(migratedLightBar.stateMappings.allSatisfy { $0.effect == .approvalWait })
        XCTAssertEqual(migratedLightBar.brightness, 60)
    }
}
