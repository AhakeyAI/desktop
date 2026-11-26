import AhaKeyConfigShared
import SwiftUI

struct StudioHookVerificationView: View {
    let verification: AgentManager.HookVerification?
    let configurationPaths: [String]
    let needsCodexRestart: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            statusLine(verification?.configurationChecked == true, "配置已写入并核对", "检测到配置，等待核对")
            statusLine(verification?.entryChecked == true, "Hook 入口自检通过", "Hook 入口待检查")
            statusLine(verification?.eventReceived == true, "已收到真实 Hook 回调", "等待真实 Hook 回调")
            let hosts = HookExecutionHost.allCases.filter { verification?.hosts.contains($0) == true }
            if !hosts.isEmpty {
                Text(NSLocalizedString("回调来源", comment: "") + " · " + hosts.map(hostTitle).joined(separator: "、"))
            }
            if needsCodexRestart {
                Text(AgentManager.codexHookRestartHint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(copied ? "已复制" : "复制恢复命令") {
                    let clipboard = NSPasteboard.general
                    clipboard.clearContents()
                    copied = clipboard.setString(AgentManager.codexHookResumeCommand, forType: .string)
                }
                .buttonStyle(.link)
                .help("适用于 Codex CLI。运行后在列表中选择要继续的会话。")
            }
            Text("在要验证的应用中开启一个新会话。使用独立配置目录时，请核对该应用加载的是下列配置。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(configurationPaths, id: \.self) { path in
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .font(.caption)
    }

    private func statusLine(_ confirmed: Bool, _ success: LocalizedStringKey, _ pending: LocalizedStringKey) -> some View {
        Label(confirmed ? success : pending, systemImage: confirmed ? "checkmark.circle" : "clock")
            .foregroundStyle(confirmed ? Color.primary : Color.secondary)
    }

    private func hostTitle(_ host: HookExecutionHost) -> String {
        switch host {
        case .orca: return "Orca"
        case .lobeHub: return "LobeHub"
        case .t3Code: return "T3 Code"
        case .codexDesktop: return "Codex Desktop"
        case .claudeDesktop: return "Claude Desktop"
        case .terminal: return NSLocalizedString("终端", comment: "")
        case .unidentified: return NSLocalizedString("本机未识别宿主", comment: "")
        }
    }
}
