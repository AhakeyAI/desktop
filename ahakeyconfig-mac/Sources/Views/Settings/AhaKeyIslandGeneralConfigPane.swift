import SwiftUI
import VibeBar

/// 灵动岛「通用」：应用级设置（登录 / Dock / 显示器 / 语言 / 声音 / 通知策略）。
struct AhaKeyIslandGeneralConfigPane: View {
    @Binding var route: AhaKeyDynamicIslandSettingsRoute

    @AppStorage(VibeBarIslandSoundSettings.mutedDefaultsKey) private var isIslandSoundMuted = false
    @AppStorage(AhaKeyIslandAppSettings.showInDockKey) private var showInDock = true
    @AppStorage(AhaKeyIslandAppSettings.openAtLoginKey) private var openAtLogin = false
    @AppStorage(VibeBarIslandAppearanceSettings.suppressForegroundNotificationsKey) private var suppressForegroundNotifications = true
    @AppStorage(VibeBarIslandAppearanceSettings.replyInCompletionCardKey) private var replyInCompletionCard = true

    @State private var preferredDisplay = VibeBarIslandAppearanceSettings.preferredDisplay
    @State private var languageMode = VibeBarIslandAppearanceSettings.languageMode
    @State private var showMoreGeneral = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("通用")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("登录、Dock、语言与声音等应用级选项；与常驻/展开面板内容无关。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            systemSection
            soundPrimarySection

            AhaKeySettingsDisclosureSection(
                title: "更多通用",
                subtitle: "语言、更多声音、通知与高级功能",
                isExpanded: $showMoreGeneral
            ) {
                languageSection
                soundMoreSection
                notificationSection
                placeholderSection
            }
        }
        .onAppear(perform: reloadFromStorage)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification)) { _ in
            reloadFromStorage()
        }
    }

    private var systemSection: some View {
        AhakeySettingsCard(sectionTitle: "系统") {
            AhakeySettingsToggleRow(
                title: "登录时打开",
                subtitle: nil,
                isOn: Binding(
                    get: { openAtLogin },
                    set: { enabled in
                        openAtLogin = enabled
                        AhaKeyIslandAppSettings.openAtLogin = enabled
                    }
                )
            )
            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "在 Dock 中显示图标",
                subtitle: nil,
                isOn: Binding(
                    get: { showInDock },
                    set: { enabled in
                        showInDock = enabled
                        AhaKeyIslandAppSettings.showInDock = enabled
                    }
                )
            )
            AhakeySettingsCardDivider()
            AhakeySettingsMenuRow(
                title: "显示器",
                selectionTitle: preferredDisplay.title
            ) {
                ForEach(VibeBarIslandAppearanceSettings.PreferredDisplay.allCases) { option in
                    Button(option.title) {
                        preferredDisplay = option
                        VibeBarIslandAppearanceSettings.preferredDisplay = option
                    }
                }
            }
        }
    }

    private var languageSection: some View {
        AhakeySettingsCard(sectionTitle: "语言") {
            AhakeySettingsMenuRow(
                title: "语言",
                selectionTitle: languageMode.title
            ) {
                ForEach(VibeBarIslandAppearanceSettings.LanguageMode.allCases) { option in
                    Button(option.title) {
                        languageMode = option
                        VibeBarIslandAppearanceSettings.languageMode = option
                    }
                }
            }
        }
    }

    private var soundPrimarySection: some View {
        AhakeySettingsCard(sectionTitle: "声音") {
            AhakeySettingsToggleRow(
                title: "展开/收起音效",
                subtitle: nil,
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
    }

    private var soundMoreSection: some View {
        AhakeySettingsCard(sectionTitle: "更多声音") {
            settingsLinkRow(
                route: .sound,
                title: "更多声音设置",
                subtitle: "均衡器、自定义提示音等（占位）"
            )
        }
    }

    private var notificationSection: some View {
        AhakeySettingsCard(sectionTitle: "通知与回复") {
            AhakeySettingsToggleRow(
                title: "在完成卡片中回复",
                subtitle: nil,
                isOn: $replyInCompletionCard
            )
            .onChange(of: replyInCompletionCard) { _ in notifyAppearanceChanged() }

            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "前台会话不弹出通知",
                subtitle: nil,
                isOn: $suppressForegroundNotifications
            )
            .onChange(of: suppressForegroundNotifications) { _ in notifyAppearanceChanged() }
        }
    }

    /// 高级功能入口占位，保持可发现。
    private var placeholderSection: some View {
        AhakeySettingsCard(sectionTitle: "高级功能") {
            settingsLinkRow(
                route: .display,
                title: "显示与布局",
                subtitle: "信息密度等（即将推出）"
            )
            AhakeySettingsCardDivider()
            settingsLinkRow(
                route: .agentSessions,
                title: "Agent 会话",
                subtitle: "会话列表规则（即将推出）"
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
        preferredDisplay = VibeBarIslandAppearanceSettings.preferredDisplay
        languageMode = VibeBarIslandAppearanceSettings.languageMode
        openAtLogin = AhaKeyIslandAppSettings.openAtLogin
        showInDock = AhaKeyIslandAppSettings.showInDock
    }

    private func notifyAppearanceChanged() {
        NotificationCenter.default.post(
            name: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification,
            object: nil
        )
    }
}
