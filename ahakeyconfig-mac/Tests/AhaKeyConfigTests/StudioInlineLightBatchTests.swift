import XCTest
import AhaKeyConfigShared
@testable import AhaKeyConfig

@MainActor
final class StudioInlineLightBatchTests: XCTestCase {
    private typealias Target = StudioLightDrafts.Target
    private typealias Fact = StudioLightDrafts.Fact
    private let first = Target.effect(mode: 2, state: 0)
    private let second = Target.effect(mode: 2, state: 1)
    private func fact(_ value: UInt8) -> Fact { .init(deviceID: "A", value: value) }
    private func plan(uncertain: Bool = false) -> StudioLightWritePlan {
        .init(mode: 2, items: [
            .init(target: first, baseline: fact(10), desired: 5, requiresPersistence: uncertain),
            .init(target: second, baseline: fact(9), desired: 3, requiresPersistence: false)])
    }
    private func host(generation: @escaping () -> UInt64 = { 1 }, release: @escaping () -> Void = {}) -> StudioInspectorSession {
        .init(access: .init(begin: { 1 }, isCurrent: { $0 == 1 }, isReady: { true }, generation: generation,
                            deviceID: { "A" }, release: { _ in release() }, pause: {}))
    }
    private func reading(_ plan: StudioLightWritePlan) -> StudioInlineLightBatch.Reading {
        .init(values: Dictionary(uniqueKeysWithValues: plan.items.map { ($0.target, $0.baseline) }), brightness: fact(35))
    }
    func testPlanScopesCurrentModeAndOrdersGlobalBrightnessLast() throws {
        var values = StudioLightDrafts()
        for target in [first, second, .effect(mode: 1, state: 0), .brightness] {
            values.observe(target, fact: fact(target == .brightness ? 35 : 10))
            values.edit(target, value: target == .brightness ? 40 : 5)
        }
        let result = try StudioLightWritePlan.make(mode: 2, values: values)
        XCTAssertEqual(result.items.map(\.target), [first, second, .brightness])
        for item in result.items { values.confirm(item.target, fact: fact(item.desired)) }
        XCTAssertEqual(values.dirtyTargets, [.effect(mode: 1, state: 0)])
    }
    func testPreflightThenSerialWritesThenVerifyAllWithOneLease() async throws {
        var events: [String] = [], releases = 0
        let plan = plan()
        let result = try await StudioInlineLightBatch.run(plan: plan, session: host(release: { releases += 1 }), read: { _, _ in
            events.append("readAll"); return self.reading(plan)
        }, save: { setting, _, generation in
            XCTAssertEqual(generation, 1)
            events.append(setting == self.first.setting(5) ? "write1" : "write2")
        }, verify: { item, _ in events.append("verify"); return self.fact(item.desired) }, writeStarted: { _ in })
        guard case .completed(_, let count) = result else { return XCTFail("Expected completion") }
        XCTAssertEqual(count, 2); XCTAssertEqual(events, ["readAll", "write1", "write2", "verify", "verify"])
        XCTAssertEqual(releases, 1)
    }
    func testConflictPreventsEveryWriteAndConfirmationRechecks() async throws {
        var plan = plan()
        for actual: UInt8 in [7, 8] {
            let result = try await StudioInlineLightBatch.run(plan: plan, session: host(), read: { _, _ in
                var read = self.reading(plan); read.values[self.second] = self.fact(actual); return read
            }, save: { _, _, _ in XCTFail("Conflict must precede all writes") }, verify: { _, _ in XCTFail(); return self.fact(0) }, writeStarted: { _ in XCTFail() })
            guard case .conflict(let conflict) = result else { return XCTFail("Expected conflict") }
            XCTAssertEqual(conflict.changed, [second]); XCTAssertEqual(conflict.plan.items[1].baseline.value, actual)
            plan = conflict.plan
        }
    }
    func testUnknownReadbackIsReadOnlyBeforeWrites() async throws {
        let plan = plan()
        let result = try await StudioInlineLightBatch.run(plan: plan, session: host(), read: { _, _ in
            var read = self.reading(plan); read.values[self.second] = self.fact(255); return read
        }, save: { _, _, _ in XCTFail() }, verify: { _, _ in XCTFail(); return self.fact(0) }, writeStarted: { _ in XCTFail() })
        guard case .readOnly = result else { return XCTFail("Expected read only") }
    }
    func testPartialFailureRetainsAllAttemptedMarkersAndReleases() async {
        struct Failed: Error {}
        var values = StudioLightDrafts(), releases = 0, writes = 0
        do {
            let plan = plan()
            _ = try await StudioInlineLightBatch.run(plan: plan, session: host(release: { releases += 1 }), read: { _, _ in self.reading(plan) }, save: { _, _, _ in
                writes += 1; if writes == 2 { throw Failed() }
            }, verify: { _, _ in XCTFail(); return self.fact(0) }, writeStarted: { values.markUnconfirmed($0) })
            XCTFail("Cannot report completion")
        } catch { XCTAssertTrue(error is Failed) }
        XCTAssertEqual(values.unconfirmed, [first, second]); XCTAssertEqual(releases, 1)
    }
    func testUnconfirmedRAMMatchStillPersistsWithoutFalseConflict() async throws {
        let plan = plan(uncertain: true); var writes = 0
        let result = try await StudioInlineLightBatch.run(plan: plan, session: host(), read: { _, _ in
            var read = self.reading(plan); read.values[self.first] = self.fact(5); return read
        }, save: { _, _, _ in writes += 1 }, verify: { item, _ in self.fact(item.desired) }, writeStarted: { _ in })
        guard case .completed = result else { return XCTFail("Expected completed retry") }
        XCTAssertEqual(writes, 2)
    }
    func testFinalVerificationMismatchOrGenerationChangeRejectsSuccess() async {
        for changeGeneration in [false, true] {
            var generation: UInt64 = 1, releases = 0
            let plan = plan()
            do {
                _ = try await StudioInlineLightBatch.run(plan: plan, session: host(generation: { generation }, release: { releases += 1 }), read: { _, _ in self.reading(plan) }, save: { _, _, _ in }, verify: { item, _ in
                    if changeGeneration { generation = 2 }
                    return self.fact(changeGeneration ? item.desired : 0)
                }, writeStarted: { _ in })
                XCTFail("Cannot report completion")
            } catch { }
            XCTAssertEqual(releases, 1)
        }
    }
    func testAlreadyAppliedValueReturnsZeroWritesWithoutClaimingPersistence() async throws {
        let plan = StudioLightWritePlan(mode: 2, items: [.init(target: first, baseline: fact(5), desired: 5, requiresPersistence: false)])
        let result = try await StudioInlineLightBatch.run(plan: plan, session: host(), read: { _, _ in self.reading(plan) }, save: { _, _, _ in XCTFail("No write needed") }, verify: { item, _ in self.fact(item.desired) }, writeStarted: { _ in XCTFail() })
        guard case .completed(_, let writes) = result else { return XCTFail("Expected read-only match") }
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(KeyboardWriteOutcome(succeeded: true, message: "Verified", wrote: false).wrote)
    }

    func testCancellationAfterFirstWriteKeepsMarkerAndReturnsLease() async {
        var attempted: [Target] = [], releases = 0
        let plan = plan()
        let task = Task { @MainActor in
            try await StudioInlineLightBatch.run(plan: plan, session: host(release: { releases += 1 }), read: { _, _ in self.reading(plan) }, save: { _, _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }, verify: { _, _ in XCTFail(); return self.fact(0) }, writeStarted: { attempted.append($0) })
        }
        do { _ = try await task.value; XCTFail("Cancelled batch cannot complete") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(attempted, [first]); XCTAssertEqual(releases, 1)
    }

    func testInvalidScopeOrForeignDevicePreventsIO() async {
        for item in [StudioLightWritePlan.Item(target: .effect(mode: 1, state: 0), baseline: fact(10), desired: 5, requiresPersistence: false),
                     .init(target: first, baseline: .init(deviceID: "B", value: 10), desired: 5, requiresPersistence: false)] {
            do {
                _ = try await StudioInlineLightBatch.run(plan: .init(mode: 2, items: [item]), session: host(), read: { _, _ in XCTFail(); return .init(values: [:], brightness: self.fact(35)) }, save: { _, _, _ in XCTFail() }, verify: { _, _ in XCTFail(); return self.fact(0) }, writeStarted: { _ in XCTFail() })
                XCTFail("Invalid scope/device")
            } catch { }
        }
    }
}
