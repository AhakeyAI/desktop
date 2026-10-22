import Foundation
import AhaKeyConfigShared

@MainActor
enum StudioInlineLightBatch {
    typealias Target = StudioLightDrafts.Target
    typealias Fact = StudioLightDrafts.Fact

    struct Reading {
        var values: [Target: Fact]
        var brightness: Fact
    }
    struct Conflict: Identifiable {
        let id = UUID()
        let plan: StudioLightWritePlan
        let changed: [Target]
        let reading: Reading
    }
    enum Result {
        case conflict(Conflict)
        case readOnly(Reading)
        case completed(Reading, writes: Int)
    }

    /// Preflight every item before any write; persistence is still per item,
    /// not an atomic firmware transaction. Callers retain attempted-item markers
    /// if any write, final verification, ownership check or cancellation fails.
    static func run(plan: StudioLightWritePlan, session: StudioInspectorSession,
                    read: (StudioLightWritePlan, StudioInspectorSession.Context) async throws -> Reading,
                    save: (WS3DisplaySetting, UInt8, UInt64) async throws -> Void,
                    verify: (StudioLightWritePlan.Item, StudioInspectorSession.Context) async throws -> Fact,
                    writeStarted: (Target) -> Void) async throws -> Result {
        guard plan.isValid, !plan.items.isEmpty, let deviceID = plan.deviceID else {
            throw ConfirmedWS3DisplaySetting.Failure.invalidValue
        }
        return try await session.withConnection(expectedDeviceID: deviceID) { context in
            var actual = try await read(plan, context)
            try Task.checkCancellation()
            guard Set(actual.values.keys) == Set(plan.items.map(\.target)),
                  actual.values.values.allSatisfy({ $0.deviceID == context.deviceID }),
                  actual.brightness.deviceID == context.deviceID,
                  Target.brightness.accepts(actual.brightness.value) else {
                throw ConfirmedWS3DisplaySetting.Failure.mismatch
            }
            guard plan.items.allSatisfy({ $0.target.accepts(actual.values[$0.target]!.value) }) else { return .readOnly(actual) }
            let changed = plan.items.filter { item in
                let fact = actual.values[item.target]!
                return fact != item.baseline && !(item.requiresPersistence && fact.value == item.desired)
            }.map(\.target)
            if !changed.isEmpty {
                let revised = StudioLightWritePlan(mode: plan.mode, items: plan.items.map { item in
                    .init(target: item.target, baseline: actual.values[item.target]!, desired: item.desired,
                          requiresPersistence: item.requiresPersistence)
                })
                return .conflict(.init(plan: revised, changed: changed, reading: actual))
            }
            var writes = 0
            for item in plan.items {
                try Task.checkCancellation()
                let baseline = actual.values[item.target]!
                if item.requiresPersistence || baseline.value != item.desired {
                    writeStarted(item.target)
                    try await save(item.target.setting(item.desired), baseline.value, context.generation)
                    writes += 1
                }
            }
            // Check the entire submitted set again after the last write.
            for item in plan.items {
                try Task.checkCancellation()
                let fact = try await verify(item, context)
                guard fact.deviceID == context.deviceID, fact.value == item.desired else {
                    throw ConfirmedWS3DisplaySetting.Failure.mismatch
                }
                actual.values[item.target] = fact
                if item.target == .brightness { actual.brightness = fact }
            }
            return .completed(actual, writes: writes)
        }
    }
}
