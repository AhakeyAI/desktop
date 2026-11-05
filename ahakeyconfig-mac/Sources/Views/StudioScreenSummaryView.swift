import SwiftUI
import AhaKeyConfigShared

struct StudioScreenSummaryView: View {
    @ObservedObject var model: StudioResourceInspectorModel
    @ObservedObject var presentation: StudioLCDInspectorModel
    @ObservedObject var ble: AhaKeyBLEManager
    let mode: AhaKeyModeSlot
    private var actualMode: WS3PresentationMode? {
        guard presentation.overview?.connected == true else { return nil }
        return presentation.overview?.requestedMode ?? .single
    }
    private var shownMode: WS3PresentationMode { actualMode ?? presentation.selectedMode ?? .single }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(NSLocalizedString("展示模式", comment: "")).foregroundStyle(.secondary)
                Spacer()
                Text(actualMode.map { NSLocalizedString($0 == .multi ? "多任务" : "单任务", comment: "") }
                    ?? NSLocalizedString("尚未读取", comment: ""))
            }.font(.caption)
            HStack(alignment: .top, spacing: 8) {
                ForEach(StudioScreenArtworkPlan.entries(mode: mode.rawValue, presentation: shownMode), id: \.self) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.2))
                            if let image = model.drafts[entry]?.thumbnail {
                                Image(nsImage: image).resizable().scaledToFit().padding(3)
                            } else {
                                Image(systemName: "photo").foregroundStyle(.tertiary)
                            }
                        }.frame(height: 45)
                        Text(NSLocalizedString(["进行中", "等待处理", "已完成"][entry >= 16 ? Int(entry - 16) : Int(entry % 4 - 1)], comment: ""))
                            .font(.caption.weight(.medium)).lineLimit(1)
                        Text(status(entry)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(.vertical, 10)
        .task { presentation.read(using: .production(ble: ble)) }
    }
    private func status(_ entry: UInt8) -> String {
        if entry < 16, entry % 4 == 3, model.completedFallbacks.contains(entry - 3), model.screenDirtyEntries.contains(entry - 3) {
            return NSLocalizedString("待完成写入", comment: "")
        }
        if model.dirtyEntries.contains(entry) { return NSLocalizedString("待写入", comment: "") }
        guard let actual = model.display?.resources.first(where: { $0.id == entry }) else {
            return NSLocalizedString("尚未读取", comment: "")
        }
        if actual.reportsValidUserResource {
            return NSLocalizedString(model.drafts[entry]?.thumbnail != nil ? "已设置" : "图片暂不可回看", comment: "")
        }
        return NSLocalizedString(WS3ResourceRestoreCommand.reportsDefault(actual) ? "默认显示" : "待核对", comment: "")
    }
}
