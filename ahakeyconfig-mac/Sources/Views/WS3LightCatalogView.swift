import SwiftUI
import AhaKeyConfigShared

struct WS3LightCatalogView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @State private var message: String?
    @State private var readID: UUID?
    @State private var readGeneration: UInt64?
    @State private var readTask: Task<Void, Never>?

    private var catalog: WS3LightCatalogSnapshot? {
        guard bleManager.canEditWS3Display, let catalog = bleManager.ws3LightCatalogSnapshot,
              catalog.generation == bleManager.configurationSnapshot.generation else { return nil }
        return catalog
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("四模式灯效总览", comment: "")).font(.headline)
            Button(readID == nil ? NSLocalizedString("读取全部 36 项灯效（只读）", comment: "") : NSLocalizedString("正在读取灯效总览…", comment: "")) { read() }
                .disabled(!bleManager.canEditWS3Display || bleManager.isConfigurationOperationInProgress)
            if let catalog {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text(NSLocalizedString("工作状态", comment: ""))
                        ForEach(AhaKeyModeSlot.allCases) { mode in Text(mode.name) }
                    }.font(.caption.bold())
                    ForEach(IDEState.allCases) { state in
                        GridRow {
                            Text(state.label)
                            ForEach(AhaKeyModeSlot.allCases) { mode in
                                if let light = catalog.light(mode: UInt8(mode.rawValue), state: state.rawValue) {
                                    Text(effectTitle(light.effect))
                                        .foregroundStyle(light.effect <= 16 ? Color.primary : Color.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityLabel(mode.name + " · " + state.label + "：" + effectTitle(light.effect))
                                }
                            }
                        }.font(.caption)
                    }
                }
            }
            Text(NSLocalizedString("只读取键盘保存值，不切换工作模式、不播放灯效，也不覆盖草稿。未知灯效保持只读。", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).textSelection(.enabled) }
        }
        .onChange(of: bleManager.configurationSnapshot.generation) { _ in
            if readGeneration != bleManager.configurationSnapshot.generation { revoke() }
        }
        .onChange(of: bleManager.canEditWS3Display) { ready in if !ready { message = nil } }
        .onDisappear { revoke() }
    }

    private func effectTitle(_ effect: UInt8) -> String {
        LightEffectStyle(firmwareIndex: effect)?.title ??
            String(format: NSLocalizedString("未知灯效 %@（只读）", comment: ""), String(effect))
    }

    private func revoke() {
        readID = nil; readGeneration = nil; readTask?.cancel(); readTask = nil; message = nil
    }

    private func read() {
        guard bleManager.canEditWS3Display, !bleManager.isConfigurationOperationInProgress else { return }
        let id = UUID(), generation = bleManager.configurationSnapshot.generation
        readID = id; readGeneration = generation; message = nil
        readTask = Task { @MainActor in
            defer { if readID == id { readID = nil; readTask = nil } }
            do {
                _ = try await bleManager.readWS3LightCatalogForEditing()
                guard readID == id, generation == bleManager.configurationSnapshot.generation else { return }
                message = NSLocalizedString("已读取四个模式共 36 项灯效，未写入键盘。", comment: "")
            } catch {
                guard readID == id, generation == bleManager.configurationSnapshot.generation else { return }
                message = KeyboardSettingsFeedback.message(for: error)
            }
        }
    }
}
