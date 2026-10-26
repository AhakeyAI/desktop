import SwiftUI
import AhaKeyConfigShared

/// An explicit diagnostic, not a timer or permission-management toggle.
struct StudioKimiInstanceInspectionView: View {
    @State private var isChecking = false
    @State private var summary: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Kimi Code Desktop 运行检查", comment: "")).font(.headline)
            Button(NSLocalizedString(isChecking ? "检查中…" : "检测运行实例（只读）", comment: "")) { inspect() }
                .disabled(isChecking)
            if let summary { Text(summary).font(.callout).textSelection(.enabled) }
            Text(NSLocalizedString("检测核对本机应用身份，不读取对话或改变权限。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { operation?.cancel() }
    }
    private func inspect() {
        guard !isChecking else { return }
        isChecking = true; summary = nil
        operation = Task { @MainActor in
            defer { isChecking = false; operation = nil }
            let worker = Task.detached(priority: .utility) {
                KimiDesktopInstanceDiscovery.scan(homes: KimiDesktopInstanceDiscovery.configuredHomes())
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            if !result.instances.isEmpty {
                summary = String(format: NSLocalizedString("已核对 %d 个官方运行实例。当前会话权限尚未接管。", comment: ""), result.instances.count)
            } else if result.unverifiedRegistrations > 0 {
                summary = NSLocalizedString("发现运行登记，但尚未完成官方 Code Desktop 身份核对。", comment: "")
            } else {
                summary = NSLocalizedString("当前配置目录中未发现可核对的 Code Desktop 运行实例。", comment: "")
            }
            if result.limitReached {
                summary = (summary ?? "") + "\n" + NSLocalizedString("本次仅检查了部分登记，请缩小配置目录范围后再试。", comment: "")
            }
        }
    }
}
