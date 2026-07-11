import SwiftUI
import VibeBar

/// 灵动岛 / 硬件 Tab 顶栏设备状态（仅图标，无文字）。
struct VibeBarIslandDeviceStatusIcons: View {
    let keyboardConnected: Bool
    let batteryLevel: Int
    let voiceRecording: Bool
    let voiceListening: Bool
    let leverIsAuto: Bool
    let leverKnown: Bool

    init(state: VibeBarState) {
        keyboardConnected = state.keyboardConnected
        batteryLevel = state.batteryLevel
        voiceRecording = state.voiceRecording
        voiceListening = state.voiceListening
        leverIsAuto = state.leverIsAuto
        leverKnown = state.leverKnown
    }

    init(
        keyboardConnected: Bool,
        batteryLevel: Int,
        voiceRecording: Bool = false,
        voiceListening: Bool = false,
        leverIsAuto: Bool = false,
        leverKnown: Bool = false
    ) {
        self.keyboardConnected = keyboardConnected
        self.batteryLevel = batteryLevel
        self.voiceRecording = voiceRecording
        self.voiceListening = voiceListening
        self.leverIsAuto = leverIsAuto
        self.leverKnown = leverKnown
    }

    private let iconFont = Font.system(size: 11, weight: .semibold)
    private let accentCyan = Color(red: 0.337, green: 0.761, blue: 1.0)

    var body: some View {
        HStack(spacing: 6) {
            statusIcon(
                systemName: keyboardConnected ? "keyboard.fill" : "keyboard",
                tint: keyboardConnected ? accentCyan : .white.opacity(0.38),
                accessibilityLabel: keyboardConnected ? "键盘已连接" : "等待设备"
            )

            if keyboardConnected {
                statusIcon(
                    systemName: batterySymbol,
                    tint: batteryTint,
                    accessibilityLabel: "电量 \(batteryLevel)%"
                )
            } else {
                statusIcon(
                    systemName: "antenna.radiowaves.left.and.right",
                    tint: .white.opacity(0.38),
                    accessibilityLabel: "等待设备连接"
                )
            }

            statusIcon(
                systemName: voiceIconName,
                tint: voiceTint,
                accessibilityLabel: voiceAccessibilityLabel
            )

            if leverKnown {
                statusIcon(
                    systemName: leverIsAuto ? "checkmark.circle.fill" : "hand.raised.fill",
                    tint: leverIsAuto ? Color(red: 0.26, green: 0.91, blue: 0.42) : .orange.opacity(0.9),
                    accessibilityLabel: leverIsAuto ? "自动放行" : "手动确认"
                )
            }
        }
    }

    private var batterySymbol: String {
        switch batteryLevel {
        case 0...10: return "battery.0percent"
        case 11...35: return "battery.25percent"
        case 36...65: return "battery.50percent"
        case 66...90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryTint: Color {
        if batteryLevel <= 15 { return .orange.opacity(0.92) }
        return .white.opacity(0.62)
    }

    private var voiceIconName: String {
        if voiceRecording { return "mic.fill" }
        if voiceListening { return "mic" }
        return "mic.slash"
    }

    private var voiceTint: Color {
        if voiceRecording { return Color(red: 1.0, green: 0.35, blue: 0.35) }
        if voiceListening { return Color(red: 0.26, green: 0.91, blue: 0.42) }
        return .white.opacity(0.38)
    }

    private var voiceAccessibilityLabel: String {
        if voiceRecording { return "语音录制中" }
        if voiceListening { return "语音监听中" }
        return "语音未激活"
    }

    private func statusIcon(
        systemName: String,
        tint: Color,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemName)
            .font(iconFont)
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .accessibilityLabel(accessibilityLabel)
    }
}
