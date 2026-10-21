import SwiftUI
import AhaKeyConfigShared

/// An explicitly refreshed observation, not a claim that MULTI is active.
struct WS3TaskOverviewView: View {
    @ObservedObject private var agentManager = AgentManager.shared
    @State private var overview: WS3TaskOverview?
    @State private var reading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("任务概览", comment: "")).font(.headline)
            Text(NSLocalizedString("查看后台收到的会话任务；此处不会开启键盘多任务显示。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            Button(reading ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取当前任务（只读）", comment: "")) {
                reading = true; failed = false; overview = nil
                Task { @MainActor in
                    defer { reading = false }
                    overview = await agentManager.readTaskOverview()
                    failed = overview == nil
                }
            }.disabled(reading || agentManager.bluetoothConnectionOwner != .agentDaemon || !agentManager.isRunning)
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
        .onChange(of: agentManager.isAgentBLEConnected) { _ in overview = nil; failed = false }
        .onChange(of: agentManager.bluetoothConnectionOwner) { _ in overview = nil; failed = false }
        .onChange(of: agentManager.isRunning) { _ in overview = nil; failed = false }
    }

    private func stateLabel(_ state: WS3TaskState) -> String {
        switch state {
        case .running: return NSLocalizedString("进行中", comment: "")
        case .waiting: return NSLocalizedString("等待处理", comment: "")
        case .done: return NSLocalizedString("已完成", comment: "")
        }
    }
}
