import SwiftUI

struct StudioCodexHookStatusView: View {
    @ObservedObject var agentManager: AgentManager
    @State private var copied = false

    var body: some View {
        Group {
            if let status = agentManager.codexHookInstallationStatus {
                VStack(alignment: .leading, spacing: 5) {
                    statusLine(status.configurationWritten, "配置已写入", "配置待确认")
                    statusLine(status.entryChecked, "Hook 入口自检通过", "Hook 入口待检查")
                    statusLine(status.eventReceived, "已收到真实 Codex Hook，接入已验证", "等待验证")
                    if status.restartRequired {
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
                }
                .font(.caption)
            } else if agentManager.codexHooksInstalled {
                Text("检测到 Codex Hook 配置。点击「修复 Hook」检查入口，等待 Codex 回调。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusLine(_ confirmed: Bool, _ success: LocalizedStringKey, _ pending: LocalizedStringKey) -> some View {
        Label(confirmed ? success : pending, systemImage: confirmed ? "checkmark.circle" : "clock")
            .foregroundStyle(confirmed ? Color.primary : Color.secondary)
    }
}
