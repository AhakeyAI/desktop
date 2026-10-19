import SwiftUI
import AhaKeyConfigShared

struct WS3DisplaySettingsView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("显示与灯光", comment: "")).font(.headline)
            Button(bleManager.isReadingWS3Display ? NSLocalizedString("读取中…", comment: "") : NSLocalizedString("读取显示信息（只读）", comment: "")) {
                message = nil
                Task { @MainActor in
                    do { _ = try await bleManager.readWS3DisplayForEditing() }
                    catch { message = KeyboardSettingsFeedback.message(for: error) }
                }
            }.disabled(!bleManager.isConnected || bleManager.isConfigurationOperationInProgress)
            if let snapshot = bleManager.ws3DisplaySnapshot,
               snapshot.generation == bleManager.configurationSnapshot.generation {
                Text(String(format: NSLocalizedString("键盘报告亮度：%@%%", comment: ""), String(snapshot.brightness)))
                Text(String(format: NSLocalizedString("键盘报告有效的自定义素材：%@ / 19", comment: ""), String(snapshot.resources.filter(\.reportsValidUserResource).count)))
            }
            if let message { Text(message).font(.caption).textSelection(.enabled) }
            Text(NSLocalizedString("只读取亮度和资源元数据，不上传、清空或保存。元数据不等于实际图像内容校验。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            Text(NSLocalizedString("画布中的素材和预览仍保留。新固件的显示、灯光保存尚未适配完成，当前不能在此应用。", comment: ""))
            Text(NSLocalizedString("旧版设备继续使用画布原有保存流程。", comment: ""))
            Spacer()
        }.padding()
    }
}
