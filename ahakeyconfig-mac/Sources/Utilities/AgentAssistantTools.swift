import Foundation

enum AgentAssistantIntent: String, CaseIterable, Identifiable {
    case status
    case help
    case enableLinkage
    case installCursorHook
    case installClaudeHook
    case installCodexHook
    case installKimiHook
    case giveBluetoothToAgent
    case giveBluetoothToStudio
    case openMyDevices
    case openApproveKey
    case openVoiceKey
    case openHardwareMode
    case openStatusSection
    case installAgent
    case startAgent
    case stopAgent

    var id: String { rawValue }

    var chipTitle: String {
        switch self {
        case .status: "查联动状态"
        case .help: "能做什么"
        case .enableLinkage: "一键启用联动"
        case .installCursorHook: "装 Cursor Hook"
        case .installClaudeHook: "装 Claude Hook"
        case .installCodexHook: "装 Codex Hook"
        case .installKimiHook: "装 Kimi Hook"
        case .giveBluetoothToAgent: "蓝牙交给 Agent"
        case .giveBluetoothToStudio: "蓝牙交回 Studio"
        case .openMyDevices: "打开我的设备"
        case .openApproveKey: "去改批准键"
        case .openVoiceKey: "去改语音键"
        case .openHardwareMode: "去切 Mode"
        case .openStatusSection: "打开联动页"
        case .installAgent: "安装守护进程"
        case .startAgent: "启动 Agent"
        case .stopAgent: "停止 Agent"
        }
    }

    /// 点芯片时写入对话的自然语言（等同用户口述）。
    var naturalPhrase: String {
        switch self {
        case .status: "帮我查一下联动状态"
        case .help: "你能做什么"
        case .enableLinkage: "一键启用联动"
        case .installCursorHook: "帮我装一下 Cursor 的 hook"
        case .installClaudeHook: "帮我装一下 Claude 的 hook"
        case .installCodexHook: "帮我装一下 Codex 的 hook"
        case .installKimiHook: "帮我装一下 Kimi 的 hook"
        case .giveBluetoothToAgent: "把蓝牙交给 Agent"
        case .giveBluetoothToStudio: "把蓝牙交回 Studio"
        case .openMyDevices: "打开我的设备"
        case .openApproveKey: "打开批准键设置"
        case .openVoiceKey: "打开语音键设置"
        case .openHardwareMode: "去硬件切换 Mode"
        case .openStatusSection: "打开联动页"
        case .installAgent: "帮我安装守护进程"
        case .startAgent: "启动 Agent"
        case .stopAgent: "停止 Agent"
        }
    }

    static let quickChips: [AgentAssistantIntent] = [
        .status, .enableLinkage, .giveBluetoothToAgent, .openStatusSection
    ]
}

@MainActor
enum AgentAssistantRouter {
    /// 解析用户输入为有序意图列表（支持复合句）。
    static func resolveAll(_ raw: String) -> [AgentAssistantIntent] {
        let text = normalize(raw)
        guard !text.isEmpty else { return [] }

        if matchesHelp(text) {
            return [.help]
        }

        if matchesEnableLinkage(text) {
            return [.enableLinkage]
        }

        var intents: [AgentAssistantIntent] = []
        var remaining = text

        // 复合：启动 + 交蓝牙 → 视为一键启用
        if matchesStart(remaining), matchesGiveBluetoothToAgent(remaining) {
            return [.enableLinkage]
        }

        func take(_ intent: AgentAssistantIntent, when match: (String) -> Bool) {
            guard match(remaining) else { return }
            if !intents.contains(intent) {
                intents.append(intent)
            }
        }

        take(.installCursorHook, when: matchesInstallCursor)
        take(.installClaudeHook, when: matchesInstallClaude)
        take(.installCodexHook, when: matchesInstallCodex)
        take(.installKimiHook, when: matchesInstallKimi)
        take(.giveBluetoothToStudio, when: matchesGiveBluetoothToStudio)
        take(.giveBluetoothToAgent, when: matchesGiveBluetoothToAgent)
        take(.installAgent, when: matchesInstallAgent)
        take(.startAgent, when: matchesStart)
        take(.stopAgent, when: matchesStop)
        take(.openMyDevices, when: matchesOpenMyDevices)
        take(.openApproveKey, when: matchesOpenApprove)
        take(.openVoiceKey, when: matchesOpenVoice)
        take(.openHardwareMode, when: matchesOpenMode)
        take(.openStatusSection, when: matchesOpenStatusSection)
        take(.status, when: matchesStatus)

        // 泛化「安装 hook」且未点名 IDE → Cursor
        if intents.isEmpty, matchesGenericInstallHook(text) {
            intents.append(.installCursorHook)
        }

        return intents
    }

    static func resolve(_ raw: String) -> AgentAssistantIntent? {
        resolveAll(raw).first
    }

    static func helpText() -> String {
        """
        我是设备联动管家，可以用自然语言让我做事（本版不接云端大模型），例如：
        · 「一键启用联动」（安装/启动守护进程并交蓝牙）
        · 「帮我查一下联动状态」
        · 「装一下 Cursor / Claude / Codex / Kimi 的 hook」
        · 「把蓝牙交给 Agent」或「交回 Studio」
        · 「打开联动页」「打开我的设备」「打开批准键 / 语音键」
        也可以说复合句，比如「启动 Agent 并把蓝牙交给它」。
        """
    }

    // MARK: - Normalize & matchers

    private static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "　", with: " ")
    }

    private static func matchesHelp(_ t: String) -> Bool {
        t == "help" || t == "?" || t == "？"
            || t.contains("能做什么") || t.contains("你会什么") || t.contains("怎么用")
            || t.contains("帮助") || t.contains("有哪些")
    }

    private static func matchesEnableLinkage(_ t: String) -> Bool {
        t.contains("一键启用")
            || (t.contains("启用") && t.contains("联动"))
            || t.contains("开启联动")
            || t.contains("启用 agent")
    }

    private static func matchesStatus(_ t: String) -> Bool {
        if t.contains("状态与联动") || t.contains("状态页") || t.contains("联动页") { return false }
        if matchesEnableLinkage(t) { return false }
        return t.contains("状态") || t.contains("status") || t.contains("好了吗")
            || t.contains("连上了吗")
            || (t.contains("联动") && (t.contains("查") || t.contains("看") || t.contains("怎么样")))
            || t.contains("检查") || t.contains("诊断一下")
    }

    private static func matchesInstallCursor(_ t: String) -> Bool {
        t.contains("cursor") && (t.contains("hook") || t.contains("钩子") || t.contains("安装") || t.contains("装"))
    }

    private static func matchesInstallClaude(_ t: String) -> Bool {
        t.contains("claude") && (t.contains("hook") || t.contains("钩子") || t.contains("安装") || t.contains("装"))
    }

    private static func matchesInstallCodex(_ t: String) -> Bool {
        t.contains("codex") && (t.contains("hook") || t.contains("钩子") || t.contains("安装") || t.contains("装"))
    }

    private static func matchesInstallKimi(_ t: String) -> Bool {
        (t.contains("kimi") || t.contains("kimicode"))
            && (t.contains("hook") || t.contains("钩子") || t.contains("安装") || t.contains("装"))
    }

    private static func matchesGenericInstallHook(_ t: String) -> Bool {
        (t.contains("hook") || t.contains("钩子")) && (t.contains("安装") || t.contains("装"))
    }

    private static func matchesGiveBluetoothToAgent(_ t: String) -> Bool {
        guard t.contains("蓝牙") || t.contains("ble") || t.contains("占用") else { return false }
        if t.contains("studio") || t.contains("交回") || t.contains("还给") { return false }
        return t.contains("agent") || t.contains("交给") || t.contains("给 agent") || t.contains("联动")
    }

    private static func matchesGiveBluetoothToStudio(_ t: String) -> Bool {
        (t.contains("蓝牙") || t.contains("ble") || t.contains("占用"))
            && (t.contains("studio") || t.contains("交回") || t.contains("还给") || t.contains("配置"))
    }

    private static func matchesInstallAgent(_ t: String) -> Bool {
        (t.contains("安装") || t.contains("装一下"))
            && (t.contains("守护") || t.contains("daemon") || (t.contains("agent") && !t.contains("hook")))
    }

    private static func matchesStart(_ t: String) -> Bool {
        (t.contains("启动") || t.contains("开启") || t.contains("start") || t.contains("跑起来"))
            && (t.contains("agent") || t.contains("守护") || t.contains("联动"))
    }

    private static func matchesStop(_ t: String) -> Bool {
        (t.contains("停止") || t.contains("关闭") || t.contains("stop") || t.contains("关掉"))
            && (t.contains("agent") || t.contains("守护") || t.contains("联动"))
    }

    private static func matchesOpenMyDevices(_ t: String) -> Bool {
        t.contains("我的设备") || t.contains("设备管理") || t.contains("设备信息") || t.contains("设备详情")
    }

    private static func matchesOpenApprove(_ t: String) -> Bool {
        t.contains("批准键") || t.contains("approve")
            || (t.contains("批准") && (t.contains("键") || t.contains("设置") || t.contains("改") || t.contains("打开")))
    }

    private static func matchesOpenVoice(_ t: String) -> Bool {
        t.contains("语音键") || (t.contains("voice") && (t.contains("键") || t.contains("key")))
            || (t.contains("语音") && (t.contains("键") || t.contains("设置") || t.contains("改")))
    }

    private static func matchesOpenMode(_ t: String) -> Bool {
        (t.contains("mode") || t.contains("模式"))
            && (t.contains("切") || t.contains("换") || t.contains("打开") || t.contains("去") || t.contains("硬件"))
    }

    private static func matchesOpenStatusSection(_ t: String) -> Bool {
        t.contains("状态与联动") || t.contains("状态页") || t.contains("联动页")
            || (t.contains("打开") && t.contains("联动") && !t.contains("启用") && !t.contains("查"))
            || (t.contains("打开") && t.contains("状态") && !t.contains("查") && !t.contains("好了"))
    }
}

@MainActor
struct AgentAssistantTools {
    let bleManager: AhaKeyBLEManager
    private let agent = AgentManager.shared

    func run(_ intent: AgentAssistantIntent) -> String {
        agent.refresh()
        switch intent {
        case .status:
            return statusSummary()
        case .help:
            return AgentAssistantRouter.helpText()
        case .enableLinkage:
            return enableLinkage()
        case .installCursorHook:
            agent.installCursorHooksOnly()
            return "已尝试安装 Cursor Hooks。可到「联动」页看徽章是否变绿；也可以说「帮我查一下联动状态」。"
        case .installClaudeHook:
            agent.installClaudeHooksOnly()
            return "已尝试安装 Claude Hooks。可到「联动」页确认。"
        case .installCodexHook:
            agent.installCodexHooksOnly()
            return "已尝试安装 Codex Hooks。可到「联动」页确认。"
        case .installKimiHook:
            agent.installKimiHooksOnly()
            return "已尝试安装 Kimi Hooks。可到「联动」页确认。"
        case .giveBluetoothToAgent:
            if !agent.isInstalled {
                return "还没装守护进程。可以说「一键启用联动」，装好后再把蓝牙交给它。"
            }
            agent.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
            return "已将蓝牙占用切换为 Agent。Studio 会释放连接，由 Agent 接管灯条与拨杆联动。"
        case .giveBluetoothToStudio:
            agent.setBluetoothConnectionOwner(.ahaKeyStudio, bleManager: bleManager)
            return "已将蓝牙交回 AhaKey Studio，可以去「硬件设备」改键或同步配置。"
        case .openMyDevices:
            StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
            return "已打开「我的设备」详情，可在那里改名、看电量与系统控制。"
        case .openApproveKey:
            openHardware(part: .key2)
            return "已打开硬件设备 · Key 2（批准）。请在右侧 Inspector 修改绑定。"
        case .openVoiceKey:
            openHardware(part: .key1)
            return "已打开硬件设备 · Key 1（语音）。请在右侧 Inspector 修改绑定。"
        case .openHardwareMode:
            StudioNavigationRouter.shared.selectSettingsTab(.hardware)
            return "已打开「硬件设备」。请在画布下方的 Agent 模式分段切换 Claude / Cursor / Codex / custom。"
        case .openStatusSection:
            StudioNavigationRouter.shared.selectAgentSection(.status)
            return "已切换到「联动」页，可在那里一键启用、切蓝牙与管理 Hook。"
        case .installAgent:
            if agent.isInstalled {
                return "守护进程已经安装。可以说「一键启用联动」或「把蓝牙交给 Agent」。"
            }
            agent.install()
            return "已开始安装并启用 Agent（含 Hook）。稍候可以说「查一下联动状态」确认。"
        case .startAgent:
            if !agent.isInstalled {
                agent.install()
                return "检测到未安装，已开始安装并启用 Agent（含 Hook）。装好后会尝试启动。"
            }
            agent.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
            agent.start()
            return "已请求启动 Agent，并尽量把蓝牙交给它。可以说「查一下联动状态」确认是否在跑。"
        case .stopAgent:
            agent.stop()
            return "已请求停止 Agent 守护进程。若要改键，可再说「把蓝牙交回 Studio」。"
        }
    }

    private func enableLinkage() -> String {
        if !agent.isInstalled {
            agent.install()
            return "已开始安装并启用联动（守护进程 + Hook）。装好后会尽量把蓝牙交给 Agent；可以说「查一下联动状态」确认。"
        }
        agent.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        if !agent.isRunning {
            agent.start()
        }
        return "已请求启用联动：蓝牙交给 Agent，并确保守护进程在跑。可以说「查一下联动状态」确认。"
    }

    /// 按序执行多个意图，合并回复。
    func runAll(_ intents: [AgentAssistantIntent]) -> String {
        guard !intents.isEmpty else {
            return """
            还没听懂。可以说「你能做什么」，或试试：「一键启用联动」「帮我查一下联动状态」「把蓝牙交给 Agent」。
            """
        }
        if intents.count == 1 {
            return run(intents[0])
        }
        return intents.enumerated().map { index, intent in
            "\(index + 1). \(run(intent))"
        }.joined(separator: "\n")
    }

    private func statusSummary() -> String {
        let installed = agent.isInstalled ? "已安装" : "未安装"
        let running = agent.isRunning ? "运行中" : "未运行"
        let ble = agent.isAgentBLEConnected
            ? "Agent 已连键盘"
            : (bleManager.isConnected ? "Studio 正连着键盘" : "键盘未连接")
        let owner = agent.bluetoothConnectionOwner.title
        let hooks = [
            agent.claudeHooksInstalled ? "Claude" : nil,
            agent.cursorHooksInstalled ? "Cursor" : nil,
            agent.codexHooksInstalled ? "Codex" : nil,
            agent.kimiHooksInstalled ? "Kimi" : nil,
        ].compactMap { $0 }
        let hookLine = hooks.isEmpty ? "尚未安装任何 Hook" : "Hook：\(hooks.joined(separator: " · "))"
        let switchTitle = bleManager.switchState == 0 ? "自动批准" : "手动批准"

        var tip = ""
        if !agent.isInstalled || !agent.isRunning || agent.bluetoothConnectionOwner != .agentDaemon {
            tip = "\n建议：可以说「一键启用联动」。"
        }

        return """
        守护进程：\(installed)，\(running)。
        蓝牙占用：\(owner)；\(ble)。
        \(hookLine)。
        拨杆语义：\(switchTitle)（只读上报）。\(tip)
        """
    }

    private func openHardware(part: AhaKeyStudioPart) {
        StudioNavigationRouter.shared.selectSettingsTab(.hardware)
        NotificationCenter.default.post(
            name: .ahaKeyStudioSelectPart,
            object: nil,
            userInfo: [StudioNavigationUserInfoKey.part: part.rawValue]
        )
    }
}
