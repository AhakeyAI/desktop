import Foundation
import AhaKeyConfigShared

struct StudioLightWritePlan: Equatable {
    struct Item: Equatable {
        let target: StudioLightDrafts.Target
        let baseline: StudioLightDrafts.Fact
        let desired: UInt8
        let requiresPersistence: Bool
    }

    let mode: UInt8
    let items: [Item]
    var deviceID: String? { items.first?.baseline.deviceID }

    static func make(mode: UInt8, values: StudioLightDrafts) throws -> Self {
        guard mode < 4 else { throw ConfirmedWS3DisplaySetting.Failure.invalidValue }
        let pending = values.dirtyTargets.union(values.unconfirmed).filter { target in
            switch target {
            case .brightness: return true
            case .effect(let itemMode, _): return itemMode == mode
            }
        }.sorted { order($0) < order($1) }
        let items = try pending.map { target -> Item in
            guard let baseline = values.facts[target], let desired = values.drafts[target],
                  target.accepts(baseline.value), target.accepts(desired) else {
                throw ConfirmedWS3DisplaySetting.Failure.invalidValue
            }
            return Item(target: target, baseline: baseline, desired: desired,
                        requiresPersistence: values.unconfirmed.contains(target))
        }
        let plan = Self(mode: mode, items: items)
        guard plan.isValid else { throw ConfirmedWS3DisplaySetting.Failure.invalidValue }
        return plan
    }

    var isValid: Bool {
        mode < 4 && Set(items.map(\.target)).count == items.count &&
        items.allSatisfy { item in
            let inScope: Bool
            switch item.target {
            case .brightness: inScope = true
            case .effect(let itemMode, _): inScope = itemMode == mode
            }
            return inScope && !item.baseline.deviceID.isEmpty && item.baseline.deviceID == deviceID &&
                item.target.accepts(item.baseline.value) && item.target.accepts(item.desired)
        }
    }

    private static func order(_ target: StudioLightDrafts.Target) -> Int {
        switch target {
        case .brightness: return 100
        case .effect(_, let state): return Int(state)
        }
    }
}
