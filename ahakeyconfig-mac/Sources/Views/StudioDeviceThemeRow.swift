import AhaKeyConfigShared
import SwiftUI

/// One inline setting above the screen editor's Single / Multi mode selector.
struct StudioDeviceThemeRow: View {
    @ObservedObject var model: StudioDeviceThemeModel
    @ObservedObject var ble: AhaKeyBLEManager
    @ObservedObject var session: StudioInspectorSession
    var blocked: Bool

    private var busy: Bool { blocked || model.isBusy || session.isBusy }
    private var connected: Bool { ble.isConnected || AgentManager.shared.isAgentBLEConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker(NSLocalizedString("主题风格", comment: ""), selection: Binding<AhaKeyDeviceTheme?>(
                    get: { model.confirmed },
                    set: { theme in
                        guard let theme, theme != model.confirmed, !busy, connected else { return }
                        model.choose(theme, using: .production(ble: ble, session: session))
                    }
                )) {
                    Text(NSLocalizedString("Light 浅色", comment: "")).tag(Optional(AhaKeyDeviceTheme.light))
                    Text(NSLocalizedString("Dark 深色", comment: "")).tag(Optional(AhaKeyDeviceTheme.dark))
                }
                .pickerStyle(.segmented)
                .font(.body)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(model.confirmed == nil || busy || !connected)
                .help(NSLocalizedString("选择后保存到键盘，读回确认后生效。", comment: ""))
                Spacer(minLength: 0)
                if model.isBusy { ProgressView().controlSize(.small) }
                Button {
                    model.read(deviceID: ble.deviceUUIDForDisplay,
                        using: .production(ble: ble, session: session))
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("重新读取主题", comment: ""))
                .help(NSLocalizedString("重新读取键盘主题", comment: ""))
                .disabled(busy || !connected)
            }
            if model.showsError {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: ble.deviceUUIDForDisplay) { model.invalidateIfChanged(deviceID: $0) }
        .onDisappear { model.cancel() }
    }
}
