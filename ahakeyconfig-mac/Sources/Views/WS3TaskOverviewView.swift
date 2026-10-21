import SwiftUI
import AhaKeyConfigShared

/// Explicitly refreshed facts and an explicit runtime mode request. ACKs are
/// not presented as visual readback, and no choice is saved/replayed.
struct WS3TaskOverviewView: View {
    @ObservedObject private var agentManager = AgentManager.shared
    @State private var overview: WS3TaskOverview?
    @State private var reading = false
    @State private var failed = false
    @State private var modeDraft: WS3PresentationMode?
    @State private var modeMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("任务概览", comment: "")).font(.headline)
            Text(NSLocalizedString("读取不会切换显示；新的显示方式需要明确选择并应用。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            Button(reading ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取当前任务（只读）", comment: "")) {
                reading = true; failed = false; overview = nil; modeMessage = nil
                Task { @MainActor in
                    defer { reading = false }
                    overview = await agentManager.readTaskOverview()
                    failed = overview == nil
                }
            }.disabled(reading || agentManager.bluetoothConnectionOwner != .agentDaemon || !agentManager.isRunning)
            HStack {
                Picker(NSLocalizedString("显示方式", comment: ""), selection: $modeDraft) {
                    Text(NSLocalizedString("请选择", comment: "")).tag(Optional<WS3PresentationMode>.none)
                    Text(NSLocalizedString("单任务", comment: "")).tag(Optional(WS3PresentationMode.single))
                    Text(NSLocalizedString("多任务", comment: "")).tag(Optional(WS3PresentationMode.multi))
                }
                Button(reading ? NSLocalizedString("处理中…", comment: "") : NSLocalizedString("应用显示方式", comment: "")) {
                    guard let modeDraft else { return }
                    reading = true; failed = false; modeMessage = nil
                    Task { @MainActor in
                        defer { reading = false }
                        do {
                            overview = try await agentManager.applyPresentationMode(modeDraft)
                            modeMessage = NSLocalizedString("显示方式请求已接受；任务从新事件开始同步，实际画面请在键盘上确认。", comment: "")
                        } catch {
                            overview = nil
                            modeMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(reading || overview?.connected != true || overview?.presentationBusy != false ||
                          modeDraft == nil || modeDraft == overview?.requestedMode)
            }.disabled(reading || agentManager.bluetoothConnectionOwner != .agentDaemon || !agentManager.isRunning)
            if let mode = overview?.requestedMode {
                Text(String(format: NSLocalizedString("本次连接已请求：%@", comment: ""), modeLabel(mode)))
            } else {
                Text(NSLocalizedString("当前连接尚未设置显示方式。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if overview?.presentationBusy == true {
                Text(NSLocalizedString("正在应用显示方式，请稍后重新读取。", comment: ""))
            }
            if overview != nil, overview?.presentationBusy == nil {
                Text(NSLocalizedString("后台尚不支持设置显示方式，请更新并重启后台。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let modeMessage { Text(modeMessage).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("仅作用于当前连接，断线后需重新应用。多任务只显示能识别会话的任务；旧版事件请使用单任务模式。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let overview {
                if !overview.connected {
                    Text(NSLocalizedString("键盘未连接，旧任务已清除。", comment: ""))
                } else if overview.tasks.isEmpty {
                    Text(NSLocalizedString("尚未收到可识别的任务会话。", comment: ""))
                }
                ForEach(overview.tasks, id: \.slot) { task in
                    HStack {
                        Text(String(format: NSLocalizedString("位置 %d · %@ · %@", comment: ""),
                                    task.slot + 1, task.client.rawValue.capitalized, String(task.reference.prefix(8))))
                        Spacer()
                        Text(stateLabel(task.state))
                    }
                }
                if overview.unrepresentedEvents > 0 {
                    Text(NSLocalizedString("本次连接有新任务事件因位置占满而未纳入；列表可能不完整。", comment: ""))
                        .foregroundStyle(.orange)
                }
                Text(NSLocalizedString("以上为读取时的快照；任务变化后请重新读取。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if failed {
                Text(NSLocalizedString("未获得任务信息，请确认后台已更新并运行后重试。", comment: ""))
                    .font(.caption).foregroundStyle(.orange)
            }
            if agentManager.bluetoothConnectionOwner != .agentDaemon {
                Text(NSLocalizedString("请先返回日常连接，再读取后台任务。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: agentManager.isAgentBLEConnected) { _ in overview = nil; failed = false; modeMessage = nil }
        .onChange(of: agentManager.bluetoothConnectionOwner) { _ in overview = nil; failed = false; modeMessage = nil }
        .onChange(of: agentManager.isRunning) { _ in overview = nil; failed = false; modeMessage = nil }
    }

    private func modeLabel(_ mode: WS3PresentationMode) -> String {
        NSLocalizedString(mode == .single ? "单任务" : "多任务", comment: "")
    }

    private func stateLabel(_ state: WS3TaskState) -> String {
        switch state {
        case .running: return NSLocalizedString("进行中", comment: "")
        case .waiting: return NSLocalizedString("等待处理", comment: "")
        case .done: return NSLocalizedString("已完成", comment: "")
        }
    }
}
