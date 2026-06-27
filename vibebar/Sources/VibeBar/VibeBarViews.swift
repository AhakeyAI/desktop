import SwiftUI

struct VibeBarCompactKeyboardItem: View {
    @ObservedObject var state: VibeBarState
    let onHoverChanged: (Bool) -> Void

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
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
    }

    private var label: String {
        if !state.keyboardConnected { return "—" }
        return "\(state.batteryLevel)%"
    }
}

struct VibeBarCompactLeverItem: View {
    @ObservedObject var state: VibeBarState
    let onHoverChanged: (Bool) -> Void

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
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
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
        guard state.leverKnown else { return "Lever?" }
        return state.leverIsAuto ? "Auto" : "Ask"
    }
}

struct VibeBarExpandedMenu: View {
    @ObservedObject var state: VibeBarState
    let onAppear: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onCompact: () -> Void
    let onOpenMain: () -> Void

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
                    title: "Device",
                    systemName: state.keyboardConnected ? "keyboard.fill" : "keyboard",
                    value: state.keyboardConnected ? "\(state.batteryLevel)%" : "Off",
                    tint: state.keyboardConnected ? .cyan : .secondary
                )
                statusTile(
                    title: "Lever",
                    systemName: leverIcon,
                    value: leverValue,
                    tint: leverTint
                )
                statusTile(
                    title: "Voice",
                    systemName: voiceIcon,
                    value: voiceValue,
                    tint: voiceTint
                )
                statusTile(
                    title: "Window",
                    systemName: "macwindow",
                    value: "Open",
                    tint: .indigo,
                    action: onOpenMain
                )
            }

            HStack(spacing: 8) {
                Spacer()
                Text("Move cursor away to collapse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onAppear(perform: onAppear)
        .onHover(perform: onHoverChanged)
    }

    private var subtitle: String {
        if let name = state.deviceName, state.keyboardConnected {
            return name
        }
        return state.keyboardConnected ? "Connected" : "Disconnected"
    }

    private var leverIcon: String {
        guard state.leverKnown else { return "questionmark.circle" }
        return state.leverIsAuto ? "lock.open.fill" : "lock.fill"
    }

    private var leverValue: String {
        guard state.leverKnown else { return "Unknown" }
        return state.leverIsAuto ? "Auto" : "Ask"
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
        if state.voiceRecording { return "Rec" }
        if state.voiceListening { return "On" }
        return "Off"
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
