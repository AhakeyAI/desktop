import SwiftUI
import VibeBar

/// 灵动岛 Settings 根容器：常驻岛 / 展开岛 / 通用 + 子路由（空壳保留占位）。
struct AhaKeyDynamicIslandSettingsPane: View {
    @ObservedObject var state: VibeBarState
    @Binding var route: AhaKeyDynamicIslandSettingsRoute
    let brandName: String

    @State private var configSection: AhaKeyDynamicIslandConfigSection = .notchConfig
    @AppStorage(VibeBarIslandSoundSettings.mutedDefaultsKey) private var isIslandSoundMuted = false
    @AppStorage(VibeBarIslandAppearanceSettings.hoverExpandKey) private var hoverExpandEnabled = true

    var body: some View {
        Group {
            switch route {
            case .root:
                rootContent
            case .componentLibrary:
                AhaKeyIslandComponentLibraryPane(
                    state: state,
                    route: $route,
                    brandName: brandName,
                    onBack: popToRoot
                )
            case .keyPadSettings:
                AhaKeyKeyPadSettingsPane(
                    state: state,
                    brandName: brandName,
                    onBack: { route = .componentLibrary }
                )
            case .oledPetSettings:
                AhaKeyOledPetSettingsPane(
                    state: state,
                    brandName: brandName,
                    onBack: { route = .componentLibrary }
                )
            case .agentSessions:
                agentSessionsPane
            case .display:
                displayPane
            case .sound:
                soundPane
            }
        }
    }

    private var rootContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                AhaKeyDynamicIslandSectionPicker(selection: $configSection)

                switch configSection {
                case .notchConfig:
                    AhaKeyIslandStatusConfigPane(state: state, route: $route, brandName: brandName)
                case .islandConfig:
                    AhaKeyIslandBehaviorConfigPane(state: state, route: $route, brandName: brandName)
                case .general:
                    AhaKeyIslandGeneralConfigPane(route: $route)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .featureCoachTip(.islandFirst, isActive: true, alignment: .topTrailing)
    }

    /// 显示子页：保留空壳，后续接信息密度等能力。
    private var displayPane: some View {
        AhakeyWrappedSettingsPane(
            title: "显示",
            brandName: brandName,
            onBack: popToRoot
        ) {
            AhakeySettingsCard(sectionTitle: "即将推出") {
                placeholderRow(
                    title: "信息密度",
                    detail: "紧凑 / 标准 / 详细等布局选项，后续版本可配置。"
                )
                AhakeySettingsCardDivider()
                placeholderRow(
                    title: "展开面板细节",
                    detail: "模块间距、字号与对齐等显示微调入口占位。"
                )
            }

            AhakeySettingsCard(sectionTitle: "临时调试") {
                AhakeySettingsToggleRow(
                    title: "悬停时展开",
                    subtitle: "正式入口在「展开岛 → 交互」；此处仅作联调占位。",
                    isOn: $hoverExpandEnabled
                )
                .onChange(of: hoverExpandEnabled) { _ in
                    NotificationCenter.default.post(
                        name: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification,
                        object: nil
                    )
                }
            }
        }
    }

    /// 声音详情子页：主开关在「通用」；此处保留更多选项空壳。
    private var soundPane: some View {
        AhakeyWrappedSettingsPane(
            title: "声音详情",
            brandName: brandName,
            onBack: popToRoot
        ) {
            AhakeySettingsCard(sectionTitle: "提示音") {
                AhakeySettingsToggleRow(
                    title: "展开/收起音效",
                    subtitle: "与「通用 → 声音」同步",
                    isOn: Binding(
                        get: { !isIslandSoundMuted },
                        set: { enabled in
                            isIslandSoundMuted = !enabled
                            if enabled {
                                VibeBarIslandSoundSettings.playInteractionIfEnabled()
                            }
                        }
                    )
                )
            }

            AhakeySettingsCard(sectionTitle: "即将推出") {
                placeholderRow(
                    title: "自定义提示音",
                    detail: "按交互类型选择系统音或自定义文件。"
                )
                AhakeySettingsCardDivider()
                placeholderRow(
                    title: "音量与均衡",
                    detail: "独立于系统音量的灵动岛提示音调节。"
                )
            }
        }
    }

    private var agentSessionsPane: some View {
        AhakeyWrappedSettingsPane(
            title: "Agent 会话",
            brandName: brandName,
            onBack: popToRoot
        ) {
            AhakeySettingsCard(sectionTitle: "即将推出") {
                placeholderRow(
                    title: "会话列表规则",
                    detail: "按 Agent / 状态筛选、排序与聚合展示，后续版本接入。"
                )
            }

            AhakeySettingsCard(sectionTitle: "预览占位") {
                sessionPreviewRow(title: "Claude · editing", badge: "运行中", tint: .orange)
                AhakeySettingsCardDivider()
                sessionPreviewRow(title: "Cursor · composer", badge: "等待", tint: AhakeySettingsTheme.accentBlue)
                AhakeySettingsCardDivider()
                sessionPreviewRow(title: "Codex · terminal", badge: "空闲", tint: AhakeySettingsTheme.secondaryText)
            }

            AhakeySettingsCard(sectionTitle: "右槽计数（调试）") {
                Stepper(value: Binding(
                    get: { VibeBarIslandAppearanceSettings.previewSessionCount },
                    set: { VibeBarIslandAppearanceSettings.previewSessionCount = $0 }
                ), in: 1...9) {
                    HStack {
                        Text("预览会话数")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Spacer()
                        Text("x\(VibeBarIslandAppearanceSettings.previewSessionCount)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 12)
            }
        }
    }

    /// 返回根页时保留当前分段（从哪进子页就回哪）。
    private func popToRoot() {
        route = .root
    }

    private func placeholderRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            Text(detail)
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private func sessionPreviewRow(title: String, badge: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 10, height: 10)
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            Text(badge)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }
}
