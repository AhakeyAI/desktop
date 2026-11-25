import AppKit
import SwiftUI

/// VibeBar ships no strings of its own. Its labels are looked up in the host app's
/// Localizable.strings (Bundle.main, keyed by the Chinese wording like the rest of AhaKey Studio)
/// and fall back to the English text when the host has no entry (for example VibeBarSmoke).
func vibeBarText(_ key: String, _ fallback: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
}

struct VibeBarCompactKeyboardItem: View {
    @ObservedObject var state: VibeBarState
    let onFrameChanged: (CGRect, NSScreen) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.keyboardConnected ? "keyboard.fill" : "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.keyboardConnected ? .cyan : .secondary)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(GeometryReader { geometry in
            VibeBarFrameReporter(contentFrame: geometry.frame(in: .global), report: onFrameChanged)
        })
        .contentShape(Rectangle())
    }

    private var label: String {
        if !state.keyboardConnected { return "—" }
        return "\(state.batteryLevel)%"
    }
}

struct VibeBarCompactLeverItem: View {
    @ObservedObject var state: VibeBarState
    let onFrameChanged: (CGRect, NSScreen) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(GeometryReader { geometry in
            VibeBarFrameReporter(contentFrame: geometry.frame(in: .global), report: onFrameChanged)
        })
        .contentShape(Rectangle())
    }

    private var icon: String {
        guard state.leverKnown else { return "questionmark.circle" }
        return state.leverIsAuto ? "lock.open.fill" : "lock.fill"
    }

    private var color: Color {
        guard state.leverKnown else { return .secondary }
        return state.leverIsAuto ? .green : .orange
    }

    private var label: String {
        guard state.leverKnown else { return vibeBarText("拨杆?", "Lever?") }
        return state.leverIsAuto ? vibeBarText("自动", "Auto") : vibeBarText("手动", "Ask")
    }
}

struct VibeBarExpandedMenu: View {
    @ObservedObject var state: VibeBarState
    let onAppear: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onFrameChanged: (CGRect, NSScreen) -> Void
    let onCompact: () -> Void
    let onOpenMain: () -> Void
    let onExitIsland: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AhaKey Island")
                        .font(.system(size: 16, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCompact) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                statusTile(
                    title: vibeBarText("设备", "Device"),
                    systemName: state.keyboardConnected ? "keyboard.fill" : "keyboard",
                    value: state.keyboardConnected ? "\(state.batteryLevel)%" : vibeBarText("未连接", "Off"),
                    tint: state.keyboardConnected ? .cyan : .secondary
                )
                statusTile(
                    title: vibeBarText("拨杆", "Lever"),
                    systemName: leverIcon,
                    value: leverValue,
                    tint: leverTint
                )
                statusTile(
                    title: vibeBarText("语音", "Voice"),
                    systemName: voiceIcon,
                    value: voiceValue,
                    tint: voiceTint
                )
                statusTile(
                    title: vibeBarText("窗口", "Window"),
                    systemName: "macwindow",
                    value: vibeBarText("打开", "Open"),
                    tint: .indigo,
                    action: onOpenMain
                )
            }

            HStack(spacing: 8) {
                Button(action: onExitIsland) {
                    HStack(spacing: 6) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.12), in: Circle())
                        Text(vibeBarText("关闭灵动岛", "Exit island"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vibeBarText("关闭灵动岛", "Exit island"))
                Spacer()
                Text(vibeBarText("移开光标即可收起", "Move cursor away to collapse"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
        .foregroundStyle(.white)
        .background(GeometryReader { geometry in
            VibeBarFrameReporter(contentFrame: geometry.frame(in: .global), report: onFrameChanged)
        })
        .contentShape(Rectangle())
        .onAppear(perform: onAppear)
        .onHover(perform: onHoverChanged)
    }

    private var subtitle: String {
        if let name = state.deviceName, state.keyboardConnected {
            return name
        }
        return state.keyboardConnected ? vibeBarText("已连接", "Connected") : vibeBarText("未连接", "Disconnected")
    }

    private var leverIcon: String {
        guard state.leverKnown else { return "questionmark.circle" }
        return state.leverIsAuto ? "lock.open.fill" : "lock.fill"
    }

    private var leverValue: String {
        guard state.leverKnown else { return vibeBarText("未知", "Unknown") }
        return state.leverIsAuto ? vibeBarText("自动", "Auto") : vibeBarText("手动", "Ask")
    }

    private var leverTint: Color {
        guard state.leverKnown else { return .secondary }
        return state.leverIsAuto ? .green : .orange
    }

    private var voiceIcon: String {
        if state.voiceRecording { return "mic.fill" }
        if state.voiceListening { return "waveform" }
        return "mic.slash"
    }

    private var voiceValue: String {
        if state.voiceRecording { return vibeBarText("录音中", "Rec") }
        if state.voiceListening { return vibeBarText("已开启", "On") }
        return vibeBarText("Off", "Off")
    }

    private var voiceTint: Color {
        if state.voiceRecording { return .red }
        if state.voiceListening { return .green }
        return .secondary
    }

    private func statusTile(
        title: String,
        systemName: String,
        value: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90, height: 64)
        }
        .buttonStyle(.borderless)
        .disabled(action == nil)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
