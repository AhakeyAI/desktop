import Foundation

enum AhaKeyModeSlot: Int, CaseIterable, Codable, Identifiable {
    case mode0 = 0
    case mode1 = 1
    case mode2 = 2
    case mode3 = 3

    var id: Int { rawValue }

    var title: String {
        "Mode \(rawValue + 1)"
    }

    var shortTitle: String {
        "M\(rawValue + 1)"
    }

    var defaultName: String {
        switch self {
        case .mode0: "Claude"
        case .mode1: "Cursor"
        case .mode2: "Codex"
        case .mode3: "custom"
        }
    }

    var name: String {
        AhaKeyModeNameStore.load()[rawValue] ?? defaultName
    }

    var subtitle: String {
        switch self {
        case .mode0:
            "Claude Code · 终端权限 Y/N"
        case .mode1:
            "Cursor · Composer Accept/Reject"
        case .mode2:
            "Codex · ↵ / Esc"
        case .mode3:
            "custom · 自定义模式"
        }
    }

    var guidance: String {
        switch self {
        case .mode0:
            "针对 Claude Code 终端权限菜单：Key2 直接输入 Y（同意），Key3 直接输入 N（拒绝）。"
        case .mode1:
            "针对 Cursor Composer / Agent：Key2 发 ↵、Key3 发 ⌫（与裸键一致）。"
        case .mode2:
            "针对 Codex 终端审批：Key2 发送 ↵ 确认，Key3 发送 Esc 取消。"
        case .mode3:
            "自定义模式：可自由配置所有按键和灯效。"
        }
    }

    var guidanceHoverDetail: String? {
        switch self {
        case .mode1:
            return "若需与「⌘↵ 接受 / ⌘⌫ 拒绝」等组合键一致，请在编辑器里为对应键加修饰，并在 Cursor 设置 → Keyboard Shortcuts 中绑成相同组合。"
        case .mode0, .mode2, .mode3:
            return nil
        }
    }
}

enum AhaKeyModeNameStore {
    private static let key = "ahakey.mode.customNames.v1"

    static func load() -> [Int: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([Int: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    static func save(_ names: [Int: String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum AhaKeyStudioPart: String, CaseIterable, Codable, Identifiable {
    case lightBar
    case oledDisplay
    case key1
    case key2
    case key3
    case key4
    case toggleSwitch
    case magneticPort

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightBar:
            "灯条"
        case .oledDisplay:
            "LCD 屏幕"
        case .key1:
            "Key 1"
        case .key2:
            "Key 2"
        case .key3:
            "Key 3"
        case .key4:
            "Key 4"
        case .toggleSwitch:
            "拨杆"
        case .magneticPort:
            "磁吸底座"
        }
    }

    var subtitle: String {
        switch self {
        case .lightBar:
            "AI 状态反馈"
        case .oledDisplay:
            "动图显示"
        case .key1:
            "语音键"
        case .key2:
            "确认键"
        case .key3:
            "取消键"
        case .key4:
            "删除键"
        case .toggleSwitch:
            "批准方式"
        case .magneticPort:
            "磁吸扩展模块"
        }
    }

    var systemImage: String {
        switch self {
        case .lightBar:
            // lightspectrum.horizontal requires macOS 13; fall back to light.max on macOS 12
            if #available(macOS 13, *) { "lightspectrum.horizontal" } else { "light.max" }
        case .oledDisplay:
            "rectangle.inset.filled"
        case .key1:
            "mic"
        case .key2:
            "checkmark"
        case .key3:
            "xmark"
        case .key4:
            "delete.left"
        case .toggleSwitch:
            "switch.2"
        case .magneticPort:
            "plus.rectangle.on.rectangle"
        }
    }

    var isGen2Only: Bool { self == .magneticPort }

    var keyRole: AhaKeyKeyRole? {
        switch self {
        case .key1:
            .voice
        case .key2:
            .approve
        case .key3:
            .reject
        case .key4:
            .submit
        default:
            nil
        }
    }

    var isKey: Bool { keyRole != nil }

    /// 当前代际在画布 / 右侧 Tab 中可见的部件（与热区一致）。
    static func visibleParts(for generation: DeviceGeneration) -> [AhaKeyStudioPart] {
        switch generation {
        case .gen2:
            return [.lightBar, .oledDisplay, .key1, .key2, .key3, .key4, .magneticPort]
        case .x1:
            return [.lightBar, .oledDisplay, .key1, .key2, .key3, .key4, .toggleSwitch]
        }
    }

    /// Tab 上更短的标签（窄 Inspector 用）。
    var tabTitle: String {
        switch self {
        case .oledDisplay: "LCD"
        case .magneticPort: "磁吸"
        case .key1: "K1"
        case .key2: "K2"
        case .key3: "K3"
        case .key4: "K4"
        case .lightBar: "灯条"
        case .toggleSwitch: "拨杆"
        }
    }
}

enum AhaKeyKeyRole: Int, CaseIterable, Codable, Identifiable {
    case voice = 0
    case approve = 1
    case reject = 2
    case submit = 3

    var id: Int { rawValue }

    var part: AhaKeyStudioPart {
        switch self {
        case .voice:
            .key1
        case .approve:
            .key2
        case .reject:
            .key3
        case .submit:
            .key4
        }
    }

    var title: String {
        switch self {
        case .voice:
            "语音键"
        case .approve:
            "确认键"
        case .reject:
            "取消键"
        case .submit:
            "删除键"
        }
    }

    var systemImage: String {
        switch self {
        case .voice:
            "mic"
        case .approve:
            "checkmark"
        case .reject:
            "xmark"
        case .submit:
            "delete.left"
        }
    }

    var defaultDescription: String {
        switch self {
        case .voice:
            "Record"
        case .approve:
            "Accept"
        case .reject:
            "Reject"
        case .submit:
            "Backspace"
        }
    }

    var manualText: String {
        switch self {
        case .voice:
            "优先用来触发语音输入，用户在软件里看到的是语音软件名，底层仍写成快捷键。"
        case .approve:
            "适合批准、确认、继续执行这类高频动作。"
        case .reject:
            "适合拒绝、取消、停止这类相反动作。"
        case .submit:
            "出厂默认 Backspace，适合删除、撤销输入或清理当前内容。"
        }
    }
}

enum ShortcutModifier: String, CaseIterable, Codable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        }
    }

    var symbol: String {
        switch self {
        case .control:
            "⌃"
        case .option:
            "⌥"
        case .shift:
            "⇧"
        case .command:
            "⌘"
        }
    }

    var hidCode: UInt8 {
        switch self {
        case .control:
            HIDUsage.leftControl
        case .option:
            HIDUsage.leftAlt
        case .shift:
            HIDUsage.leftShift
        case .command:
            HIDUsage.leftGUI
        }
    }

    static let displayOrder: [ShortcutModifier] = [.control, .option, .shift, .command]
}

struct ShortcutBinding: Codable, Equatable {
    var modifiers: [ShortcutModifier]
    var keyCode: UInt8

    init(modifiers: [ShortcutModifier] = [], keyCode: UInt8 = 0) {
        self.modifiers = Self.normalized(modifiers)
        self.keyCode = keyCode
    }

    var hidCodes: [UInt8] {
        orderedModifiers.map(\.hidCode) + (keyCode == 0 ? [] : [keyCode])
    }

    var orderedModifiers: [ShortcutModifier] {
        modifiers.sorted { lhs, rhs in
            let order = ShortcutModifier.displayOrder
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }

    var displayLabel: String {
        let modifierLabel = orderedModifiers.map(\.symbol).joined()
        let keyLabel = keyCode == 0 ? "" : HIDUsage.name(for: keyCode)
        let combined = modifierLabel + keyLabel
        return combined.isEmpty ? "未设置" : combined
    }

    var isConfigured: Bool {
        keyCode != 0 || !modifiers.isEmpty
    }

    mutating func setModifier(_ modifier: ShortcutModifier, enabled: Bool) {
        var next = modifiers
        if enabled {
            next.append(modifier)
        } else {
            next.removeAll { $0 == modifier }
        }
        modifiers = Self.normalized(next)
    }

    private static func normalized(_ modifiers: [ShortcutModifier]) -> [ShortcutModifier] {
        var seen = Set<ShortcutModifier>()
        var result: [ShortcutModifier] = []
        for modifier in ShortcutModifier.displayOrder where modifiers.contains(modifier) {
            if seen.insert(modifier).inserted {
                result.append(modifier)
            }
        }
        return result
    }
}

enum VoicePreset: String, CaseIterable, Codable, Identifiable {
    case macOSNative
    case typeless
    case wechat
    case claudeCode
    case kimiCode
    case codex
    case doubao
    case custom

    var id: String { rawValue }

    /// claudeCode / kimiCode 与 macOSNative 底层路由完全相同，合并展示为同一选项。
    /// 保留枚举 case 是为了向下兼容已存储的配置数据；迁移在 AhaKeyStudioStore 完成。
    var isMacOSNativeFamily: Bool {
        self == .macOSNative || self == .claudeCode || self == .kimiCode
    }

    /// Picker 中实际展示的选项（微信/豆包并入 Fn/Globe；旧 case 保留用于迁移）
    static var visibleCases: [VoicePreset] {
        [.macOSNative, .typeless, .custom]
    }

    var title: String {
        switch self {
        case .macOSNative, .claudeCode, .kimiCode:
            "macOS 原生转写"
        case .typeless:
            "Fn/Globe"
        case .wechat:
            "微信语音"
        case .codex:
            "Codex"
        case .doubao:
            "豆包输入法"
        case .custom:
            "自定义快捷键"
        }
    }

    var detail: String {
        switch self {
        case .macOSNative, .claudeCode, .kimiCode:
            "调用苹果原生语音转写，识别完成后以 ⌘V 写回当前光标位置。适合 Claude Code、Kimi Code、Codex 等 CLI 终端及任意输入框。按一次开始，再按一次结束。"
        case .typeless:
            "预设对应快捷键：Typeless/微信语音/豆包输入法内仍选 Fn/Globe。本 Studio 使用 F19 作为 Fn 触发键；按下后向系统注入「按住 Fn」。旧版 F18 仍会兼容监听。请授予输入监控与辅助功能。"
        case .wechat:
            "AhaKey Studio 使用 F19 作为 Fn 触发键，并在后台把语音键的按下/松开转换成 Fn/Globe，便于接入微信语音。"
        case .doubao:
            "豆包输入法 Mac 版需要直接接收真实语音键事件。AhaKey Studio 会切到豆包输入源，并把 F18 配置为豆包长按语音快捷键；按住语音键说话，松开后由豆包提交文字。"
        case .codex:
            "规划中，保留入口。"
        case .custom:
            "直接自己指定底层快捷键。"
        }
    }

    var availableInV1: Bool {
        switch self {
        case .codex:
            false
        default:
            true
        }
    }

    var defaultBinding: ShortcutBinding {
        switch self {
        case .macOSNative:
            ShortcutBinding(keyCode: HIDUsage.f18)
        case .typeless:
            // 与 macOS 原生默认 F18 错开；固件可把 Typeless 档语音键设为 F19，Mode 0 另有 F18 出厂兼容路由
            ShortcutBinding(keyCode: HIDUsage.f19)
        case .wechat:
            ShortcutBinding(keyCode: HIDUsage.f19)
        case .claudeCode:
            ShortcutBinding(keyCode: HIDUsage.f18)
        case .kimiCode:
            ShortcutBinding(keyCode: HIDUsage.f18)
        case .codex:
            ShortcutBinding(keyCode: HIDUsage.f18)
        case .doubao:
            ShortcutBinding(keyCode: HIDUsage.f18)
        case .custom:
            ShortcutBinding()
        }
    }
}

enum LightBarPreviewState: String, CaseIterable, Codable, Identifiable {
    case aiRunning
    case waitingApproval
    case stopped
    case taskCompleted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiRunning:
            "AI 运行中"
        case .waitingApproval:
            "等待批准"
        case .stopped:
            "已停止"
        case .taskCompleted:
            "任务完成"
        }
    }

    var detail: String {
        switch self {
        case .aiRunning:
            "默认效果是来回流水灯。"
        case .waitingApproval:
            "提醒用户当前需要确认。"
        case .stopped:
            "默认用红色常亮停住。"
        case .taskCompleted:
            "表示本轮执行已经完成。"
        }
    }

    var ideState: IDEState {
        switch self {
        case .aiRunning:
            .preToolUse
        case .waitingApproval:
            .permissionRequest
        case .stopped:
            .stop
        case .taskCompleted:
            .taskCompleted
        }
    }
}

enum LightEffectStyle: String, CaseIterable, Codable, Identifiable {
    case off
    case middleLight
    case singleMove
    case breathing
    case rainbowMove
    case rainbowWave
    case rainbowWaveSlow
    case typingRipple
    case comet
    case scanBar
    case pulseCenter
    case warningBlink
    case successSweep
    case blueThinking
    case lowBattery
    case chargingFlow
    case approvalWait

    var id: String { rawValue }

    var firmwareIndex: UInt8 {
        switch self {
        case .off: 0
        case .singleMove: 1
        case .rainbowMove: 2
        case .rainbowWave: 3
        case .rainbowWaveSlow: 4
        case .breathing: 5
        case .middleLight: 6
        case .typingRipple: 7
        case .comet: 8
        case .scanBar: 9
        case .pulseCenter: 10
        case .warningBlink: 11
        case .successSweep: 12
        case .blueThinking: 13
        case .lowBattery: 14
        case .chargingFlow: 15
        case .approvalWait: 16
        }
    }

    init?(firmwareIndex: UInt8) {
        guard let match = Self.allCases.first(where: { $0.firmwareIndex == firmwareIndex }) else {
            return nil
        }
        self = match
    }

    var title: String {
        switch self {
        case .off: "熄灭"
        case .middleLight: "中间停住"
        case .singleMove: "来回流水"
        case .breathing: "整条呼吸"
        case .rainbowMove: "彩虹流水"
        case .rainbowWave: "彩虹波浪"
        case .rainbowWaveSlow: "彩虹慢波浪"
        case .typingRipple: "打字涟漪"
        case .comet: "彗星拖尾"
        case .scanBar: "扫描条"
        case .pulseCenter: "中心脉冲"
        case .warningBlink: "警告闪烁"
        case .successSweep: "成功扫过"
        case .blueThinking: "蓝色思考"
        case .lowBattery: "低电量"
        case .chargingFlow: "充电流动"
        case .approvalWait: "等待审批"
        }
    }

    var detail: String {
        switch self {
        case .off: "不点亮灯条。"
        case .middleLight: "中间最亮，两侧渐弱，适合停住提示。"
        case .singleMove: "单点来回移动，适合运行中。"
        case .breathing: "整条均匀起伏，适合等待确认。"
        case .rainbowMove: "彩色单点流水，更活跃。"
        case .rainbowWave: "整条彩色流动，更显眼。"
        case .rainbowWaveSlow: "比普通彩虹波浪更慢，适合做氛围效果。"
        case .typingRipple: "从中心向两侧扩散的涟漪效果。"
        case .comet: "带拖尾的单向扫过，像彗星。"
        case .scanBar: "3 灯一组左右扫描。"
        case .pulseCenter: "中心快速脉冲扩散。"
        case .warningBlink: "橙色快速闪烁，适合警告。"
        case .successSweep: "绿色从左到右逐渐点亮。"
        case .blueThinking: "蓝色呼吸波浪，适合思考中。"
        case .lowBattery: "红色慢闪，表示低电量。"
        case .chargingFlow: "绿色填充流动，表示充电中。"
        case .approvalWait: "琥珀色呼吸 + 中心闪烁，等待用户操作。"
        }
    }
}

struct AhaKeyLightStateDraft: Codable, Equatable, Identifiable {
    var state: IDEState
    var effect: LightEffectStyle

    var id: UInt8 { state.rawValue }

    private enum CodingKeys: String, CodingKey {
        case state, effect
    }

    init(state: IDEState, effect: LightEffectStyle) {
        self.state = state
        self.effect = effect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        effect = try container.decode(LightEffectStyle.self, forKey: .effect)
        if let ideState = try? container.decode(IDEState.self, forKey: .state) {
            state = ideState
        } else if let legacy = try? container.decode(LightBarPreviewState.self, forKey: .state) {
            state = legacy.ideState
        } else {
            state = .notification
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(effect, forKey: .effect)
    }
}

struct AhaKeyLightBarDraft: Codable, Equatable {
    var stateMappings: [AhaKeyLightStateDraft]
    var brightness: Int

    func effect(for state: IDEState) -> LightEffectStyle {
        stateMappings.first(where: { $0.state == state })?.effect ?? .singleMove
    }

    private enum CodingKeys: String, CodingKey {
        case stateMappings, brightness
    }

    init(stateMappings: [AhaKeyLightStateDraft], brightness: Int = 35) {
        self.stateMappings = stateMappings
        self.brightness = brightness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMappings = try container.decode([AhaKeyLightStateDraft].self, forKey: .stateMappings)
        let rawBrightness = try container.decodeIfPresent(Int.self, forKey: .brightness) ?? 35
        brightness = max(1, min(100, rawBrightness))

        if rawMappings.count >= IDEState.allCases.count {
            stateMappings = rawMappings
        } else {
            let defaults = AhaKeyLightBarDraft.defaultMappings
            var merged = rawMappings
            for defaultMapping in defaults {
                if !merged.contains(where: { $0.state == defaultMapping.state }) {
                    merged.append(defaultMapping)
                }
            }
            stateMappings = merged.sorted { $0.state.rawValue < $1.state.rawValue }
        }
    }

    static let defaultMappings: [AhaKeyLightStateDraft] = [
        AhaKeyLightStateDraft(state: .notification, effect: .pulseCenter),
        AhaKeyLightStateDraft(state: .permissionRequest, effect: .approvalWait),
        AhaKeyLightStateDraft(state: .postToolUse, effect: .successSweep),
        AhaKeyLightStateDraft(state: .preToolUse, effect: .singleMove),
        AhaKeyLightStateDraft(state: .sessionStart, effect: .rainbowWave),
        AhaKeyLightStateDraft(state: .stop, effect: .middleLight),
        AhaKeyLightStateDraft(state: .taskCompleted, effect: .successSweep),
        AhaKeyLightStateDraft(state: .userPromptSubmit, effect: .breathing),
        AhaKeyLightStateDraft(state: .sessionEnd, effect: .off),
    ]

    static func `default`(for mode: AhaKeyModeSlot) -> AhaKeyLightBarDraft {
        _ = mode
        return AhaKeyLightBarDraft(stateMappings: defaultMappings, brightness: 35)
    }
}

/// 固件宏步骤动作类型。
/// 对应老 Python 客户端 `MacroAction`，固件端已实现执行逻辑。
enum MacroAction: UInt8, Codable, CaseIterable, Identifiable {
    case noOp = 0
    case downKey = 1
    case upKey = 2
    /// `param` 单位为 3ms（固件规定），最大 255 ≈ 765ms。
    case delay = 3
    case upAllKeys = 4

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .noOp: return "空操作"
        case .downKey: return "按下"
        case .upKey: return "松开"
        case .delay: return "延时"
        case .upAllKeys: return "全部松开"
        }
    }

    /// 窄 Inspector 宏行用的短标签。
    var shortTitle: String {
        switch self {
        case .noOp: return "空"
        case .downKey: return "按下"
        case .upKey: return "松开"
        case .delay: return "延时"
        case .upAllKeys: return "全松"
        }
    }

    /// 是否需要 HID 键码作为 param。
    var takesKeycodeParam: Bool {
        self == .downKey || self == .upKey
    }

    /// 是否把 param 当 delay 单位（×3ms）使用。
    var takesDelayParam: Bool {
        self == .delay
    }
}

/// 一个宏步骤。对固件协议而言就是 (action, param) 两个字节。
struct MacroStep: Codable, Equatable, Identifiable {
    var id: UUID
    var action: MacroAction
    /// downKey/upKey：HID keycode；delay：×3ms；noOp / upAllKeys：忽略。
    var param: UInt8

    init(id: UUID = UUID(), action: MacroAction, param: UInt8 = 0) {
        self.id = id
        self.action = action
        self.param = param
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case action
        case param
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.action = try c.decode(MacroAction.self, forKey: .action)
        self.param = try c.decodeIfPresent(UInt8.self, forKey: .param) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(action, forKey: .action)
        try c.encode(param, forKey: .param)
    }

    /// 渲染成 `↓` / `Enter` / `+5ms`… 这样的人类可读片段，inspector 和 summary 都用。
    var displayLabel: String {
        switch action {
        case .noOp:
            return "no-op"
        case .downKey:
            return "↓\(HIDUsage.name(for: param))"
        case .upKey:
            return "↑\(HIDUsage.name(for: param))"
        case .delay:
            let ms = Int(param) * 3
            return "+\(ms)ms"
        case .upAllKeys:
            return "↑ALL"
        }
    }
}

extension Array where Element == MacroStep {
    /// 展平成 (action, param, action, param, ...) 字节流，长度 = 2 × 步数。
    /// 固件上限 98 字节 ≈ 49 步；这里不做截断，由调用方检查/提示。
    var flattenedBytes: [UInt8] {
        flatMap { [$0.action.rawValue, $0.param] }
    }

    /// 浓缩描述：把连续的 down/up 对合并成 `X` 方便展示。
    /// 不能完整还原所有细节，只用于 UI summary。
    var displaySummary: String {
        var parts: [String] = []
        var i = 0
        while i < count {
            let step = self[i]
            if step.action == .downKey,
               i + 1 < count,
               self[i + 1].action == .upKey,
               self[i + 1].param == step.param
            {
                parts.append(HIDUsage.name(for: step.param))
                i += 2
            } else {
                parts.append(step.displayLabel)
                i += 1
            }
        }
        return parts.joined(separator: " → ")
    }
}

struct AhaKeyKeyDraft: Codable, Equatable, Identifiable {
    let role: AhaKeyKeyRole
    var shortcut: ShortcutBinding
    /// 非空则整个按键走固件宏下发（`cmdUpdateCustomKey / subMacro`），
    /// 此时 `shortcut` 被忽略。为空则走 `subShortcut`（单键/组合键）。
    var macro: [MacroStep]
    var description: String
    var voicePreset: VoicePreset?

    init(
        role: AhaKeyKeyRole,
        shortcut: ShortcutBinding,
        macro: [MacroStep] = [],
        description: String,
        voicePreset: VoicePreset? = nil
    ) {
        self.role = role
        self.shortcut = shortcut
        self.macro = macro
        self.description = description
        self.voicePreset = voicePreset
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case shortcut
        case macro
        case description
        case voicePreset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try c.decode(AhaKeyKeyRole.self, forKey: .role)
        self.shortcut = try c.decode(ShortcutBinding.self, forKey: .shortcut)
        self.macro = try c.decodeIfPresent([MacroStep].self, forKey: .macro) ?? []
        self.description = try c.decode(String.self, forKey: .description)
        self.voicePreset = try c.decodeIfPresent(VoicePreset.self, forKey: .voicePreset)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(shortcut, forKey: .shortcut)
        if !macro.isEmpty {
            try c.encode(macro, forKey: .macro)
        }
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(voicePreset, forKey: .voicePreset)
    }

    var id: Int { role.rawValue }

    var title: String { role.title }

    /// 当前按键是否以"宏"形式下发。
    var usesMacro: Bool { !macro.isEmpty }

    var displaySummary: String {
        if role == .voice, let voicePreset {
            return voicePreset.title
        }
        if usesMacro {
            return "宏：\(macro.displaySummary)"
        }
        return shortcut.displayLabel
    }
}

struct AhaKeyOLEDDraft: Codable, Equatable {
    var localAssetPath: String?
    var statusLine: String
    var framesPerSecond: Int

    private enum CodingKeys: String, CodingKey {
        case localAssetPath
        case statusLine
        case framesPerSecond
    }

    init(localAssetPath: String?, statusLine: String, framesPerSecond: Int = 12) {
        self.localAssetPath = localAssetPath
        self.statusLine = statusLine
        self.framesPerSecond = framesPerSecond
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localAssetPath = try container.decodeIfPresent(String.self, forKey: .localAssetPath)
        statusLine = try container.decode(String.self, forKey: .statusLine)
        let storedFPS = try container.decodeIfPresent(Int.self, forKey: .framesPerSecond) ?? 12
        framesPerSecond = min(30, max(1, storedFPS))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(localAssetPath, forKey: .localAssetPath)
        try container.encode(statusLine, forKey: .statusLine)
        try container.encode(framesPerSecond, forKey: .framesPerSecond)
    }

    static func `default`(for mode: AhaKeyModeSlot) -> AhaKeyOLEDDraft {
        let statusLine: String
        switch mode {
        case .mode0:
            statusLine = "Claude Code · 终端权限菜单 Y/N。"
        case .mode1:
            statusLine = "Cursor · ↵ 接受改动 / ⌫ 拒绝改动。"
        case .mode2:
            statusLine = "Codex · 审批 ↵ / Esc。"
        case .mode3:
            statusLine = "自定义模式。"
        }
        return AhaKeyOLEDDraft(
            localAssetPath: DefaultOLEDAssets.bundledAssetPath(for: mode),
            statusLine: statusLine,
            framesPerSecond: 12
        )
    }
}

struct AhaKeyModeDraft: Codable, Equatable, Identifiable {
    let mode: AhaKeyModeSlot
    var keys: [AhaKeyKeyDraft]
    var oled: AhaKeyOLEDDraft
    var lightBar: AhaKeyLightBarDraft

    var id: Int { mode.rawValue }

    init(mode: AhaKeyModeSlot, keys: [AhaKeyKeyDraft], oled: AhaKeyOLEDDraft, lightBar: AhaKeyLightBarDraft) {
        self.mode = mode
        self.keys = keys
        self.oled = oled
        self.lightBar = lightBar
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case keys
        case oled
        case lightBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(AhaKeyModeSlot.self, forKey: .mode)
        keys = try container.decode([AhaKeyKeyDraft].self, forKey: .keys)
        oled = try container.decodeIfPresent(AhaKeyOLEDDraft.self, forKey: .oled) ?? .default(for: mode)
        lightBar = try container.decodeIfPresent(AhaKeyLightBarDraft.self, forKey: .lightBar) ?? .default(for: mode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(keys, forKey: .keys)
        try container.encode(oled, forKey: .oled)
        try container.encode(lightBar, forKey: .lightBar)
    }

    func key(for role: AhaKeyKeyRole) -> AhaKeyKeyDraft {
        keys.first { $0.role == role } ?? AhaKeyModeDraft.default(for: mode).keys[role.rawValue]
    }

    mutating func updateKey(_ updated: AhaKeyKeyDraft) {
        if let index = keys.firstIndex(where: { $0.role == updated.role }) {
            keys[index] = updated
        }
    }

    /// Claude CLI 新版菜单 "1. Yes / 2. Yes, allow all / 3. No"：
    /// 光标默认在 Yes 上，所以 No 需要先 ↓ 两次再回车。
    /// 这是一个固件原生宏（action/param pairs），由键盘自己串行吐三个 HID 事件。
    static let claudeNoMacroSteps: [MacroStep] = [
        .init(action: .downKey, param: HIDUsage.downArrow),
        .init(action: .upKey, param: HIDUsage.downArrow),
        .init(action: .delay, param: 5),
        .init(action: .downKey, param: HIDUsage.downArrow),
        .init(action: .upKey, param: HIDUsage.downArrow),
        .init(action: .delay, param: 5),
        .init(action: .downKey, param: HIDUsage.enter),
        .init(action: .upKey, param: HIDUsage.enter),
    ]

    static func `default`(for mode: AhaKeyModeSlot) -> AhaKeyModeDraft {
        let voicePreset: VoicePreset = .macOSNative
        let approveShortcut: ShortcutBinding
        let rejectShortcut: ShortcutBinding
        var rejectMacro: [MacroStep] = []
        let approveDescription: String
        let rejectDescription: String

        switch mode {
        case .mode0:
            // Yes 按 Enter；No 用固件原生宏 ↓↓⏎。
            approveShortcut = ShortcutBinding(keyCode: HIDUsage.enter)
            rejectShortcut = ShortcutBinding()
            rejectMacro = claudeNoMacroSteps
            approveDescription = "Yes"
            rejectDescription = "No"
        case .mode1:
            // 与固件 `defult_key_0_1` 等裸 HID 风格一致：单键 Enter / Backspace。若要用 Composer 默认 ⌘ 组合，由用户在编辑器中勾选 ⌘ 或改 Cursor 快捷键。
            approveShortcut = ShortcutBinding(keyCode: HIDUsage.enter)
            rejectShortcut = ShortcutBinding(keyCode: HIDUsage.backspace)
            approveDescription = "Accept"
            rejectDescription = "Reject"
        case .mode2:
            approveShortcut = ShortcutBinding(keyCode: HIDUsage.enter)
            rejectShortcut = ShortcutBinding(keyCode: HIDUsage.escape)
            approveDescription = "Accept"
            rejectDescription = "Reject"
        case .mode3:
            approveShortcut = ShortcutBinding(keyCode: HIDUsage.enter)
            rejectShortcut = ShortcutBinding(keyCode: HIDUsage.escape)
            approveDescription = "Accept"
            rejectDescription = "Reject"
        }

        return AhaKeyModeDraft(
            mode: mode,
            keys: [
                AhaKeyKeyDraft(
                    role: .voice,
                    shortcut: voicePreset.defaultBinding,
                    description: AhaKeyKeyRole.voice.defaultDescription,
                    voicePreset: voicePreset
                ),
                AhaKeyKeyDraft(
                    role: .approve,
                    shortcut: approveShortcut,
                    description: approveDescription,
                    voicePreset: nil
                ),
                AhaKeyKeyDraft(
                    role: .reject,
                    shortcut: rejectShortcut,
                    macro: rejectMacro,
                    description: rejectDescription,
                    voicePreset: nil
                ),
                AhaKeyKeyDraft(
                    role: .submit,
                    shortcut: ShortcutBinding(keyCode: HIDUsage.backspace),
                    description: AhaKeyKeyRole.submit.defaultDescription,
                    voicePreset: nil
                ),
            ],
            oled: .default(for: mode),
            lightBar: .default(for: mode)
        )
    }
}

struct AhaKeyStudioDraft: Codable, Equatable {
    var modes: [AhaKeyModeDraft]

    static let `default` = AhaKeyStudioDraft(
        modes: AhaKeyModeSlot.allCases.map { AhaKeyModeDraft.default(for: $0) }
    )

    func draft(for mode: AhaKeyModeSlot) -> AhaKeyModeDraft {
        modes.first(where: { $0.mode == mode }) ?? AhaKeyModeDraft.default(for: mode)
    }

    mutating func updateMode(_ updated: AhaKeyModeDraft) {
        if let index = modes.firstIndex(where: { $0.mode == updated.mode }) {
            modes[index] = updated
        }
    }
}

enum AhaKeyStudioStore {
    private static let key = "ahakey.studio.draft.v1"

    static func load() -> AhaKeyStudioDraft? {
        guard let data = UserDefaults.standard.data(forKey: key),
              var draft = try? JSONDecoder().decode(AhaKeyStudioDraft.self, from: data) else {
            return nil
        }
        let existingSlots = Set(draft.modes.map(\.mode))
        for slot in AhaKeyModeSlot.allCases where !existingSlots.contains(slot) {
            draft.modes.append(AhaKeyModeDraft.default(for: slot))
        }
        return migratedDraft(from: draft)
    }

    static func save(_ draft: AhaKeyStudioDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func migratedDraft(from draft: AhaKeyStudioDraft) -> AhaKeyStudioDraft {
        var next = draft
        var mode0 = next.draft(for: .mode0)
        let legacyDescriptions: [AhaKeyKeyRole: String] = [
            .voice: "语音",
            .approve: "批准",
            .reject: "拒绝",
            .submit: "回车",
        ]

        for role in AhaKeyKeyRole.allCases {
            var key = mode0.key(for: role)
            if key.description.isEmpty || key.description == legacyDescriptions[role] {
                key.description = role.defaultDescription
            }
            if role == .voice,
               key.voicePreset == .macOSNative,
               key.shortcut.keyCode == HIDUsage.f17,
               key.shortcut.modifiers.isEmpty
            {
                key.shortcut = ShortcutBinding(keyCode: HIDUsage.f18)
            }
            mode0.updateKey(key)
        }
        next.updateMode(mode0)

        // claudeCode / kimiCode 已合并到 macOSNative，迁移所有 mode 里的旧 preset。
        for modeSlot in AhaKeyModeSlot.allCases {
            var modeDraft = next.draft(for: modeSlot)
            var voiceKey = modeDraft.key(for: .voice)
            if voiceKey.voicePreset == .claudeCode || voiceKey.voicePreset == .kimiCode {
                voiceKey.voicePreset = .macOSNative
                modeDraft.updateKey(voiceKey)
                next.updateMode(modeDraft)
            }
        }

        // 旧 Mode 0 = Cursor / 旧 Mode 1 = Claude 的用户，自动对调成新默认布局。
        // 仅当两个 mode 的 approve/reject 都完全等于旧默认时触发，保护手动改过的配置。
        let cursorApproveBinding = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
        let cursorRejectBinding = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.backspace)
        let claudeApproveBinding = ShortcutBinding(keyCode: 0x1C)
        let claudeRejectBinding = ShortcutBinding(keyCode: 0x11)

        let legacyMode0 = next.draft(for: .mode0)
        let legacyMode1 = next.draft(for: .mode1)
        let mode0LooksLikeCursor =
            legacyMode0.key(for: .approve).shortcut == cursorApproveBinding
            && legacyMode0.key(for: .approve).description == "Accept"
            && legacyMode0.key(for: .reject).shortcut == cursorRejectBinding
            && legacyMode0.key(for: .reject).description == "Reject"
        let mode1LooksLikeClaude =
            legacyMode1.key(for: .approve).shortcut == claudeApproveBinding
            && legacyMode1.key(for: .approve).description == "Yes"
            && legacyMode1.key(for: .reject).shortcut == claudeRejectBinding
            && legacyMode1.key(for: .reject).description == "No"

        if mode0LooksLikeCursor, mode1LooksLikeClaude {
            let m1Def = AhaKeyModeDraft.default(for: .mode1)
            var newMode0 = legacyMode0
            var newMode1 = legacyMode1
            var approve0 = newMode0.key(for: .approve)
            approve0.shortcut = claudeApproveBinding
            approve0.description = "Yes"
            newMode0.updateKey(approve0)
            var reject0 = newMode0.key(for: .reject)
            reject0.shortcut = claudeRejectBinding
            reject0.description = "No"
            newMode0.updateKey(reject0)
            var approve1 = newMode1.key(for: .approve)
            approve1.shortcut = m1Def.key(for: .approve).shortcut
            approve1.description = "Accept"
            newMode1.updateKey(approve1)
            var reject1 = newMode1.key(for: .reject)
            reject1.shortcut = m1Def.key(for: .reject).shortcut
            reject1.macro = m1Def.key(for: .reject).macro
            reject1.description = "Reject"
            newMode1.updateKey(reject1)
            next.updateMode(newMode0)
            next.updateMode(newMode1)
        }

        let legacyOLEDStatusLines: Set<String> = [
            "当前仅支持动图",
            "切换模式时会先显示按键描述，再回到 Mode 1 默认动图。",
            "当前模式还未上传动图，后续可替换成你的自定义 GIF。",
            "Cursor · ⌘↵ 接受改动 / ⌘⌫ 拒绝改动。",
            "Claude Code · 终端权限菜单 Y/N。",
            "Codex · 审批 ↵ / Esc。",
        ]
        let legacyApproveBinding = ShortcutBinding(keyCode: HIDUsage.enter)
        let legacyRejectBinding = ShortcutBinding(keyCode: HIDUsage.escape)
        let legacyApproveDescriptions: Set<String> = ["Accept", "批准", ""]
        let legacyRejectDescriptions: Set<String> = ["Reject", "拒绝", ""]

        for mode in AhaKeyModeSlot.allCases {
            var modeDraft = next.draft(for: mode)
            let target = AhaKeyModeDraft.default(for: mode)

            if legacyOLEDStatusLines.contains(modeDraft.oled.statusLine) {
                modeDraft.oled.statusLine = AhaKeyOLEDDraft.default(for: mode).statusLine
            }

            // LCD 素材路径自愈：用户没选过自定义 GIF（为 nil）或引用的是旧 bundle 路径时，
            // 刷成当前构建下内置 GIF 的绝对路径；用户自选的外部路径原样保留。
            if let bundled = DefaultOLEDAssets.bundledAssetPath(for: mode) {
                if modeDraft.oled.localAssetPath == nil
                    || (modeDraft.oled.localAssetPath.map(DefaultOLEDAssets.isBundledPath) ?? false)
                {
                    modeDraft.oled.localAssetPath = bundled
                }
            } else if let existing = modeDraft.oled.localAssetPath,
                      DefaultOLEDAssets.isBundledPath(existing) {
                modeDraft.oled.localAssetPath = nil
            }

            var voiceKey = modeDraft.key(for: .voice)
            if voiceKey.voicePreset == .wechat || voiceKey.voicePreset == .doubao {
                voiceKey.voicePreset = .typeless
                modeDraft.updateKey(voiceKey)
            }
            voiceKey = modeDraft.key(for: .voice)
            if voiceKey.voicePreset == .macOSNative,
               voiceKey.shortcut.keyCode == HIDUsage.f17,
               voiceKey.shortcut.modifiers.isEmpty
            {
                voiceKey.shortcut = ShortcutBinding(keyCode: HIDUsage.f18)
                modeDraft.updateKey(voiceKey)
            }
            if (voiceKey.voicePreset == .typeless || voiceKey.voicePreset == .wechat),
               voiceKey.shortcut.keyCode == HIDUsage.f18,
               voiceKey.shortcut.modifiers.isEmpty
            {
                voiceKey.shortcut = ShortcutBinding(keyCode: HIDUsage.f19)
                modeDraft.updateKey(voiceKey)
            }

            var submitKey = modeDraft.key(for: .submit)
            if submitKey.macro.isEmpty,
               submitKey.shortcut == ShortcutBinding(keyCode: HIDUsage.enter),
               (submitKey.description == "Enter" || submitKey.description == "回车" || submitKey.description.isEmpty)
            {
                let targetSubmit = target.key(for: .submit)
                submitKey.shortcut = targetSubmit.shortcut
                submitKey.description = targetSubmit.description
                modeDraft.updateKey(submitKey)
            }

            submitKey = modeDraft.key(for: .submit)
            if submitKey.shortcut == ShortcutBinding(keyCode: HIDUsage.backspace),
               submitKey.macro.isEmpty,
               ["", "backspace", "Back space", "Back Space", "删除", "删除键"].contains(submitKey.description)
            {
                submitKey.description = AhaKeyKeyRole.submit.defaultDescription
                modeDraft.updateKey(submitKey)
            }

            if modeDraft.lightBar.brightness == 50 {
                modeDraft.lightBar.brightness = 35
            }

            // 旧版「全模式通用」模板曾用 主键↵/Esc + Accept/Reject 文案。Codex/其它 mode 的升级仍需要；
            // Mode 1（Cursor）允许用户**有意**改组合键，若继续套用下面规则会在每次启动时改回出厂 ↵/⌫，表现为改键不保存。
            if mode != .mode1 {
                var approveKey = modeDraft.key(for: .approve)
                if approveKey.shortcut == legacyApproveBinding,
                   legacyApproveDescriptions.contains(approveKey.description)
                {
                    let targetApprove = target.key(for: .approve)
                    approveKey.shortcut = targetApprove.shortcut
                    approveKey.description = targetApprove.description
                    modeDraft.updateKey(approveKey)
                }

                var rejectKey = modeDraft.key(for: .reject)
                if rejectKey.shortcut == legacyRejectBinding,
                   legacyRejectDescriptions.contains(rejectKey.description)
                {
                    let targetReject = target.key(for: .reject)
                    rejectKey.shortcut = targetReject.shortcut
                    rejectKey.description = targetReject.description
                    // 必须与当前 mode 的默认一致：Mode 0 的 No 依赖固件宏 ↓↓⏎，不能只拷 shortcut（否则宏为空，UI 会退化成单键展示）。
                    rejectKey.macro = targetReject.macro
                    modeDraft.updateKey(rejectKey)
                }
            }

            // Mode 0 (Claude) 专门的升级路径：
            //   老草稿 1：reject = "N" (0x11)            → 升级成固件原生宏 ↓↓⏎
            //   老草稿 2：reject = "F20" (0x6F) 代理键   → 升级成固件原生宏 ↓↓⏎
            // 同时把 approve 从 0x1C (Y) 升级成 Enter。
            // 升级前提：用户没手动改过描述（为空或仍是默认 "Yes" / "No"）。
            if mode == .mode0 {
                var approve0 = modeDraft.key(for: .approve)
                if approve0.shortcut == ShortcutBinding(keyCode: 0x1C),
                   approve0.description == "Yes" || approve0.description.isEmpty,
                   approve0.macro.isEmpty
                {
                    approve0.shortcut = ShortcutBinding(keyCode: HIDUsage.enter)
                    approve0.description = "Yes"
                    modeDraft.updateKey(approve0)
                }
                var reject0 = modeDraft.key(for: .reject)
                let wasLegacyN = reject0.shortcut == ShortcutBinding(keyCode: 0x11)
                let wasF20Proxy = reject0.shortcut == ShortcutBinding(keyCode: HIDUsage.f20)
                if (wasLegacyN || wasF20Proxy),
                   reject0.description == "No" || reject0.description.isEmpty,
                   reject0.macro.isEmpty
                {
                    reject0.shortcut = ShortcutBinding()
                    reject0.macro = AhaKeyModeDraft.claudeNoMacroSteps
                    reject0.description = "No"
                    modeDraft.updateKey(reject0)
                }

                // 自愈：旧版迁移从 Esc 切到 No 时曾漏拷 macro；或用户在 Inspector 里把「宏」切到「单键/组合键」会清空宏。No 的应有配置是空 shortcut + ↓↓⏎。
                var rejectNo = modeDraft.key(for: .reject)
                if rejectNo.description == "No",
                   rejectNo.macro.isEmpty,
                   rejectNo.shortcut == ShortcutBinding()
                    || rejectNo.shortcut == ShortcutBinding(keyCode: HIDUsage.enter)
                {
                    rejectNo.shortcut = ShortcutBinding()
                    rejectNo.macro = AhaKeyModeDraft.claudeNoMacroSteps
                    modeDraft.updateKey(rejectNo)
                }
            }

            // Mode 1（Cursor）取消键为「单键 Backspace」HID 快捷键。若草稿里仍残留非空 macro（例如从其它 mode 误带、或 UI 曾切宏后未清干净），
            // `usesMacro` 会为 true，全量同步会走 0x74 覆盖 0x73，设备表现与界面上的 ⌫ 不一致（ble-comm 里可见「取消键 宏: …」）。
            if mode == .mode1 {
                let oldDefaultApprove = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.enter)
                let oldDefaultReject = ShortcutBinding(modifiers: [.command], keyCode: HIDUsage.backspace)
                var approve1 = modeDraft.key(for: .approve)
                var reject1 = modeDraft.key(for: .reject)
                // 一版曾出厂为 ⌘↵/⌘⌫：与当前出厂一致（仍为默认文案且无宏）时升到裸键 ↵/⌫。
                if approve1.shortcut == oldDefaultApprove,
                   reject1.shortcut == oldDefaultReject,
                   approve1.description == "Accept",
                   reject1.description == "Reject",
                   approve1.macro.isEmpty,
                   reject1.macro.isEmpty
                {
                    let t = AhaKeyModeDraft.default(for: .mode1)
                    approve1.shortcut = t.key(for: .approve).shortcut
                    modeDraft.updateKey(approve1)
                    reject1.shortcut = t.key(for: .reject).shortcut
                    reject1.macro = t.key(for: .reject).macro
                    modeDraft.updateKey(reject1)
                }

                reject1 = modeDraft.key(for: .reject)
                let defaultCursorReject = AhaKeyModeDraft.default(for: .mode1).key(for: .reject)
                if !reject1.macro.isEmpty,
                   reject1.shortcut == defaultCursorReject.shortcut
                {
                    reject1.macro = []
                    modeDraft.updateKey(reject1)
                }
            }

            next.updateMode(modeDraft)
        }

        return next
    }
}
