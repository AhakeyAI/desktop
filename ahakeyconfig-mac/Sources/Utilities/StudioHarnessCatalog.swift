import AppKit

enum StudioHookClient: String, CaseIterable, Identifiable {
    case claude, cursor, codex, kimi, workBuddy, copilot, antigravity, openCode, cline, pi, openClaw
    var id: Self { self }

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .kimi: return "Kimi Code"
        case .workBuddy: return "WorkBuddy"
        case .copilot: return "GitHub Copilot CLI"
        case .antigravity: return "Antigravity"
        case .openCode: return "OpenCode V1"
        case .cline: return "Cline CLI"
        case .pi: return "Pi"
        case .openClaw: return "OpenClaw"
        }
    }

    var detection: StudioHarnessCatalog.Entry {
        switch self {
        case .claude: return .init(name, "claude", ["Claude"])
        case .cursor: return .init(name, "cursor-agent", ["Cursor"])
        case .codex: return .init(name, "codex", ["Codex"])
        case .kimi: return .init(name, "kimi", ["Kimi Code"])
        case .workBuddy: return .init(name, "", ["WorkBuddy"], note: "仅同步任务状态")
        case .copilot: return .init(name, "copilot", note: "仅同步任务状态")
        case .antigravity: return .init(name, "agy", ["Antigravity", "Antigravity IDE"], note: "仅同步任务状态")
        case .openCode: return .init(name, "opencode", ["OpenCode"], note: "仅同步任务状态")
        case .cline: return .init(name, "cline", note: "仅同步任务状态")
        case .pi: return .init(name, "pi", note: "仅同步任务状态")
        case .openClaw: return .init(name, "openclaw", note: "仅同步本机 Gateway 的任务状态")
        }
    }
}

enum StudioHarnessCatalog {
    struct Entry: Identifiable {
        let name: String
        let commands: [String]
        let apps: [String]
        let integrationNote: String?
        let iconAsset: String?
        var id: String { name }

        init(_ name: String, _ commands: String = "", _ apps: [String] = [], note: String? = nil,
             iconAsset: String? = nil) {
            self.name = name
            self.commands = commands.split(separator: " ").map(String.init)
            self.apps = apps
            self.integrationNote = note
            self.iconAsset = iconAsset
        }
    }

    static let featured: [Entry] = [
        .init("千问办公", "", ["千问办公", "QwenWork"], note: "企业版通过管理后台配置 HTTP Hook", iconAsset: "qwenWork"),
        .init("豆包工作", "", ["豆包工作", "Doubao Work"], note: "尚未确认本机 Hook 接口", iconAsset: "doubaoWork")
    ]

    static let other: [Entry] = [
        .init("Claude Agent Teams", note: "由 Orca 启用"), .init("DeepSeek Harness", "dsh-tui"),
        .init("ZCode", "zcode", ["ZCode"]), .init("OpenClaude", "openclaude"), .init("Grok", "grok"),
        .init("OpenCode 2", "opencode2", ["OpenCode 2"]), .init("MiMo Code", "mimo"), .init("Ante", "ante"),
        .init("TRAE", "traecli", ["TRAE", "Trae CN"]), .init("Muse", "muse"), .init("Qoder CLI", "qodercli"),
        .init("Qoder CLI 中国版", "qoderclicn"), .init("Pipi", "pipi"), .init("OMP", "omp"),
        .init("Prime Agent", "prime-agent"), .init("Gemini CLI", "gemini"),
        .init("Aider", "aider"), .init("Goose", "goose", ["Goose"]), .init("Amp", "amp"), .init("Kilo", "kilo"),
        .init("Kiro", "kiro-cli", ["Kiro"]), .init("Charm Crush", "crush"), .init("Auggie", "auggie"),
        .init("Autohand Code", "autohand"), .init("Codebuff", "codebuff"),
        .init("Freebuff", "freebuff"), .init("Command Code", "command-code"), .init("Continue", "cn"),
        .init("Droid", "droid"), .init("Mistral Vibe", "vibe"), .init("Qwen Code", "qwen"),
        .init("Rovo Dev", "acli"), .init("Hermes", "hermes"), .init("Devin", "devin"),
        .init("CodeBuddy", "codebuddy", ["CodeBuddy"]), .init("Jcode", "jcode")
    ]

    /// Detection only reads application metadata and executable paths. It never launches a tool.
    @MainActor static func detect() -> Set<String> {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let environmentPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map(String.init).filter { $0.hasPrefix("/") }
        let paths = Set(environmentPath + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                                            home.appendingPathComponent(".local/bin").path,
                                            home.appendingPathComponent(".kimi-code/bin").path])
        let applicationDirectories = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        let appNames = applicationDirectories.flatMap {
            (try? files.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }.filter { $0.pathExtension == "app" }.map { $0.deletingPathExtension().lastPathComponent.lowercased() }
        let running = NSWorkspace.shared.runningApplications.compactMap {
            $0.bundleURL?.deletingPathExtension().lastPathComponent.lowercased()
        }
        let apps = Set(appNames + running)
        let entries = StudioHookClient.allCases.map(\.detection) + featured + other
        return Set(entries.filter { entry in
            entry.apps.contains { apps.contains($0.lowercased()) }
                || entry.commands.contains { command in
                    paths.contains { files.isExecutableFile(atPath: $0 + "/" + command) }
                }
        }.map(\.id))
    }
}
