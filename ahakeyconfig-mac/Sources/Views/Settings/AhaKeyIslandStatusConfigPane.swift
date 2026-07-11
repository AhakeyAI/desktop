import SwiftUI
import VibeBar

/// 常驻岛配置：状态态 + 预览 + 左/右槽 + 灯条 + 尺寸。
struct AhaKeyIslandStatusConfigPane: View {
    @ObservedObject var state: VibeBarState
    @Binding var route: AhaKeyDynamicIslandSettingsRoute
    let brandName: String

    @State private var stateKind: VibeBarRestingStateKind = VibeBarIslandAppearanceSettings.editingStateKind
    @State private var rightSlot: VibeBarRightSlotDisplay = VibeBarIslandAppearanceSettings.rightSlot(for: .auto)
    @State private var leftSlot: VibeBarLeftSlotDisplay = VibeBarIslandAppearanceSettings.leftSlot(for: .auto)
    @AppStorage(VibeBarIslandAppearanceSettings.previewSessionCountKey) private var previewSessionCount = 3
    @AppStorage(VibeBarIslandAppearanceSettings.compactLightStripEnabledKey) private var lightStripEnabled = true
    @State private var islandWidth = VibeBarIslandAppearanceSettings.islandWidth
    @State private var showMoreAppearance = false

    private var previewModel: VibeBarCompactNotchModel {
        VibeBarIslandAppearanceSettings.previewModel(
            for: stateKind,
            rightSlot: rightSlot,
            leftSlot: leftSlot,
            sessionCount: previewSessionCount,
            deviceState: state,
            lightStripEnabled: lightStripEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(VibeBarRestingStateKind.auto.configPageTitle)
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("静息态收起胶囊；在预览左下角切换状态，并分别配置左槽、右槽与灯条。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            AhaKeyIslandNotchPreview(
                model: previewModel,
                stateKind: $stateKind,
                islandWidth: islandWidth,
                agentStatus: state.agentStatus,
                sectionTitle: "常驻岛预览"
            )

            layoutSection

            AhaKeySettingsDisclosureSection(
                title: "更多外观",
                subtitle: "灯条、尺寸与高级功能",
                isExpanded: $showMoreAppearance
            ) {
                lightStripSection
                islandWidthSection
                placeholderSection
            }
        }
        .onAppear(perform: reloadFromStorage)
        .onChange(of: stateKind) { kind in
            VibeBarIslandAppearanceSettings.editingStateKind = kind
            reloadFromStorage()
            applyToLiveIsland()
        }
        .onChange(of: rightSlot) { _ in applyToLiveIsland() }
        .onChange(of: leftSlot) { _ in applyToLiveIsland() }
        .onChange(of: lightStripEnabled) { enabled in
            VibeBarIslandAppearanceSettings.compactLightStripEnabled = enabled
            applyToLiveIsland()
        }
        .onChange(of: previewSessionCount) { _ in applyToLiveIsland() }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarIslandAppearanceSettings.appearanceDidChangeNotification)) { _ in
            reloadFromStorage()
        }
    }

    private var lightStripSection: some View {
        AhakeySettingsCard(sectionTitle: "灯条") {
            AhakeySettingsToggleRow(
                title: "显示 Agent 灯条",
                subtitle: "常驻岛底部状态灯效，关闭后胶囊更紧凑",
                isOn: $lightStripEnabled
            )
        }
    }

    private var islandWidthSection: some View {
        AhakeySettingsCard(sectionTitle: "尺寸") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("岛宽度")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer()
                    Text("\(Int(islandWidth)) pt")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { Double(islandWidth) },
                        set: { islandWidth = CGFloat($0) }
                    ),
                    in: Double(VibeBarIslandAppearanceSettings.islandWidthMin)...Double(VibeBarIslandAppearanceSettings.islandWidthMax),
                    step: 10
                )
                .onChange(of: islandWidth) { width in
                    VibeBarIslandAppearanceSettings.islandWidth = width
                    state.islandWidth = width
                    applyToLiveIsland()
                }

                Text("可调范围 \(Int(VibeBarIslandAppearanceSettings.islandWidthMin))–\(Int(VibeBarIslandAppearanceSettings.islandWidthMax)) pt；常驻岛与展开岛共用。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("布局")
                .font(AhakeySettingsTheme.sectionTitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.leading, 4)

            leftSlotSection
            rightSlotSection
        }
    }

    private var leftSlotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("左槽")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(VibeBarLeftSlotDisplay.allCases) { option in
                    AhaKeyIslandLeftSlotOptionCard(
                        display: option,
                        isSelected: leftSlot == option
                    ) {
                        leftSlot = option
                        VibeBarIslandAppearanceSettings.setLeftSlot(option, for: stateKind)
                        applyToLiveIsland()
                    }
                }
            }
        }
    }

    private var rightSlotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("右槽")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(VibeBarRightSlotDisplay.allCases) { option in
                    AhaKeyIslandRightSlotOptionCard(
                        display: option,
                        sessionCount: previewSessionCount,
                        isSelected: rightSlot == option
                    ) {
                        rightSlot = option
                        VibeBarIslandAppearanceSettings.setRightSlot(option, for: stateKind)
                        applyToLiveIsland()
                    }
                }
            }
        }
    }

    /// 常驻岛相关高级功能占位；系统/声音已迁至「通用」。
    private var placeholderSection: some View {
        AhakeySettingsCard(sectionTitle: "高级功能") {
            Button { route = .agentSessions } label: {
                HStack(spacing: 12) {
                    Image(systemName: AhaKeyDynamicIslandSettingsRoute.agentSessions.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Agent 会话")
                                .font(AhakeySettingsTheme.rowTitleFont)
                                .foregroundStyle(AhakeySettingsTheme.primaryText)
                            Text("占位")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AhakeySettingsTheme.controlFill))
                        }
                        Text("会话列表在胶囊中的展示规则（即将推出）")
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
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
    }

    private func reloadFromStorage() {
        stateKind = VibeBarIslandAppearanceSettings.editingStateKind
        rightSlot = VibeBarIslandAppearanceSettings.rightSlot(for: stateKind)
        leftSlot = VibeBarIslandAppearanceSettings.leftSlot(for: stateKind)
        previewSessionCount = VibeBarIslandAppearanceSettings.previewSessionCount
        islandWidth = VibeBarIslandAppearanceSettings.islandWidth
        lightStripEnabled = VibeBarIslandAppearanceSettings.compactLightStripEnabled
    }

    private func applyToLiveIsland() {
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
    }
}

extension Notification.Name {
    static let ahaKeyIslandAppearanceApplyRequested = Notification.Name("ahaKey.island.appearanceApplyRequested")
}
