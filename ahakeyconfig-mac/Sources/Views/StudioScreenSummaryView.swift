import SwiftUI
import AhaKeyConfigShared

struct StudioScreenSummaryView: View {
    @ObservedObject var model: StudioResourceInspectorModel
    let mode: AhaKeyModeSlot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("屏幕素材", comment: "")).font(.headline)
            if let actual = model.display?.resources.first(where: { $0.id == UInt8(mode.rawValue * 4) }) {
                Text(StudioResourceInspectorModel.title(actual.id))
                Text(actual.reportsValidUserResource ? String(format: NSLocalizedString("自定义素材 · %d 帧", comment: ""), Int(actual.frames)) :
                    NSLocalizedString("默认显示", comment: ""))
            } else {
                Text(NSLocalizedString("点击修改可读取键盘画面，选择图片或 GIF。", comment: ""))
            }
            Text(NSLocalizedString("默认画面最多 8 帧，其他位置最多 12 帧；固定 10 FPS。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 10)
    }
}
