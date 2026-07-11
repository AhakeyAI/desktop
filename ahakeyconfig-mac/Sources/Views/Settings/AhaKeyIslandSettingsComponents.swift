import SwiftUI
import VibeBar

/// 常驻岛 / 展开岛预览共用舞台背景。
enum AhaKeyIslandPreviewStage {
    static let cornerRadius: CGFloat = 18

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.12, blue: 0.42),
                Color(red: 0.55, green: 0.22, blue: 0.58),
                Color(red: 0.72, green: 0.32, blue: 0.62),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func background(cornerRadius: CGFloat = cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(gradient)
    }
}

/// 设置页「常驻岛预览」：胶囊居中 + 左下角状态切换。
struct AhaKeyIslandNotchPreview: View {
    let model: VibeBarCompactNotchModel
    @Binding var stateKind: VibeBarRestingStateKind
    var islandWidth: CGFloat = VibeBarIslandAppearanceSettings.islandWidth
    var agentStatus: VibeBarAgentStatus = .idle
    var sectionTitle: String = "常驻岛预览"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle)
                .font(AhakeySettingsTheme.sectionTitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.leading, 4)

            ZStack {
                AhaKeyIslandPreviewStage.background()

                VibeBarCompactNotchPreviewCapsule(
                    model: model,
                    width: min(islandWidth, VibeBarIslandAppearanceSettings.islandWidthMax),
                    agentStatus: agentStatus
                )

                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        AhaKeyIslandStateKindPicker(selection: $stateKind)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 14)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: AhaKeyIslandPreviewStage.cornerRadius, style: .continuous))
        }
    }
}

/// 设置页「展开岛预览」：渲染真实展开机身（非常驻胶囊）。
struct AhaKeyIslandExpandedPreview: View {
    @ObservedObject var state: VibeBarState
    var islandWidth: CGFloat = VibeBarIslandAppearanceSettings.islandWidth
    var sectionTitle: String = "展开岛预览"

    @State private var isSoundMuted = false
    @State private var petAppearance = VibeBarPetAppearanceSettings.appearance
    @State private var keyPadSlots = VibeBarKeyPadSettings.slots

    private var previewStatus: VibeBarAgentStatus {
        if state.voiceRecording { return .listening }
        if state.agentRunning { return .thinking }
        return state.agentStatus == .idle ? .coding : state.agentStatus
    }

    private var previewKeys: [VibeBarCommandKey] {
        let visible = keyPadSlots.filter(\.isEnabled)
        let slots = visible.isEmpty ? Array(keyPadSlots.prefix(1)) : visible
        return slots.map { slot in
            VibeBarCommandKey(
                id: slot.role.rawValue,
                title: slot.title,
                subtitle: slot.id.uppercased(),
                systemName: slot.systemImage,
                tint: slot.tintColor,
                action: {}
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle)
                .font(AhakeySettingsTheme.sectionTitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.leading, 4)

            ZStack {
                AhaKeyIslandPreviewStage.background()

                VibeBarHardwareChassis(
                    status: previewStatus,
                    state: state,
                    taskTitle: previewTaskTitle,
                    progress: previewStatus == .coding || previewStatus == .thinking ? 0.55 : 0,
                    keys: previewKeys,
                    isSoundMuted: $isSoundMuted,
                    onOpenMainWindow: {},
                    onQuit: {},
                    onPetTap: {},
                    petAppearance: petAppearance
                )
                .frame(width: min(islandWidth, VibeBarIslandAppearanceSettings.islandWidthMax))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: AhaKeyIslandPreviewStage.cornerRadius, style: .continuous))
        }
        .onAppear {
            petAppearance = VibeBarPetAppearanceSettings.appearance
            keyPadSlots = VibeBarKeyPadSettings.slots
        }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarPetAppearanceSettings.didChangeNotification)) { _ in
            petAppearance = VibeBarPetAppearanceSettings.appearance
        }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarKeyPadSettings.didChangeNotification)) { _ in
            keyPadSlots = VibeBarKeyPadSettings.slots
        }
    }

    private var previewTaskTitle: String {
        switch previewStatus {
        case .listening: return "Voice input active"
        case .thinking: return "Analyzing context"
        case .coding: return "Generating changes"
        case .approval: return "Waiting for your confirm"
        default: return state.agentTaskTitle.isEmpty ? "Ready for next task" : state.agentTaskTitle
        }
    }
}

/// 左槽选项卡片。
struct AhaKeyIslandLeftSlotOptionCard: View {
    let display: VibeBarLeftSlotDisplay
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                optionGlyph
                    .frame(height: 26)
                Text(display.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AhakeySettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AhakeySettingsTheme.accentBlue.opacity(0.55) : AhakeySettingsTheme.divider, lineWidth: isSelected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var optionGlyph: some View {
        switch display {
        case .statusLine:
            Text("A·b")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .deviceName:
            Image(systemName: "keyboard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .battery:
            Image(systemName: "battery.75percent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .agentStatus:
            Text("Think")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .clock:
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .focusTimer:
            Text("25:00")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
                .monospacedDigit()
        case .hidden:
            Text("—")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
    }
}

/// 右槽选项卡片。
struct AhaKeyIslandRightSlotOptionCard: View {
    let display: VibeBarRightSlotDisplay
    let sessionCount: Int
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var focusTimer = VibeBarFocusTimerStore.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                optionGlyph
                    .frame(height: 26)
                Text(display.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AhakeySettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AhakeySettingsTheme.accentBlue.opacity(0.55) : AhakeySettingsTheme.divider, lineWidth: isSelected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var optionGlyph: some View {
        switch display {
        case .sessionCount:
            Text("x\(sessionCount)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .agent:
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.55, blue: 0.18))
                        .frame(width: 8, height: 8)
                }
            }
        case .focusTimer:
            Text(focusTimer.displayText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
                .monospacedDigit()
        case .battery:
            Image(systemName: "battery.75percent")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .lever:
            Text("Auto")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .clock:
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .agentStatus:
            Text("Think")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
        case .hidden:
            Text("—")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
    }
}

/// 常驻岛预览内嵌的状态切换（自动 / 空间 / 运行 / 等待）。
struct AhaKeyIslandStateKindPicker: View {
    @Binding var selection: VibeBarRestingStateKind

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VibeBarRestingStateKind.allCases) { kind in
                let isSelected = selection == kind
                Button {
                    selection = kind
                } label: {
                    HStack(spacing: 4) {
                        Text(kind.title)
                            .font(.system(size: 12, weight: .semibold))
                        if isSelected {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .foregroundStyle(isSelected ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? AhakeySettingsTheme.cardBackground : AhakeySettingsTheme.controlFill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 常驻岛 / 展开岛 / 通用 顶部分段。
struct AhaKeyDynamicIslandSectionPicker: View {
    @Binding var selection: AhaKeyDynamicIslandConfigSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AhaKeyDynamicIslandConfigSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        VStack(spacing: 3) {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selection == section ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.secondaryText)
                            Text(section.subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selection == section ? AhakeySettingsTheme.accentBlue : AhakeySettingsTheme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == section ? AhakeySettingsTheme.controlFill : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AhakeySettingsTheme.cardBackground)
            )
        }
    }
}

/// 深色 Settings 折叠区：低频选项默认收起，避免与预览同级铺开。
struct AhaKeySettingsDisclosureSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AhakeySettingsTheme.rowSubtitleFont)
                                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AhakeySettingsTheme.cardCornerRadius, style: .continuous)
                        .fill(AhakeySettingsTheme.controlFill)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
