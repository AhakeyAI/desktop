import SwiftUI

// MARK: - Sidebar chrome

struct AhakeySettingsBrandHeader: View {
    var body: some View {
        Text("AhaKey Studio")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AhakeySettingsTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AhakeySettingsSidebarDeviceCard: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var onTap: (() -> Void)? = nil

    private var isConnected: Bool { bleManager.isConnected }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "keyboard")
                            .font(.system(size: 18))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(bleManager.deviceName ?? "AhaKey Mini")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(isConnected ? "已连接" : "未连接")
                            .font(.system(size: 11))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        Image(systemName: "battery.75percent")
                            .font(.system(size: 11))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        Text(isConnected ? "\(bleManager.batteryLevel)%" : "—")
                            .font(.system(size: 11))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .help("打开我的设备")
    }
}

struct AhakeySettingsSidebarUserCard: View {
    @ObservedObject private var account = CloudAccountManager.shared
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.85), AhakeySettingsTheme.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Text(account.avatarInitial)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.sidebarTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                        .lineLimit(1)
                    Text(account.sidebarSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
            )
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - Global top chrome（右侧功能入口，无品牌字）

struct AhakeySettingsGlobalTopBar: View {
    var onPluginMarketTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            topBarLabeledButton(
                title: "插件市场",
                systemImage: "bag",
                action: onPluginMarketTap
            )
        }
        .padding(.horizontal, AhakeySettingsTheme.contentPadding)
        .padding(.vertical, 12)
        .background(AhakeySettingsTheme.sidebarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AhakeySettingsTheme.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func topBarLabeledButton(
        title: String,
        systemImage: String,
        action: (() -> Void)?
    ) -> some View {
        let label = HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AhakeySettingsTheme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AhakeySettingsTheme.controlFill)
        )

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help(title)
        } else {
            label
                .opacity(0.55)
                .help(title)
        }
    }
}
