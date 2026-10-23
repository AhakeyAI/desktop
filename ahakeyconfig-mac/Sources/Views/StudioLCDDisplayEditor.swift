import SwiftUI
import AhaKeyConfigShared

struct StudioLCDDisplayEditor: View {
    @ObservedObject var model: StudioLCDInspectorModel
    @ObservedObject private var foregroundSource = TerminalForegroundSource.shared

    var body: some View {
        StudioInspectorSection {
            HStack {
                Text(NSLocalizedString("展示方式", comment: "")).font(.headline)
                if model.modeDraft != nil { Circle().fill(.orange).frame(width: 6, height: 6) }
                Spacer()
                Text(NSLocalizedString("本次连接", comment: "")).font(.caption2).foregroundStyle(.secondary)
                    .help(NSLocalizedString("断线后需重新应用展示方式。", comment: ""))
            }
            HStack(spacing: 8) {
                modeCard(.single, title: "单任务", detail: "显示最新任务状态", icon: "rectangle")
                modeCard(.multi, title: "多任务", detail: "同时追踪多个会话", icon: "rectangle.split.2x2")
            }
            if model.selectedMode == .multi {
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
                            if foregroundSource.status == .accessibility || foregroundSource.status == .automation {
                                Button(NSLocalizedString("授权", comment: "")) { Task { await foregroundSource.authorize() } }
                                    .buttonStyle(.link).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .disabled(model.isWriting)
    }

    private func modeCard(_ mode: WS3PresentationMode, title: String, detail: String, icon: String) -> some View {
        let selected = model.selectedMode == mode
        return Button { model.chooseMode(mode) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label(NSLocalizedString(title, comment: ""), systemImage: icon).font(.callout.weight(.semibold))
                Text(NSLocalizedString(detail, comment: "")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(9)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? NSLocalizedString("已选中", comment: "") : "")
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

struct StudioLCDTaskList: View {
    @ObservedObject var model: StudioLCDInspectorModel
    let refresh: () -> Void

    var body: some View {
        StudioInspectorSection {
            HStack {
                Text(NSLocalizedString("当前任务", comment: "")).font(.headline)
                if let count = model.overview?.tasks.count { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if model.isReading { ProgressView().controlSize(.small) }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(NSLocalizedString("刷新任务（只读）", comment: ""))
                    .disabled(model.isReading || model.isWriting)
            }
            if let overview = model.overview, !overview.tasks.isEmpty {
                ForEach(overview.tasks, id: \.slot) { task in
                    HStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("%@ · 会话 %d", comment: ""), task.client.rawValue.capitalized, task.slot + 1))
                            .font(.caption)
                        if task.foreground == true {
                            Text(NSLocalizedString("当前", comment: "")).font(.caption2).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        Text(stateLabel(task.state)).font(.caption).foregroundStyle(task.state == .waiting ? Color.orange : .secondary)
                    }
                }
                if overview.unrepresentedEvents > 0 {
                    Text(NSLocalizedString("部分任务未纳入显示", comment: "")).font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(NSLocalizedString(model.isReading ? "正在读取…" : "暂无任务，可刷新查看", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func stateLabel(_ state: WS3TaskState) -> String {
        switch state {
        case .running: return NSLocalizedString("进行中", comment: "")
        case .waiting: return NSLocalizedString("等待处理", comment: "")
        case .done: return NSLocalizedString("已完成", comment: "")
        }
    }
}
