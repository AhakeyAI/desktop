import SwiftUI

struct AhakeySettingsRootChrome<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: AhakeySettingsTheme.sidebarWidth)
                .background(AhakeySettingsTheme.sidebarBackground)

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AhakeySettingsTheme.contentBackground)
        }
        .background(AhakeySettingsTheme.windowBackground)
    }
}

struct AhakeySettingsTopBar: View {
    var brandName: String
    var onSettingsTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(brandName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)

            HStack(spacing: 16) {
                topBarButton("gearshape", action: onSettingsTap)
                topBarIcon("bag")
                topBarIcon("person.crop.circle")
            }
        }
        .padding(.horizontal, AhakeySettingsTheme.contentPadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func topBarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AhakeySettingsTheme.secondaryText)
            .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func topBarButton(_ name: String, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                topBarIcon(name)
            }
            .buttonStyle(.plain)
        } else {
            topBarIcon(name)
        }
    }
}

struct AhakeySettingsFlatSidebar: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @Binding var selection: AhaKeySettingsTab
    var onUserTap: (() -> Void)? = nil
    var onDeviceTap: (() -> Void)? = nil

    private static let items = AhaKeySettingsTab.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AhakeySettingsBrandHeader()
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.items) { tab in
                    sidebarRow(tab: tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("我的设备")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    .padding(.horizontal, 4)

                AhakeySettingsSidebarDeviceCard(bleManager: bleManager, onTap: onDeviceTap)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            AhakeySettingsSidebarUserCard(onTap: onUserTap)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarRow(tab: AhaKeySettingsTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.secondaryText)
                    .frame(width: 18)

                Text(tab.title)
                    .font(AhakeySettingsTheme.sidebarItemFont)
                    .foregroundStyle(isSelected ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AhakeySettingsTheme.sidebarSelection : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AhakeySettingsDetailScaffold<Content: View>: View {
    let title: String
    let brandName: String
    var onSettingsTap: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let onBack {
                            Button(action: onBack) {
                                Label("返回", systemImage: "chevron.left")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(title)
                            .font(AhakeySettingsTheme.pageTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                    }
                    .padding(.bottom, 4)

                    content()
                }
                .padding(.horizontal, AhakeySettingsTheme.contentPadding)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
        }
    }
}

struct AhakeySettingsCard<Content: View>: View {
    let sectionTitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(AhakeySettingsTheme.sectionTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: AhakeySettingsTheme.cardCornerRadius, style: .continuous)
                    .fill(AhakeySettingsTheme.cardBackground)
            )
        }
    }
}

struct AhakeySettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(AhakeySettingsTheme.divider)
            .frame(height: 1)
            .padding(.leading, AhakeySettingsTheme.rowPaddingH)
    }
}

struct AhakeySettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AhakeySettingsTheme.accentBlue)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, AhakeySettingsTheme.rowPaddingV)
    }
}

struct AhakeySettingsMenuRow<MenuContent: View>: View {
    let title: String
    let selectionTitle: String
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer(minLength: 8)
            Menu {
                menuContent()
            } label: {
                HStack(spacing: 4) {
                    Text(selectionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AhakeySettingsTheme.controlFill)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, AhakeySettingsTheme.rowPaddingV)
    }
}

struct AhakeyWrappedSettingsPane<Content: View>: View {
    let title: String
    let brandName: String
    var onSettingsTap: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        AhakeySettingsDetailScaffold(
            title: title,
            brandName: brandName,
            onSettingsTap: onSettingsTap,
            onBack: onBack,
            content: content
        )
    }
}
