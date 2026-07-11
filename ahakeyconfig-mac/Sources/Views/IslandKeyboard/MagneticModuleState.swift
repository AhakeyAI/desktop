import Foundation

enum MagneticModuleType: Int, CaseIterable, Codable, Identifiable {
    case none = 0
    case toggle
    case joystick
    case knob
    case scrollWheel
    case dpad

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "无模块"
        case .toggle: return "拨杆"
        case .joystick: return "摇杆"
        case .knob: return "旋钮"
        case .scrollWheel: return "滚轮"
        case .dpad: return "十字键"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "square.dashed"
        case .toggle: return "switch.2"
        case .joystick: return "plus.circle"
        case .knob:
            if #available(macOS 13, *) { return "dial.medium" }
            return "circle.circle"
        case .scrollWheel:
            if #available(macOS 13, *) { return "scroll" }
            return "arrow.up.arrow.down"
        case .dpad:
            if #available(macOS 14, *) { return "dpad" }
            return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "空槽占位"
        case .toggle: return "免费 · 自动/手动批准"
        case .joystick: return "二维方向输入"
        case .knob: return "旋转增量"
        case .scrollWheel: return "滚轮滚动"
        case .dpad: return "五向导航"
        }
    }

    /// 出厂自带，无需购买。
    var isIncludedByDefault: Bool { self == .toggle }

    /// 磁吸扩展套件，需单独购买解锁。
    var requiresPurchase: Bool {
        switch self {
        case .joystick, .knob, .scrollWheel, .dpad: return true
        default: return false
        }
    }

    static var attachableCases: [MagneticModuleType] {
        allCases.filter { $0 != .none }
    }

    static var purchasableCases: [MagneticModuleType] {
        attachableCases.filter(\.requiresPurchase)
    }
}

enum DPadDirection: String, CaseIterable, Codable, Identifiable {
    case up, down, left, right, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .center: return "●"
        }
    }
}

struct MagneticModuleState: Equatable, Codable {
    var attachedType: MagneticModuleType
    var togglePosition: Int
    var joystickX: Int
    var joystickY: Int
    var knobDelta: Int
    var scrollDelta: Int
    var dpadDirection: DPadDirection?

    static let empty = MagneticModuleState(
        attachedType: .none,
        togglePosition: 1,
        joystickX: 0,
        joystickY: 0,
        knobDelta: 0,
        scrollDelta: 0,
        dpadDirection: nil
    )

    /// 出厂默认：磁吸底座为空槽，用户在设置中选择模块后吸附。
    static let `default` = empty

    var isConnected: Bool { attachedType != .none }

    var toggleTitle: String {
        switch togglePosition {
        case 0: return "自动批准"
        case 2: return "中间档"
        default: return "手动批准"
        }
    }
}

enum MagneticModuleStateStore {
    static func load() -> MagneticModuleState {
        guard let data = UserDefaults.standard.data(forKey: DeviceCapabilityStorage.magneticModuleKey),
              var state = try? JSONDecoder().decode(MagneticModuleState.self, from: data) else {
            return .default
        }
        state = sanitized(state)
        // 打开页面时始终从空槽开始；吸附类型仅在本会话内有效。
        state.attachedType = .none
        return state
    }

    static func save(_ state: MagneticModuleState) {
        var clean = sanitized(state)
        // 不持久化吸附模块，避免下次打开仍显示已安装控件。
        clean.attachedType = .none
        guard let data = try? JSONEncoder().encode(clean) else { return }
        UserDefaults.standard.set(data, forKey: DeviceCapabilityStorage.magneticModuleKey)
    }

    /// 若吸附了未解锁的付费模块，回退到空槽。
    static func sanitized(_ state: MagneticModuleState) -> MagneticModuleState {
        var next = state
        if next.attachedType.requiresPurchase, !MagneticModuleUnlockStore.isUnlocked(next.attachedType) {
            next.attachedType = .none
        }
        return next
    }
}

/// 磁吸扩展模块解锁状态（拨杆免费可用；其余需购买）。
enum MagneticModuleUnlockStore {
    private static let key = DeviceCapabilityStorage.magneticModuleUnlockKey

    /// 测试阶段：付费套件在 UI 上全部显示为已解锁。
    static let previewAssumeAllPurchased = true

    static func isUnlocked(_ type: MagneticModuleType) -> Bool {
        if type == .none { return false }
        if type.isIncludedByDefault { return true }
        if previewAssumeAllPurchased, type.requiresPurchase { return true }
        guard type.requiresPurchase else { return false }
        return loadUnlockedRawValues().contains(type.rawValue)
    }

    /// 是否应在 UI 上显示锁定态（测试阶段付费模块不显示锁）。
    static func showsLockedInUI(_ type: MagneticModuleType) -> Bool {
        type.requiresPurchase && !isUnlocked(type)
    }

    static func moduleSourceLabel(for type: MagneticModuleType) -> String {
        if type.isIncludedByDefault { return "免费可用" }
        if type.requiresPurchase {
            if previewAssumeAllPurchased { return "需购买 · 测试已解锁" }
            return isUnlocked(type) ? "已购买解锁" : "未解锁"
        }
        return "—"
    }

    static func moduleCardSubtitle(for module: MagneticModuleType) -> String {
        if module.isIncludedByDefault { return module.subtitle }
        if showsLockedInUI(module) { return "需购买解锁" }
        if previewAssumeAllPurchased, module.requiresPurchase { return "需购买 · 测试已解锁" }
        return module.subtitle
    }

    static func unlock(_ type: MagneticModuleType) {
        guard type.requiresPurchase else { return }
        var raw = loadUnlockedRawValues()
        raw.insert(type.rawValue)
        UserDefaults.standard.set(Array(raw).sorted(), forKey: key)
    }

    static func lockedPurchasableModules() -> [MagneticModuleType] {
        MagneticModuleType.purchasableCases.filter { !isUnlocked($0) }
    }

    static func unlockedPurchasableModules() -> [MagneticModuleType] {
        MagneticModuleType.purchasableCases.filter { isUnlocked($0) }
    }

    private static func loadUnlockedRawValues() -> Set<Int> {
        let list = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
        return Set(list)
    }
}
