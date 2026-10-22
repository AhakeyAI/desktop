import Foundation
import AhaKeyConfigShared

/// Reported values survive a lease ending; they never authorize a later write.
struct StudioLightDrafts: Codable {
    enum Target: Hashable, Codable {
        case brightness
        case effect(mode: UInt8, state: UInt8)

        func setting(_ value: UInt8) -> WS3DisplaySetting {
            switch self {
            case .brightness: return .brightness(value)
            case .effect(let mode, let state): return .singleLight(mode: mode, state: state, effect: value)
            }
        }

        func accepts(_ value: UInt8) -> Bool { setting(value).saveRequest != nil }
    }

    struct Fact: Equatable, Codable {
        let deviceID: String
        let value: UInt8
    }

    private(set) var facts: [Target: Fact] = [:]
    private(set) var drafts: [Target: UInt8] = [:]
    private(set) var unconfirmed: Set<Target> = []

    var dirtyTargets: Set<Target> {
        Set(drafts.compactMap { target, value in facts[target]?.value != value ? target : nil })
    }

    func isDirty(mode: UInt8) -> Bool {
        dirtyTargets.contains { target in
            switch target {
            case .brightness: return true
            case .effect(let itemMode, _): return itemMode == mode
            }
        }
    }

    mutating func observe(_ target: Target, fact: Fact) {
        let wasClean = drafts[target] == nil || drafts[target] == facts[target]?.value
        facts[target] = fact
        if wasClean { drafts[target] = fact.value }
    }

    mutating func edit(_ target: Target, value: UInt8) {
        guard target.accepts(value), let fact = facts[target], target.accepts(fact.value) else { return }
        drafts[target] = value
    }

    mutating func adopt(_ target: Target) {
        drafts[target] = facts[target]?.value
    }

    mutating func markUnconfirmed(_ target: Target) { unconfirmed.insert(target) }

    mutating func confirm(_ target: Target, fact: Fact) {
        facts[target] = fact
        drafts[target] = fact.value
        unconfirmed.remove(target)
    }
}
