import SwiftUI

/// 左下角「我的设备」：点设备卡进入详情（迁入 DeviceInfoView）。
struct AhaKeyDeviceManagementPane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @Binding var showsDetail: Bool
    var onClose: (() -> Void)? = nil
    @ObservedObject private var coachTips = FeatureCoachTipController.shared

    var body: some View {
        Group {
            if showsDetail {
                deviceDetail
            } else {
                deviceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AhakeySettingsTheme.contentBackground)
        .featureCoachTip(
            .deviceConnect,
            isActive: true,
            alignment: .topTrailing,
            enablePrimaryAction: false
        )
    }

    private var deviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我的设备")
                            .font(AhakeySettingsTheme.pageTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text("管理已连接或可连接的 AhaKey 键盘：改名、蓝牙占用与设备信息。")
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if let onClose {
                        Button("关闭", action: onClose)
                            .buttonStyle(.plain)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }

                Button {
                    showsDetail = true
                } label: {
                    deviceListCard
                }
                .buttonStyle(.plain)

                if !bleManager.isConnected {
                    emptyHint
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    private var deviceListCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AhakeySettingsTheme.controlFill)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(bleManager.deviceName ?? "AhaKey Mini")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                HStack(spacing: 8) {
                    Circle()
                        .fill(bleManager.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(bleManager.isConnected ? "已连接" : "未连接")
                        .font(.system(size: 12))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    if bleManager.isConnected {
                        Text("电量 \(bleManager.batteryLevel)%")
                            .font(.system(size: 12))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)

            Text("设置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AhakeySettingsTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AhakeySettingsTheme.divider, lineWidth: 1)
        )
    }

    private var emptyHint: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("尚未连接键盘")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("将蓝牙交给本 App 后，点右侧「连接设备」。也可进入详情查看更多选项。")
                    .font(.system(size: 12))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                showsDetail = true
                bleManager.userInitiatedConnect()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(bleManager.isScanning)
            .overlay(alignment: .top) {
                if coachTips.isShowing(.deviceConnect) {
                    Text("点这里")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AhakeySettingsTheme.accentBlue)
                        )
                        .offset(y: -28)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(AhakeySettingsTheme.divider)
        )
    }

    private var deviceDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if let onClose {
                        onClose()
                    } else {
                        showsDetail = false
                    }
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text(bleManager.deviceName ?? "AhaKey Mini")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, AhakeySettingsTheme.contentPadding)
            .padding(.top, 16)
            .padding(.bottom, 10)

            DeviceInfoView(bleManager: bleManager, chrome: .settingsCards)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
