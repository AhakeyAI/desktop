import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

final class StudioInlineKeyTests: XCTestCase {
    private func key(_ action: [UInt8], type: UInt8 = 0x73, index: UInt8 = 1) -> OrdinaryKeyReadback {
        .init(mode: 2, keyIndex: index, actionType: type, action: Data(action), description: Data("Accept".utf8))
    }

    func testImportsOnlyLosslesslyRepresentableShortcuts() throws {
        let original = AhaKeyModeDraft.default(for: .mode2).key(for: .approve)
        let actual = key([HIDUsage.leftControl, HIDUsage.leftGUI, HIDUsage.enter])
        let imported = try XCTUnwrap(StudioKeyWriteProposal.draft(from: actual, preserving: original))
        XCTAssertEqual(try StudioKeyWriteProposal.make(key: imported, mode: .mode2), actual)
        for unknown in [key([HIDUsage.enter, HIDUsage.downArrow]), key([HIDUsage.enter, HIDUsage.leftGUI]), key([], type: 0), key([0x28], type: 0x99)] {
            XCTAssertNil(StudioKeyWriteProposal.draft(from: unknown, preserving: original))
        }
    }

    func testMacroReadbackPreservesEveryStepWithoutChangingOtherKeys() throws {
        let original = AhaKeyModeDraft.default(for: .mode2).key(for: .approve)
        let actual = key([MacroAction.downKey.rawValue, HIDUsage.enter, MacroAction.upKey.rawValue, HIDUsage.enter], type: 0x74)
        let imported = try XCTUnwrap(StudioKeyWriteProposal.draft(from: actual, preserving: original))
        XCTAssertEqual(imported.macro.count, 2)
        XCTAssertEqual(try StudioKeyWriteProposal.make(key: imported, mode: .mode2), actual)
        XCTAssertNil(StudioKeyWriteProposal.draft(from: key([255, 1], type: 0x74), preserving: original))
        XCTAssertNil(StudioKeyWriteProposal.draft(from: key([1], type: 0x74), preserving: original))
        XCTAssertNil(StudioKeyWriteProposal.draft(from: key([HIDUsage.enter], index: 2), preserving: original))
    }

    @MainActor
    private func session(release: @escaping () -> Void) -> StudioInspectorSession {
        StudioInspectorSession(access: .init(begin: { 1 }, isCurrent: { $0 == 1 }, isReady: { true }, generation: { 7 }, deviceID: { "A" }, release: { _ in release() }, pause: {}))
    }

    @MainActor
    func testConflictNeverWritesAndConfirmationRechecksAgain() async throws {
        let before = key([HIDUsage.enter]), changed = key([HIDUsage.downArrow]), desired = key([HIDUsage.escape])
        var releases = 0, writes = 0, reads = 0
        let host = session { releases += 1 }
        let first = try await StudioInlineKeySave.run(session: host, baseline: .init(deviceID: "A", value: before), desired: desired,
            read: { mode, index in XCTAssertEqual(mode, 2); XCTAssertEqual(index, 1); reads += 1; return changed },
            save: { _, _, _ in XCTFail("No write on conflict"); return desired }, writeStarted: { writes += 1 })
        guard case .conflict(let conflict) = first else { return XCTFail("Expected conflict") }
        XCTAssertEqual(conflict.actual, changed); XCTAssertEqual(conflict.desired, desired)
        // Device changes again after the user reviews the first conflict.
        let second = try await StudioInlineKeySave.run(session: host, baseline: .init(deviceID: "A", value: conflict.actual), desired: conflict.desired,
            read: { _, _ in reads += 1; return before },
            save: { _, _, _ in XCTFail("Confirmation cannot bypass another change"); return desired }, writeStarted: { writes += 1 })
        guard case .conflict = second else { return XCTFail("Expected second conflict") }
        XCTAssertEqual(reads, 2); XCTAssertEqual(writes, 0); XCTAssertEqual(releases, 2)
    }

    @MainActor
    func testUnchangedReadbackIsNotReportedAsSaved() async throws {
        let value = key([HIDUsage.enter]); var releases = 0
        let result = try await StudioInlineKeySave.run(session: session { releases += 1 }, baseline: .init(deviceID: "A", value: value), desired: value,
            read: { _, _ in value }, save: { _, _, _ in XCTFail("No change"); return value }, writeStarted: { XCTFail("No change") })
        guard case .unchanged = result else { return XCTFail("Must not erase unconfirmed-save history") }
        XCTAssertEqual(releases, 1)
    }

    @MainActor
    func testSaveUsesFreshBaselineAndGenerationThenReleases() async throws {
        let before = key([HIDUsage.enter]), desired = key([HIDUsage.escape])
        var events: [String] = []
        let host = session { events.append("release") }
        let result = try await StudioInlineKeySave.run(session: host, baseline: .init(deviceID: "A", value: before), desired: desired,
            read: { _, _ in events.append("read"); return before },
            save: { baseline, target, generation in
                XCTAssertEqual(baseline, before); XCTAssertEqual(target, desired); XCTAssertEqual(generation, 7)
                events.append("confirmed-transaction"); return desired
            }, writeStarted: { events.append("write-started") })
        guard case .saved(let fact) = result else { return XCTFail("Expected confirmed save") }
        XCTAssertEqual(fact.deviceID, "A"); XCTAssertEqual(fact.value, desired)
        XCTAssertEqual(events, ["read", "write-started", "confirmed-transaction", "release"])
    }
}
