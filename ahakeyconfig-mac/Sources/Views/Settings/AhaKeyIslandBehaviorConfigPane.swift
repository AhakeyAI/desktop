import SwiftUI
import VibeBar

/// 展开岛配置：预览 → 组件库 → 交互 → 个性化；空壳入口保留占位。
struct AhaKeyIslandBehaviorConfigPane: View {
    @ObservedObject var state: VibeBarState
    @Binding var route: AhaKeyDynamicIslandSettingsRoute
    let brandName: String

    @AppStorage(VibeBarIslandAppearanceSettings.hoverExpandKey) private var hoverExpandEnabled = true
    @AppStorage(VibeBarIslandAppearanceSettings.autoCollapseOnLeaveKey) private var autoCollapseOnLeave = true
    @AppStorage(VibeBarIslandAppearanceSettings.hapticFeedbackKey) private var hapticFeedbackEnabled = true

    @State private var islandWidth = VibeBarIslandAppearanceSettings.islandWidth
    @State private var hoverExpandDelayMs = Double(VibeBarIslandAppearanceSettings.hoverExpandDelayMs)
    @State private var showMoreInteraction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("展开岛配置")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("悬停后的展开面板：模块、交互与个性化。系统级选项请到「通用」。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            AhaKeyIslandExpandedPreview(
                state: state,
                islandWidth: islandWidth,
                sectionTitle: "展开岛预览"
            )

            modulesSection
            appearanceSection

            AhaKeySettingsDisclosureSection(
                title: "交互与更多",
                subtitle: "悬停、尺寸与高级功能",
                isExpanded: $showMoreInteraction
            ) {
                interactionSection
                widthHintSection
                placeholderSection
            }
        }
        .onAppear(perform: reloadFromStorage)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification)) { _ in
            reloadFromStorage()
        }
    }

    private var modulesSection: some View {
        AhakeySettingsCard(sectionTitle: "模块") {
            Button { route = .componentLibrary } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("组件库")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text("管理灯带、OLED、四键、底座等模块显隐与顺序")
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private var interactionSection: some View {
        AhakeySettingsCard(sectionTitle: "交互") {
            AhakeySettingsToggleRow(
                title: "悬停时展开",
                subtitle: nil,
                isOn: $hoverExpandEnabled
            )
            .onChange(of: hoverExpandEnabled) { _ in notifyAppearanceChanged() }

            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "鼠标离开时自动收起",
                subtitle: nil,
                isOn: $autoCollapseOnLeave
            )
            .onChange(of: autoCollapseOnLeave) { _ in notifyAppearanceChanged() }

            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "悬停时震动反馈",
                subtitle: nil,
                isOn: $hapticFeedbackEnabled
            )
            .onChange(of: hapticFeedbackEnabled) { _ in notifyAppearanceChanged() }

            AhakeySettingsCardDivider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("悬停展开延迟")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer()
                    Text(String(format: "%.1f s", hoverExpandDelayMs / 1000))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                Slider(value: $hoverExpandDelayMs, in: 100...2000, step: 100)
                    .onChange(of: hoverExpandDelayMs) { value in
                        VibeBarIslandAppearanceSettings.hoverExpandDelayMs = Int(value)
                    }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var widthHintSection: some View {
        AhakeySettingsCard(sectionTitle: "尺寸") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("岛宽度")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("与常驻岛共用，请在「常驻岛」中调整")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                Spacer()
                Text("\(Int(islandWidth)) pt")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var appearanceSection: some View {
        AhakeySettingsCard(sectionTitle: "个性化") {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("焕肤")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text("即将推出")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AhakeySettingsTheme.controlFill))
                    }
                    Text("更换机身材质、灯效主题与键帽风格")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
            .opacity(0.72)
            .accessibilityLabel("焕肤，即将推出")
        }
    }

    private var placeholderSection: some View {
        AhakeySettingsCard(sectionTitle: "高级功能") {
            settingsLinkRow(
                route: .display,
                title: "显示与布局",
                subtitle: "展开面板信息密度等（占位）"
            )
        }
    }

    private func settingsLinkRow(
        route target: AhaKeyDynamicIslandSettingsRoute,
        title: String,
        subtitle: String?
    ) -> some View {
        Button { route = target } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text("占位")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AhakeySettingsTheme.controlFill))
                    }
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func reloadFromStorage() {
        islandWidth = VibeBarIslandAppearanceSettings.islandWidth
        hoverExpandDelayMs = Double(VibeBarIslandAppearanceSettings.hoverExpandDelayMs)
        state.islandWidth = islandWidth
        state.enabledExpandedModules = VibeBarIslandAppearanceSettings.enabledExpandedModules
    }

    private func notifyAppearanceChanged() {
        NotificationCenter.default.post(
            name: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification,
            object: nil
        )
    }
}
