import Foundation

// MARK: - 声明式目标配置（WBS-5.6 切片 0：Shared 冻结）
//
// 本文件定义 `AhaKeyConfigurationPackage.desiredConfiguration`（Data）的**唯一**规范编解码。
// Studio 只声明「想要什么」；物理 opcode、槽位策略、传输与恢复全部由 Runtime planner/事务决定。
// Studio 不得另做私有 JSON（现有 UserDefaults 草稿仅作 UI 草稿，提交时必须先编码为本模型）。
//
// 资源一律以 `AhaKeyResourceIdentifier` 引用（内容寻址 CAS），
// 本模型内禁止出现本地文件路径——路径是提交方实现细节，不进 canonical 形态。

/// 声明式目标配置（canonical）。随 `schemaVersion` 演进；解码器必须容忍未知字段。
public struct AhaKeyDesiredConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1

    public let schemaVersion: UInt16
    public let modes: [Mode]

    public init(schemaVersion: UInt16 = Self.currentSchemaVersion, modes: [Mode]) throws {
        guard schemaVersion > 0 else { throw AhaKeyDesiredConfigurationError.invalidSchemaVersion }
        guard !modes.isEmpty else { throw AhaKeyDesiredConfigurationError.emptyModes }
        guard Set(modes.map(\.slot)).count == modes.count else {
            throw AhaKeyDesiredConfigurationError.duplicateModeSlot
        }
        self.schemaVersion = schemaVersion
        self.modes = modes
    }

    /// canonical JSON 编码（键序稳定，供 revision/基线 diff 与 WAL 快照复现）。
    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> AhaKeyDesiredConfiguration {
        try JSONDecoder().decode(AhaKeyDesiredConfiguration.self, from: data)
    }

    // MARK: Mode

    public struct Mode: Codable, Equatable, Sendable {
        /// 模式槽位（0...3，对应固件 mode0..mode3）。
        public let slot: UInt8
        public let keys: [Key]
        public let oled: OLED
        public let lightBar: LightBar

        public init(slot: UInt8, keys: [Key], oled: OLED, lightBar: LightBar) throws {
            guard slot <= 3 else { throw AhaKeyDesiredConfigurationError.invalidModeSlot }
            guard Set(keys.map(\.role)).count == keys.count else {
                throw AhaKeyDesiredConfigurationError.duplicateKeyRole
            }
            self.slot = slot
            self.keys = keys
            self.oled = oled
            self.lightBar = lightBar
        }
    }

    // MARK: Key

    /// 按键角色（对齐固件 4 键）：0=voice 1=approve 2=reject 3=submit。
    public enum KeyRole: UInt8, Codable, CaseIterable, Sendable {
        case voice = 0, approve = 1, reject = 2, submit = 3
    }

    public struct Key: Codable, Equatable, Sendable {
        public let role: KeyRole
        /// 按键行为：单键/组合键 或 固件宏（二选一）。
        public let action: KeyAction
        /// 用户可读描述（仅展示，不下发）。
        public let description: String
        /// voice 角色的预设标识（其余角色为 nil）。
        public let voicePreset: String?

        public init(role: KeyRole, action: KeyAction, description: String, voicePreset: String? = nil) {
            self.role = role
            self.action = action
            self.description = description
            self.voicePreset = voicePreset
        }
    }

    public enum KeyAction: Codable, Equatable, Sendable {
        case shortcut(Shortcut)
        case macro([MacroStep])

        private enum CodingKeys: String, CodingKey { case shortcut, macro }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) {
                self = .shortcut(shortcut)
            } else if let steps = try c.decodeIfPresent([MacroStep].self, forKey: .macro) {
                guard !steps.isEmpty else { throw AhaKeyDesiredConfigurationError.emptyMacro }
                self = .macro(steps)
            } else {
                throw AhaKeyDesiredConfigurationError.missingKeyAction
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .shortcut(let shortcut): try c.encode(shortcut, forKey: .shortcut)
            case .macro(let steps): try c.encode(steps, forKey: .macro)
            }
        }
    }

    public struct Shortcut: Codable, Equatable, Sendable {
        /// 修饰键标识（稳定字符串，如 "control"/"option"/"shift"/"command"）。
        public let modifiers: [String]
        /// HID usage keycode；0 表示仅修饰键。
        public let keyCode: UInt8

        public init(modifiers: [String] = [], keyCode: UInt8) throws {
            guard Set(modifiers).count == modifiers.count else {
                throw AhaKeyDesiredConfigurationError.duplicateModifier
            }
            self.modifiers = modifiers
            self.keyCode = keyCode
        }
    }

    /// 固件宏步骤：(action, param) 两字节。action: 0=noOp 1=downKey 2=upKey 3=delay(×3ms) 4=upAllKeys。
    public struct MacroStep: Codable, Equatable, Sendable {
        public let action: UInt8
        public let param: UInt8

        public init(action: UInt8, param: UInt8 = 0) throws {
            guard action <= 4 else { throw AhaKeyDesiredConfigurationError.invalidMacroAction }
            self.action = action
            self.param = param
        }
    }

    // MARK: OLED

    public struct OLED: Codable, Equatable, Sendable {
        /// 顶层默认动画资源引用（镜像套图 A done 槽语义；nil = 无）。
        public let defaultAnimation: AhaKeyResourceIdentifier?
        public let statusLine: String
        /// 1...30。
        public let framesPerSecond: Int
        /// 任务状态套图，恒 2 套（A/B）。
        public let taskSets: [TaskSet]
        /// 激活套图 0/1；-1 = 尚未同步基线（跨重启动保留）。
        public let activeSet: Int

        public init(
            defaultAnimation: AhaKeyResourceIdentifier?,
            statusLine: String,
            framesPerSecond: Int,
            taskSets: [TaskSet],
            activeSet: Int
        ) throws {
            guard (1...30).contains(framesPerSecond) else {
                throw AhaKeyDesiredConfigurationError.invalidFramesPerSecond
            }
            guard taskSets.count == 2 else { throw AhaKeyDesiredConfigurationError.invalidTaskSetCount }
            guard (-1...1).contains(activeSet) else { throw AhaKeyDesiredConfigurationError.invalidActiveSet }
            self.defaultAnimation = defaultAnimation
            self.statusLine = statusLine
            self.framesPerSecond = framesPerSecond
            self.taskSets = taskSets
            self.activeSet = activeSet
        }
    }

    /// 任务图状态：0=idle 1=working 2=done 3=error（对齐 AhaKeyTaskDisplayState）。
    public enum TaskDisplayState: UInt8, Codable, CaseIterable, Sendable {
        case idle = 0, working = 1, done = 2, error = 3
    }

    public struct TaskSet: Codable, Equatable, Sendable {
        public let assets: [TaskAsset]

        public init(assets: [TaskAsset]) throws {
            guard Set(assets.map(\.state)).count == assets.count else {
                throw AhaKeyDesiredConfigurationError.duplicateTaskState
            }
            self.assets = assets
        }
    }

    public struct TaskAsset: Codable, Equatable, Sendable {
        public let state: TaskDisplayState
        /// 资源引用；nil = 该状态无独立图（planner 决定回退策略，如 idle 回退 working）。
        public let resource: AhaKeyResourceIdentifier?
        /// 5...20。
        public let framesPerSecond: Int

        public init(state: TaskDisplayState, resource: AhaKeyResourceIdentifier?, framesPerSecond: Int) throws {
            guard (5...20).contains(framesPerSecond) else {
                throw AhaKeyDesiredConfigurationError.invalidFramesPerSecond
            }
            self.state = state
            self.resource = resource
            self.framesPerSecond = framesPerSecond
        }
    }

    // MARK: LightBar

    public struct LightBar: Codable, Equatable, Sendable {
        public let stateMappings: [LightStateMapping]
        /// 1...100。
        public let brightness: Int

        public init(stateMappings: [LightStateMapping], brightness: Int) throws {
            guard (1...100).contains(brightness) else {
                throw AhaKeyDesiredConfigurationError.invalidBrightness
            }
            guard Set(stateMappings.map(\.state)).count == stateMappings.count else {
                throw AhaKeyDesiredConfigurationError.duplicateLightState
            }
            self.stateMappings = stateMappings
            self.brightness = brightness
        }
    }

    public struct LightStateMapping: Codable, Equatable, Sendable {
        /// IDE 状态（UInt8 raw，对齐 IDEState）。
        public let state: UInt8
        /// 灯效标识（稳定字符串，对齐 LightEffectStyle rawValue）。
        public let effect: String

        public init(state: UInt8, effect: String) throws {
            guard !effect.isEmpty else { throw AhaKeyDesiredConfigurationError.emptyLightEffect }
            self.state = state
            self.effect = effect
        }
    }

    // MARK: 资源引用完整性

    /// 本配置引用的全部资源标识（供提交方校验 `resources` 数组完整性）。
    public var referencedResources: Set<AhaKeyResourceIdentifier> {
        var result = Set<AhaKeyResourceIdentifier>()
        for mode in modes {
            if let def = mode.oled.defaultAnimation { result.insert(def) }
            for set in mode.oled.taskSets {
                for asset in set.assets {
                    if let resource = asset.resource { result.insert(resource) }
                }
            }
        }
        return result
    }
}

public enum AhaKeyDesiredConfigurationError: Error, Equatable {
    case invalidSchemaVersion
    case emptyModes
    case duplicateModeSlot
    case invalidModeSlot
    case duplicateKeyRole
    case missingKeyAction
    case emptyMacro
    case duplicateModifier
    case invalidMacroAction
    case invalidFramesPerSecond
    case invalidTaskSetCount
    case invalidActiveSet
    case duplicateTaskState
    case invalidBrightness
    case duplicateLightState
    case emptyLightEffect
}
