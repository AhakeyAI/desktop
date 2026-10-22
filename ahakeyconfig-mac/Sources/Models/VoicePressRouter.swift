import CoreGraphics
import Foundation

struct VoiceTriggerBinding: Hashable {
    let keyCode: CGKeyCode
    let modifiers: Set<ShortcutModifier>


}

enum VoiceRouteAction: Hashable {
    case macOSDictation
    case functionRelay(appName: String)
    case doubaoPassThrough

    var title: String {
        switch self {
        case .macOSDictation: NSLocalizedString("macOS 原生语音", comment: "")
        case let .functionRelay(appName): appName
        case .doubaoPassThrough: NSLocalizedString("豆包输入法", comment: "")
        }
    }
    var isFunctionRelay: Bool {
        if case .functionRelay = self { return true }
        return false
    }
    var consumesPhysicalEvent: Bool { self != .doubaoPassThrough }
}

struct VoiceRoute: Hashable {
    let binding: VoiceTriggerBinding
    let action: VoiceRouteAction
    let mode: AhaKeyModeSlot
    let compatibilityLabel: String?
}

/// Called only on the relay's serial route queue. A keyUp belongs to the route
/// chosen at keyDown, even if mode, modifiers or route configuration changed.
struct VoicePressRouter {
    enum Decision: Equatable {
        case passThrough
        case suppressRepeat
        case route(VoiceRoute)
    }
    private enum Press {
        case passThrough
        case route(VoiceRoute)
    }
    private var pressed: [CGKeyCode: Press] = [:]

    mutating func keyDown(code: CGKeyCode, modifiers: Set<ShortcutModifier>, isRepeat: Bool,
                          mode: AhaKeyModeSlot?, routes: [VoiceRoute]) -> Decision {
        if let existing = pressed[code] {
            switch existing {
            case .passThrough: return .passThrough
            case .route(let route): return route.action.consumesPhysicalEvent ? .suppressRepeat : .passThrough
            }
        }
        // Never start recording midway through a press begun before monitoring.
        guard !isRepeat else { return .passThrough }
        guard let mode, let route = routes.first(where: {
            $0.mode == mode && $0.binding.keyCode == code && $0.binding.modifiers == modifiers
        }) else {
            pressed[code] = .passThrough
            return .passThrough
        }
        pressed[code] = .route(route)
        return .route(route)
    }

    mutating func keyUp(code: CGKeyCode) -> Decision {
        guard let existing = pressed.removeValue(forKey: code) else { return .passThrough }
        switch existing {
        case .passThrough: return .passThrough
        case .route(let route): return .route(route)
        }
    }

    mutating func reset() { pressed.removeAll() }
}
