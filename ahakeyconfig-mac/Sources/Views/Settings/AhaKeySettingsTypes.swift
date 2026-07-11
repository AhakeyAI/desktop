import Foundation

enum AhaKeySettingsTab: String, CaseIterable, Identifiable, Hashable {
    case hardware
    case voiceInput
    case agent
    case dynamicIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dynamicIsland: "灵动岛"
        case .hardware: "硬件设备"
        case .voiceInput: "语音输入"
        case .agent: "Agent"
        }
    }

    var icon: String {
        switch self {
        case .dynamicIsland: "sparkles.rectangle.stack"
        case .hardware: "keyboard"
        case .voiceInput: "mic.fill"
        case .agent: "brain.head.profile"
        }
    }
}

/// 灵动岛 Tab 三分段：常驻 / 展开 / 通用。
enum AhaKeyDynamicIslandConfigSection: String, CaseIterable, Identifiable, Hashable {
    case notchConfig
    case islandConfig
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchConfig: "常驻岛"
        case .islandConfig: "展开岛"
        case .general: "通用"
        }
    }

    var subtitle: String {
        switch self {
        case .notchConfig: "静息态胶囊"
        case .islandConfig: "悬停展开面板"
        case .general: "系统与声音"
        }
    }
}

/// 语音输入 Tab 三分段：历史 / 词典 / 通用。
enum AhaKeyVoiceInputConfigSection: String, CaseIterable, Identifiable, Hashable {
    case history
    case dictionary
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "历史记录"
        case .dictionary: "词典"
        case .general: "通用设置"
        }
    }

    var subtitle: String {
        switch self {
        case .history: "口述与转写"
        case .dictionary: "替换词条"
        case .general: "试录与权限"
        }
    }
}

/// 用户中心左侧导航分段。
enum AhaKeyUserCenterSection: String, CaseIterable, Identifiable, Hashable {
    case account
    case settings
    case usageData
    case about
    case help
    case releaseNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "用户中心"
        case .settings: "设置"
        case .usageData: "使用数据"
        case .about: "关于我们"
        case .help: "帮助中心"
        case .releaseNotes: "版本说明"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .settings: "gearshape"
        case .usageData: "chart.bar.doc.horizontal"
        case .about: "info.circle"
        case .help: "book"
        case .releaseNotes: "doc.text"
        }
    }

    var showsExternalLinkHint: Bool {
        self == .help || self == .releaseNotes
    }

    static let primarySections: [AhaKeyUserCenterSection] = [.account, .settings, .usageData, .about]
    static let secondarySections: [AhaKeyUserCenterSection] = [.help, .releaseNotes]
}

/// Agent Tab 三分段：助手 / 联动 / 设置。
enum AhaKeyAgentConfigSection: String, CaseIterable, Identifiable, Hashable {
    case assistant
    case status
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: "助手"
        case .status: "联动"
        case .general: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .assistant: "对话下达"
        case .status: "启用与蓝牙"
        case .general: "皮肤与图标"
        }
    }
}

enum AhaKeyDynamicIslandSettingsRoute: String, Hashable, Identifiable, CaseIterable {
    case root
    case componentLibrary
    case keyPadSettings
    case oledPetSettings
    case agentSessions
    case display
    case sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .root: "灵动岛"
        case .componentLibrary: "组件库"
        case .keyPadSettings: "四键键帽"
        case .oledPetSettings: "OLED Pet"
        case .agentSessions: "Agent 会话"
        case .display: "显示"
        case .sound: "声音详情"
        }
    }

    var detail: String? {
        switch self {
        case .componentLibrary: "管理展开岛模块显隐与顺序"
        case .keyPadSettings: "外观、显隐与动作映射"
        case .oledPetSettings: "信息层、尺寸、动画与素材"
        case .agentSessions: "会话列表规则（占位）"
        case .display: "信息密度等（占位）"
        case .sound: "更多声音选项（占位）"
        case .root: nil
        }
    }

    var icon: String {
        switch self {
        case .root: "sparkles.rectangle.stack"
        case .componentLibrary: "square.stack.3d.up"
        case .keyPadSettings: "keyboard"
        case .oledPetSettings: "rectangle.inset.filled"
        case .agentSessions: "list.bullet.rectangle"
        case .display: "textformat.size"
        case .sound: "speaker.wave.2.fill"
        }
    }

    var hasDetailSettings: Bool {
        self == .keyPadSettings || self == .oledPetSettings
    }
}
