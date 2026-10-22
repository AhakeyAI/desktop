import SwiftUI
import AhaKeyConfigShared

struct WS3DisplaySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var initialResourceEntry: UInt8 = 0
    @State private var message: String?
    @State private var feedback = WS3DisplaySettingFeedback()
    @State private var operationTask: Task<Void, Never>?

    private var display: WS3DisplaySnapshot? {
        guard let value = bleManager.ws3DisplaySnapshot,
              value.generation == bleManager.configurationSnapshot.generation else { return nil }
        return value
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("显示与灯光", comment: "")).font(.headline)
                WS3TaskOverviewView()
                Divider()
                Button(bleManager.isReadingWS3Display ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取显示信息（只读）", comment: "")) {
                    perform(operation: { try await bleManager.readWS3DisplayForEditing() }) { _ in }
                }.disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
                if let display {
                    Text(String(format: NSLocalizedString("键盘报告亮度：%@%%", comment: ""), String(display.brightness)))
                    Text(String(format: NSLocalizedString("键盘报告有效的自定义素材：%@ / 19", comment: ""), String(display.resources.filter(\.reportsValidUserResource).count)))
                }
                Text(NSLocalizedString("读取不会保存。预览和保存只在本次连接读回确认后开放。素材上传与恢复默认需分别确认，仅作用于所选位置。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                WS3ResourceUploadView(bleManager: bleManager, initialEntry: initialResourceEntry)
                Divider()
                WS3LightCatalogView(bleManager: bleManager)
                Text(NSLocalizedString("灯光修改请在画布选中灯条，点击“修改”后使用底部“写入键盘”。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).textSelection(.enabled) }
                Text(NSLocalizedString("元数据不等于实际图像内容校验。保存失败或取消不代表回滚；重新连接后须重新读取。", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString("旧版设备继续使用画布原有保存流程。", comment: ""))
            }.padding()
        }
        .onChange(of: bleManager.configurationSnapshot.generation) { _ in
            if feedback.connectionChanged(to: bleManager.configurationSnapshot.generation) {
                operationTask?.cancel()
                operationTask = nil
                message = nil
            }
        }
        .onDisappear {
            feedback.invalidate()
            operationTask?.cancel()
            operationTask = nil
            message = nil
        }
    }

    private func perform<Result>(operation: @escaping @MainActor () async throws -> Result,
                                 onSuccess: @escaping @MainActor (Result) -> Void) {
        let currentGeneration = bleManager.configurationSnapshot.generation
        operationTask?.cancel()
        let ticket = feedback.begin(generation: currentGeneration)
        message = nil
        operationTask = Task { @MainActor in
            guard !Task.isCancelled,
                  feedback.start(ticket, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
            do {
                let result = try await operation()
                guard !Task.isCancelled,
                      feedback.succeed(ticket, currentGeneration: bleManager.configurationSnapshot.generation) else { return }
                operationTask = nil
                onSuccess(result)
            } catch {
                let failure = error as? ConfirmedWS3DisplaySetting.Failure
                let mayHaveApplied = failure != .invalidValue && failure != .changedBaseline
                guard feedback.fail(ticket, currentGeneration: bleManager.configurationSnapshot.generation,
                                    mayHaveApplied: mayHaveApplied) else { return }
                operationTask = nil
                message = KeyboardSettingsFeedback.message(for: error)
            }
        }
    }
}
