import SwiftUI
import VibeBar

/// Agent · 设置：Pet 外观主入口 + 边界与跳转说明。
struct AhaKeyAgentGeneralPane: View {
    @ObservedObject var islandState: VibeBarState
    @State private var showMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("设置")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("Pet 外观（皮肤 / 图标）在此配置；动画、尺寸与信息层请到灵动岛 · 组件库。日常对话用「助手」，启用守护与蓝牙用「联动」。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Pet 外观")
                    .font(AhakeySettingsTheme.sectionTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .padding(.leading, 4)

                AhaKeyPetAppearanceEditor(agentTaskTitle: islandState.agentTaskTitle)
            }

            AhakeySettingsCard(sectionTitle: "怎么用") {
                Text("先到「联动」一键启用；再用「助手」查状态或切蓝牙。键盘 Mode、批准键与语音键请到「硬件设备」。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                    .padding(.vertical, 14)
            }

            AhaKeySettingsDisclosureSection(
                title: "跳转与说明",
                subtitle: "Mode、改键入口与安全边界",
                isExpanded: $showMore
            ) {
                AhakeySettingsCard(sectionTitle: "面向的 AI 工具") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("键盘 Mode 对应 Claude / Cursor / Codex / custom。切换请到硬件画布下方的 Agent 模式分段。")
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            StudioNavigationRouter.shared.selectSettingsTab(.hardware)
                        } label: {
                            navRow("打开硬件设备 · 切换 Mode")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                    .padding(.vertical, 14)
                }

                AhakeySettingsCard(sectionTitle: "快捷改键入口") {
                    Button {
                        StudioNavigationRouter.shared.selectSettingsTab(.hardware)
                        NotificationCenter.default.post(
                            name: .ahaKeyStudioSelectPart,
                            object: nil,
                            userInfo: [StudioNavigationUserInfoKey.part: AhaKeyStudioPart.key2.rawValue]
                        )
                    } label: {
                        navRow("配置批准键（Key 2）")
                    }
                    .buttonStyle(.plain)
                    AhakeySettingsCardDivider()
                    Button {
                        StudioNavigationRouter.shared.selectSettingsTab(.hardware)
                        NotificationCenter.default.post(
                            name: .ahaKeyStudioSelectPart,
                            object: nil,
                            userInfo: [StudioNavigationUserInfoKey.part: AhaKeyStudioPart.key1.rawValue]
                        )
                    } label: {
                        navRow("配置语音键（Key 1）")
                    }
                    .buttonStyle(.plain)
                }

                AhakeySettingsCard(sectionTitle: "安全与边界") {
                    Text("Hook 会写入本机用户配置（如 ~/.cursor/hooks.json）。AhaKey 助手只管理设备与工作流联动，不会替代 Claude/Cursor 写代码。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private func navRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }
}
