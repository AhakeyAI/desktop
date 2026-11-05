import SwiftUI

struct StudioLCDForegroundOption: View {
    @ObservedObject var model: StudioLCDInspectorModel
    @ObservedObject private var foregroundSource = TerminalForegroundSource.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
                Toggle(NSLocalizedString("跟随当前终端", comment: ""), isOn: Binding(
                    get: { model.followsTerminal }, set: { model.chooseFollow($0) }))
                    .toggleStyle(.checkbox).font(.callout)
                    .help(NSLocalizedString("识别 Terminal 或 iTerm 当前窗口与标签；无法唯一匹配会话时不突出显示。", comment: ""))
                Text(NSLocalizedString("优先显示当前聚焦的会话", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                if model.followsTerminal {
                    if model.followDraft == true {
                        Text(NSLocalizedString("写入后启用跟随", comment: "")).font(.caption).foregroundStyle(.secondary)
                    } else if foregroundSource.status != .following {
                        HStack {
                            Text(foregroundHint).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if foregroundSource.canRequestAuthorization {
                                Button(NSLocalizedString("允许读取终端状态", comment: "")) { Task { await foregroundSource.authorize() } }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
            }
    }
    private var foregroundHint: String {
        switch foregroundSource.status {
        case .accessibility: return NSLocalizedString("需要辅助功能权限", comment: "")
        case .automation: return NSLocalizedString("需要终端读取权限", comment: "")
        case .waiting, .disabled: return NSLocalizedString("切换到 Terminal 或 iTerm 后跟随", comment: "")
        case .unavailable: return NSLocalizedString("暂未识别到当前会话", comment: "")
        case .following: return ""
        }
    }
}
