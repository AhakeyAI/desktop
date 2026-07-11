import SwiftUI
import VibeBar

/// 组件库：管理展开岛模块显隐与顺序（非常驻岛槽位）。
struct AhaKeyIslandComponentLibraryPane: View {
    @ObservedObject var state: VibeBarState
    @Binding var route: AhaKeyDynamicIslandSettingsRoute
    let brandName: String
    var onBack: () -> Void

    @State private var enabledModules = VibeBarIslandAppearanceSettings.enabledExpandedModules
    @State private var disabledModules = VibeBarIslandAppearanceSettings.disabledExpandedModules
    @State private var statusMessage: String?

    var body: some View {
        AhakeyWrappedSettingsPane(title: "组件库", brandName: brandName, onBack: onBack) {
            VStack(alignment: .leading, spacing: 6) {
                Text("展开岛模块")
                    .font(AhakeySettingsTheme.sectionTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Text("组件库只影响悬停展开后的面板；常驻岛左/右槽请在「常驻岛配置」中设置。四键与 OLED Pet 可点进进一步配置；皮肤与图标在 Agent · 设置。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
            }

            enabledSection
            disabledSection

            Text("OLED Pet 为展开岛核心模块，不可关闭。点进可配置信息层、尺寸、动画与 GIF；皮肤与图标在 Agent · 设置。")
                .font(.caption)
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .featureCoachTip(.islandLibrary, isActive: true, alignment: .topTrailing)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification)) { _ in
            reload()
        }
    }

    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已启用 · 可调整顺序")
                .font(AhakeySettingsTheme.sectionTitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.leading, 4)

            AhakeySettingsCard(sectionTitle: nil) {
                ForEach(Array(enabledModules.enumerated()), id: \.element.id) { index, module in
                    if index > 0 { AhakeySettingsCardDivider() }
                    enabledRow(module, index: index)
                }
            }
        }
    }

    private var disabledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("未启用")
                .font(AhakeySettingsTheme.sectionTitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.leading, 4)

            AhakeySettingsCard(sectionTitle: nil) {
                if disabledModules.isEmpty {
                    Text("所有展开岛模块均已启用")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(disabledModules.enumerated()), id: \.element.id) { index, module in
                        if index > 0 { AhakeySettingsCardDivider() }
                        disabledRow(module)
                    }
                }
            }
        }
    }

    private func detailRoute(for module: VibeBarExpandedModule) -> AhaKeyDynamicIslandSettingsRoute? {
        switch module {
        case .keyPad: return .keyPadSettings
        case .oledPet: return .oledPetSettings
        default: return nil
        }
    }

    private func enabledRow(_ module: VibeBarExpandedModule, index: Int) -> some View {
        let detail = detailRoute(for: module)
        return HStack(spacing: 10) {
            VStack(spacing: 2) {
                Button { move(module, direction: -1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .foregroundStyle(index == 0 ? AhakeySettingsTheme.tertiaryText : AhakeySettingsTheme.secondaryText)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)

                Button { move(module, direction: 1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(index >= enabledModules.count - 1)
                .foregroundStyle(
                    index >= enabledModules.count - 1
                        ? AhakeySettingsTheme.tertiaryText
                        : AhakeySettingsTheme.secondaryText
                )
            }
            .frame(width: 18)

            Button {
                if let detail { route = detail }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: module.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(module.title)
                                .font(AhakeySettingsTheme.rowTitleFont)
                                .foregroundStyle(AhakeySettingsTheme.primaryText)
                            if module == .oledPet {
                                Text("核心")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.orange.opacity(0.95))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                        }
                        Text(module == .oledPet
                             ? "点击配置 · 信息层、尺寸、动画与素材"
                             : (detail == nil ? module.detail : "点击配置 · \(module.detail)"))
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }

                    Spacer(minLength: 0)

                    if detail != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(detail == nil)

            Toggle(
                "",
                isOn: Binding(
                    get: { true },
                    set: { applyEnable(module, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(module == .oledPet)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 10)
    }

    private func disabledRow(_ module: VibeBarExpandedModule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Text(module.detail)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { false },
                    set: { applyEnable(module, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private func applyEnable(_ module: VibeBarExpandedModule, enabled: Bool) {
        let message = VibeBarIslandAppearanceSettings.setExpandedModuleEnabled(module, enabled: enabled)
        statusMessage = message
        reload()
        state.enabledExpandedModules = VibeBarIslandAppearanceSettings.enabledExpandedModules
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
        if let message {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if statusMessage == message { statusMessage = nil }
            }
        }
    }

    private func move(_ module: VibeBarExpandedModule, direction: Int) {
        guard let index = enabledModules.firstIndex(of: module) else { return }
        let target = index + direction
        guard enabledModules.indices.contains(target) else { return }
        var list = enabledModules
        list.swapAt(index, target)
        VibeBarIslandAppearanceSettings.enabledExpandedModules = list
        reload()
        state.enabledExpandedModules = list
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
    }

    private func reload() {
        enabledModules = VibeBarIslandAppearanceSettings.enabledExpandedModules
        disabledModules = VibeBarIslandAppearanceSettings.disabledExpandedModules
    }
}
