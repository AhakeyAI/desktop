import SwiftUI
import VibeBar

// MARK: - Chassis tokens

enum VibeBarChassisTheme {
    static let oledCorner: CGFloat = 10
    static let keyCorner: CGFloat = 8
    /// 内容相对灵动岛黑壳的内边距（岛缘=键盘缘，只留键帽呼吸边）。
    static let contentInset: CGFloat = 12

    static let keyFace = Color(red: 0.16, green: 0.17, blue: 0.19)
    static let keyFacePressed = Color(red: 0.11, green: 0.12, blue: 0.14)
}

// MARK: - Edge-to-edge keyboard body (island shell IS the chassis)

/// 灵动岛黑壳即机身外缘：按组件库启用顺序渲染模块。
struct VibeBarHardwareChassis: View {
    let status: VibeBarAgentStatus
    let state: VibeBarState
    let taskTitle: String
    let progress: Double
    let keys: [VibeBarCommandKey]
    @Binding var isSoundMuted: Bool
    var onOpenMainWindow: () -> Void
    var onQuit: () -> Void
    var onPetTap: () -> Void
    var petAppearance: VibeBarPetAppearance = VibeBarPetAppearanceSettings.appearance
    @ObservedObject private var focusTimer = VibeBarFocusTimerStore.shared

    private var modules: [VibeBarExpandedModule] {
        state.enabledExpandedModules.isEmpty
            ? VibeBarExpandedModule.defaultEnabledOrder
            : state.enabledExpandedModules
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeRow
                .padding(.horizontal, VibeBarChassisTheme.contentInset)
                .padding(.top, 4)
                .padding(.bottom, modules.contains(.lightStrip) || modules.contains(.focusChip) ? 6 : 10)

            ForEach(modules) { module in
                moduleView(module)
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private func moduleView(_ module: VibeBarExpandedModule) -> some View {
        switch module {
        case .lightStrip:
            VibeBarAgentLightStrip(
                status: status,
                ledCount: 40,
                height: 16,
                showsRecess: false
            )
            .padding(.horizontal, VibeBarChassisTheme.contentInset)
            .padding(.bottom, 10)
        case .focusChip:
            // 专注芯片已在 chromeRow；若单独启用且未在顶栏展示则补一条
            EmptyView()
        case .oledPet:
            VibeBarAIPetOLED(
                status: status,
                taskTitle: taskTitle,
                progress: progress,
                appearance: petAppearance,
                onTap: onPetTap
            )
            .padding(.horizontal, VibeBarChassisTheme.contentInset)
            .padding(.bottom, 12)
        case .keyPad:
            VibeBarCommandKeyPad(keys: keys, highlightStatus: status)
                .padding(.horizontal, VibeBarChassisTheme.contentInset)
                .padding(.bottom, 10)
        case .magneticBase:
            VibeBarMagneticBaseStatus(state: state, focusTimer: focusTimer)
                .padding(.horizontal, VibeBarChassisTheme.contentInset)
                .padding(.bottom, 8)
        }
    }

    private var chromeRow: some View {
        HStack(spacing: 8) {
            Text("VibeBar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.4)

            if modules.contains(.focusChip) {
                focusChip
            }

            Spacer(minLength: 0)

            VibeBarIslandMenuBar(
                isSoundMuted: $isSoundMuted,
                onOpenMainWindow: onOpenMainWindow,
                onQuit: onQuit
            )
            .scaleEffect(0.92, anchor: .trailing)
        }
    }

    private var focusChip: some View {
        Button {
            focusTimer.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: focusTimer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(focusTimer.displayText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(focusTimer.isRunning ? Color(red: 1.0, green: 0.78, blue: 0.28) : .white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(focusTimer.isRunning ? 0.12 : 0.06))
            )
        }
        .buttonStyle(.plain)
        .help(focusTimer.isRunning ? "暂停专注" : "开始专注")
    }
}

// MARK: - OLED AI Pet

struct VibeBarAIPetOLED: View {
    let status: VibeBarAgentStatus
    var taskTitle: String
    var progress: Double
    var appearance: VibeBarPetAppearance = VibeBarPetAppearanceSettings.appearance
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: VibeBarChassisTheme.oledCorner + 2, style: .continuous)
                    .fill(Color.white.opacity(0.04))

                RoundedRectangle(cornerRadius: VibeBarChassisTheme.oledCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.055, blue: 0.07),
                                Color(red: 0.015, green: 0.015, blue: 0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: VibeBarChassisTheme.oledCorner, style: .continuous)
                            .stroke(status.lightPrimary.opacity(0.4), lineWidth: 1)
                    )
                    .padding(2)

                HStack(spacing: 14) {
                    petGlyph
                        .frame(width: appearance.petSize.glyphFontSize + 18)

                    VStack(alignment: .leading, spacing: 4) {
                        if appearance.showsStatusLabel {
                            Text(status.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        }

                        if appearance.showsTaskTitle {
                            Text(taskTitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }

                        if appearance.showsProgress,
                           progress > 0,
                           status == .coding || status == .searching || status == .thinking {
                            progressBar
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: appearance.petSize.panelHeight)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("AI Pet：\(status.title)")
    }

    @ViewBuilder
    private var petGlyph: some View {
        if let url = appearance.resolvedCustomAssetURL {
            PixelArtAnimatedGIFView(path: url.path, fps: 12)
                .frame(width: appearance.petSize.glyphFontSize + 8, height: appearance.petSize.glyphFontSize + 8)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .modifier(VibeBarPetAnimationModifier(
                    style: appearance.animationStyle(for: status),
                    speed: appearance.animationSpeed
                ))
        } else {
            Text(appearance.glyph(for: status))
                .font(.system(size: appearance.petSize.glyphFontSize))
                .foregroundStyle(status.lightPrimary)
                .modifier(VibeBarPetAnimationModifier(
                    style: appearance.animationStyle(for: status),
                    speed: appearance.animationSpeed
                ))
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(status.lightPrimary.opacity(0.9))
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 3)
    }
}

private struct VibeBarPetAnimationModifier: ViewModifier {
    let style: VibeBarPetAnimationStyle
    let speed: VibeBarPetAnimationSpeed

    func body(content: Content) -> some View {
        switch style {
        case .none:
            content
        case .breathe:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * (.pi * 2) / speed.period) + 1) / 2
                content
                    .scaleEffect(0.92 + 0.08 * phase)
                    .opacity(0.75 + 0.25 * phase)
            }
        case .bounce:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = abs(sin(t * (.pi * 2) / speed.period))
                content
                    .offset(y: -4 * phase)
            }
        case .blink:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let on = Int(t / (speed.period / 2)) % 2 == 0
                content.opacity(on ? 1 : 0.25)
            }
        }
    }
}

// MARK: - Four keycaps

struct VibeBarCommandKey: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color
    let action: () -> Void
}

struct VibeBarCommandKeyPad: View {
    let keys: [VibeBarCommandKey]
    var highlightStatus: VibeBarAgentStatus = .idle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(keys) { key in
                keycap(key)
            }
        }
    }

    private func keycap(_ key: VibeBarCommandKey) -> some View {
        let emphasized = shouldEmphasize(key)
        return Button(action: key.action) {
            VStack(spacing: 5) {
                Image(systemName: key.systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(key.tint)
                Text(key.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(key.subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: VibeBarChassisTheme.keyCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                VibeBarChassisTheme.keyFace.opacity(emphasized ? 1 : 0.95),
                                VibeBarChassisTheme.keyFacePressed,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: VibeBarChassisTheme.keyCorner, style: .continuous)
                    .stroke(
                        emphasized ? key.tint.opacity(0.55) : Color.white.opacity(0.1),
                        lineWidth: emphasized ? 1.2 : 1
                    )
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1.5)
                    .padding(.horizontal, 10)
                    .padding(.top, 5)
            }
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
        }
        .buttonStyle(VibeBarKeycapButtonStyle())
    }

    private func shouldEmphasize(_ key: VibeBarCommandKey) -> Bool {
        switch highlightStatus {
        case .listening: return key.id == VibeBarKeyPadRole.voice.rawValue || key.id == "record"
        case .approval:
            return key.id == VibeBarKeyPadRole.approve.rawValue
                || key.id == VibeBarKeyPadRole.reject.rawValue
                || key.id == "approve"
                || key.id == "reject"
        case .coding, .thinking, .searching:
            return key.id == VibeBarKeyPadRole.submit.rawValue || key.id == "switch"
        default: return false
        }
    }
}

private struct VibeBarKeycapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Magnetic base

struct VibeBarMagneticBaseStatus: View {
    let state: VibeBarState
    @ObservedObject var focusTimer: VibeBarFocusTimerStore

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.keyboardConnected ? Color(red: 0.26, green: 0.91, blue: 0.42) : Color.white.opacity(0.2))
                .frame(width: 6, height: 6)

            Text(state.keyboardConnected ? "Connected" : "Offline")
                .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 0)

            Button {
                focusTimer.toggle()
            } label: {
                Label(focusTimer.isRunning ? "专注中" : "专注", systemImage: "timer")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(focusTimer.isRunning ? Color(red: 1.0, green: 0.78, blue: 0.28) : .white.opacity(0.45))
            }
            .buttonStyle(.plain)

            if state.keyboardConnected {
                Label("\(state.batteryLevel)%", systemImage: "battery.75percent")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white.opacity(0.45))
            }

            if state.leverKnown {
                Text(state.leverIsAuto ? "Auto" : "Ask")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
