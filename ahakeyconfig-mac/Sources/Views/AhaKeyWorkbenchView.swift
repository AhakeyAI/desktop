import AppKit
import SwiftUI

// MARK: - 侧边栏导航项

/// 工作台侧边栏的四个主导航页面。
private enum WorkbenchTab: String, CaseIterable, Identifiable {
    case workbench    // 工作台
    case keyConfig    // 按键配置
    case agentMode    // Agent 模式
    case deviceSystem // 设备与系统

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workbench:    "工作台"
        case .keyConfig:    "按键配置"
        case .agentMode:    "Agent 模式"
        case .deviceSystem: "设备与系统"
        }
    }

    var systemImage: String {
        switch self {
        case .workbench:    "house.fill"
        case .keyConfig:    "keyboard"
        case .agentMode:    "brain.head.profile"
        case .deviceSystem: "gearshape"
        }
    }
}

// MARK: - Agent 类型

private enum AgentType: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case cursor = "Cursor"
    case codex  = "Codex"

    var id: String { rawValue }
}

// MARK: - 工作台主视图

struct AhaKeyWorkbenchView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var embeddedInSettings: Bool = false

    @State private var selectedTab: WorkbenchTab = .agentMode
    @State private var selectedMode: AhaKeyModeSlot
    @State private var selectedKeyRole: AhaKeyKeyRole = .voice
    @State private var studioDraft: AhaKeyStudioDraft
    @State private var selectedAgent: AgentType = .claude
    @State private var autoApprove: Bool = false
    @State private var apiKeyRevealed: Bool = false

    init(bleManager: AhaKeyBLEManager, embeddedInSettings: Bool = false) {
        self.bleManager = bleManager
        self.embeddedInSettings = embeddedInSettings
        let draft = AhaKeyStudioStore.load() ?? .default
        _studioDraft = State(initialValue: draft)
        let mode = AhaKeyModeSlot(rawValue: bleManager.workMode) ?? .mode0
        _selectedMode = State(initialValue: mode)
    }

    // MARK: - 颜色常量

    private let bgPrimary    = Color(red: 0.05, green: 0.07, blue: 0.09)
    private let bgSecondary  = Color(red: 0.09, green: 0.11, blue: 0.13)
    private let bgTertiary   = Color(red: 0.11, green: 0.13, blue: 0.17)
    private let bgCard       = Color(red: 0.14, green: 0.16, blue: 0.20)
    private let accentCyan   = Color(red: 0.35, green: 0.65, blue: 1.0)
    private let accentGreen  = Color(red: 0.25, green: 0.73, blue: 0.31)
    private let accentRed    = Color(red: 0.97, green: 0.32, blue: 0.29)
    private let accentOrange = Color(red: 0.82, green: 0.60, blue: 0.13)
    private let accentPurple = Color(red: 0.74, green: 0.55, blue: 1.0)
    private let accentTeal   = Color(red: 0.22, green: 0.82, blue: 0.75)
    private let textPrimary   = Color.white
    private let textSecondary = Color.white.opacity(0.55)
    private let textTertiary  = Color.white.opacity(0.35)

    private var currentModeDraft: AhaKeyModeDraft {
        studioDraft.draft(for: selectedMode)
    }

    private var syncedStudioDraft: Binding<AhaKeyStudioDraft> {
        Binding(
            get: { studioDraft },
            set: { newValue in
                studioDraft = newValue
                AhaKeyStudioStore.save(newValue)
                VoiceRelayService.shared.updateRoutes(from: newValue)
            }
        )
    }

    var body: some View {
        Group {
            if embeddedInSettings {
                embeddedSettingsLayout
            } else {
                standaloneLayout
            }
        }
        .background(bgPrimary)
        .preferredColorScheme(.dark)
        .frame(
            minWidth: embeddedInSettings ? 0 : 1280,
            minHeight: embeddedInSettings ? 0 : 820
        )
        .onChange(of: bleManager.workMode) { newValue in
            if let slot = AhaKeyModeSlot(rawValue: newValue), slot != selectedMode {
                selectedMode = slot
            }
        }
        .onAppear {
            SwitchStateNotifier.shared.bind(to: bleManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioNavigate)) { notification in
            handleStudioNavigation(notification)
        }
    }

    private var standaloneLayout: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.06))
            VStack(spacing: 0) {
                topStatusBar
                Divider().overlay(Color.white.opacity(0.06))
                contentArea
                Divider().overlay(Color.white.opacity(0.06))
                bottomStatusBar
            }
        }
    }

    private var embeddedSettingsLayout: some View {
        VStack(spacing: 0) {
            embeddedSubTabBar
            Divider().overlay(Color.white.opacity(0.06))
            contentArea
        }
    }

    private var embeddedSubTabBar: some View {
        HStack(spacing: 8) {
            ForEach(WorkbenchTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12))
                        Text(tab.title)
                            .font(.system(size: 12, weight: tab == selectedTab ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == selectedTab ? accentCyan : textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == selectedTab ? accentCyan.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bgSecondary)
    }

    private func handleStudioNavigation(_ notification: Notification) {
        guard let raw = notification.userInfo?[StudioNavigationUserInfoKey.section] as? String,
              let section = StudioNavigationSection(rawValue: raw) else { return }

        switch section {
        case .voiceAgent:
            selectedTab = .agentMode
        case .device:
            if embeddedInSettings {
                StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
            } else {
                selectedTab = .deviceSystem
            }
        case .approve:
            selectedTab = .keyConfig
            selectedKeyRole = .approve
        case .oled:
            selectedTab = .workbench
        case .voice:
            selectedTab = .keyConfig
            selectedKeyRole = .voice
        }
    }

    // MARK: - 业务内容区域

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selectedTab {
            case .workbench:
                HStack(spacing: 0) {
                    centerContent
                    Divider().overlay(Color.white.opacity(0.06))
                    rightPanelWorkbench
                }
            case .keyConfig:
                AhaKeyKeyConfigPageView(
                    bleManager: bleManager,
                    studioDraft: syncedStudioDraft,
                    selectedMode: selectedMode,
                    selectedKeyRole: selectedKeyRole
                )
            case .agentMode:
                HStack(spacing: 0) {
                    agentCenterContent
                    Divider().overlay(Color.white.opacity(0.06))
                    agentRightPanel
                }
            case .deviceSystem:
                if embeddedInSettings {
                    deviceSystemSettingsRedirect
                } else {
                    ScrollView {
                        DeviceInfoView(bleManager: bleManager)
                            .padding(16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var deviceSystemSettingsRedirect: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设备与系统已迁至「我的设备」")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(textPrimary)
            Text("改名、蓝牙占用、设备信息与 Agent 系统控制请到左侧底部「我的设备」查看。")
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开我的设备") {
                StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func openDeviceSystem() {
        if embeddedInSettings {
            StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
        } else {
            selectedTab = .deviceSystem
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Text("A")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("AhaKey Studio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack(spacing: 4) {
                ForEach(WorkbenchTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(tab.title)
                                .font(.system(size: 13, weight: tab == selectedTab ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(tab == selectedTab ? accentCyan : textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tab == selectedTab ? accentCyan.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            deviceCard
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            userCard
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .frame(width: 220)
        .background(bgSecondary)
    }

    private var deviceCard: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bgTertiary)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "keyboard")
                        .font(.system(size: 18))
                        .foregroundStyle(textSecondary)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(bleManager.deviceName ?? "AhaKey Mini")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(bleManager.isConnected ? accentGreen : accentOrange)
                        .frame(width: 7, height: 7)
                    Text(bleManager.isConnected ? "已连接" : "未连接")
                        .font(.system(size: 11))
                        .foregroundStyle(textSecondary)
                    Image(systemName: "battery.75percent")
                        .font(.system(size: 11))
                        .foregroundStyle(textSecondary)
                    Text("\(bleManager.batteryLevel)%")
                        .font(.system(size: 11))
                        .foregroundStyle(textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgTertiary)
        )
    }

    private var userCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentPurple, accentCyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Text("A")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("AhaKey 用户")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(textTertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bgTertiary)
        )
    }

    // MARK: - 顶部状态栏

    private var topStatusBar: some View {
        HStack(spacing: 16) {
            topPill(
                icon: "circle.fill",
                iconColor: bleManager.isConnected ? accentGreen : accentOrange,
                label: bleManager.isConnected ? "已连接" : "未连接",
                value: bleManager.deviceName ?? "等待设备"
            )
            topPill(
                icon: "battery.75percent",
                iconColor: accentGreen,
                label: "电量",
                value: bleManager.isConnected ? "\(bleManager.batteryLevel)%" : "—"
            )
            topPill(
                icon: "square.stack.3d.up",
                iconColor: accentCyan,
                label: "当前模式",
                value: "Agent Mode / \(selectedMode.title)"
            )
            topPill(
                icon: "brain.head.profile",
                iconColor: accentTeal,
                label: "Agent",
                value: "已接入"
            )

            Spacer(minLength: 0)

            Button {
                let next = (selectedMode.rawValue + 1) % AhaKeyModeSlot.allCases.count
                if let slot = AhaKeyModeSlot(rawValue: next) {
                    selectedMode = slot
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12))
                    Text("切换模式")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                openDeviceSystem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                    Text("设置")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(bgSecondary)
    }

    private func topPill(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(textTertiary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textPrimary)
            }
        }
    }

    // MARK: - 工作台中间内容（原有）

    private var centerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modeHeader
                workbenchDeviceVisualization
                keyLegendBar
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgPrimary)
    }

    private var modeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(selectedMode.name + " 确认模式")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textPrimary)

                Text(selectedMode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }

            Text("点按设备上的按键或指示灯，即可查看并调整当前配置。")
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
        }
    }

    private var workbenchDeviceVisualization: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 680)
            let height = width * 0.52
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.18, blue: 0.24),
                                Color(red: 0.12, green: 0.12, blue: 0.17),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)

                VStack(spacing: height * 0.06) {
                    HStack(spacing: width * 0.03) {
                        ledBarView(width: width * 0.52, height: height * 0.18)
                        oledView(width: width * 0.22, height: height * 0.22)
                    }

                    HStack(spacing: width * 0.02) {
                        ForEach(AhaKeyKeyRole.allCases) { role in
                            keyCapView(role: role, size: width * 0.13)
                        }

                        Spacer().frame(width: width * 0.02)

                        toggleSwitchView(width: width * 0.06, height: height * 0.32)
                    }
                }
                .padding(.horizontal, width * 0.06)
                .padding(.vertical, height * 0.08)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 360)
    }

    private func ledBarView(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("灯条")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .frame(height: height * 0.6)

                HStack(spacing: width * 0.06) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(ledSegmentColor(index: i))
                            .frame(width: width * 0.1, height: height * 0.3)
                    }
                }
            }
            .frame(width: width, height: height * 0.6)
        }
    }

    private func ledSegmentColor(index: Int) -> Color {
        let colors: [Color] = [
            accentCyan,
            accentCyan.opacity(0.7),
            Color.blue.opacity(0.8),
            accentCyan.opacity(0.6),
        ]
        return colors[index % colors.count]
    }

    private func oledView(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text(selectedMode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("默认动画")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: width, height: height)
    }

    private func keyCapView(role: AhaKeyKeyRole, size: CGFloat) -> some View {
        let isSelected = selectedKeyRole == role
        let keyDraft = currentModeDraft.key(for: role)

        return Button {
            selectedKeyRole = role
        } label: {
            VStack(spacing: size * 0.06) {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.22, blue: 0.28),
                                    Color(red: 0.16, green: 0.16, blue: 0.22),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                                .stroke(
                                    isSelected ? accentCyan : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 2.5 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? accentCyan.opacity(0.3) : .clear,
                            radius: isSelected ? 12 : 0
                        )

                    CanvasKeyRoleIcon(role: role, color: .white.opacity(0.85), size: size * 0.22)
                        .fixedSize()
                }
                .frame(width: size, height: size)

                Text(keyDraft.description.isEmpty ? role.defaultDescription : keyDraft.description)
                    .font(.system(size: max(size * 0.1, 10), weight: .medium))
                    .foregroundStyle(keyLabelColor(for: role))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func keyLabelColor(for role: AhaKeyKeyRole) -> Color {
        switch role {
        case .voice:   accentCyan
        case .approve: accentGreen
        case .reject:  accentRed
        case .submit:  accentPurple
        }
    }

    private func toggleSwitchView(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: bleManager.switchState == 0 ? .top : .bottom) {
                RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * 0.6, height: width * 0.6)
                    .padding(4)
            }
            .frame(width: width, height: height)

            Text("自动切换")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(textTertiary)
        }
    }

    private var keyLegendBar: some View {
        HStack(spacing: 24) {
            ForEach(AhaKeyKeyRole.allCases) { role in
                let keyDraft = currentModeDraft.key(for: role)
                HStack(spacing: 8) {
                    Text(keyDraft.description.isEmpty ? role.defaultDescription : keyDraft.description)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(keyLabelColor(for: role))
                    Text(legendDescription(for: role))
                        .font(.system(size: 12))
                        .foregroundStyle(textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func legendDescription(for role: AhaKeyKeyRole) -> String {
        switch role {
        case .voice:   "语音输入"
        case .approve: "确认"
        case .reject:  "拒绝"
        case .submit:  "发送 / 执行"
        }
    }

    // MARK: - Agent 模式中间内容

    private var agentCenterContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                agentModeHeader
                agentDeviceVisualization
                agentStatusCards
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgPrimary)
    }

    private var agentModeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text("Claude Agent 执行模式")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textPrimary)

                Text(selectedMode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(accentGreen.opacity(0.15))
                    )
            }

            Text("通过按键、拨杆与状态灯控制 Agent 的执行与授权。")
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
        }
    }

    // MARK: - Agent 设备可视化

    private var agentDeviceVisualization: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 680)
            let height = width * 0.52
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.18, blue: 0.24),
                                Color(red: 0.12, green: 0.12, blue: 0.17),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 16)

                VStack(spacing: height * 0.06) {
                    HStack(spacing: width * 0.03) {
                        agentLedBarView(width: width * 0.52, height: height * 0.18)
                        agentOledView(width: width * 0.22, height: height * 0.22)
                    }

                    HStack(spacing: width * 0.02) {
                        agentKeyCapView(
                            icon: "mic.fill", label: "唤醒 / 语音输入",
                            color: accentCyan, size: width * 0.13
                        )
                        agentKeyCapView(
                            icon: "checkmark", label: "批准 / 继续",
                            color: accentGreen, size: width * 0.13
                        )
                        agentKeyCapView(
                            icon: "xmark", label: "拒绝 / 停止",
                            color: accentRed, size: width * 0.13
                        )
                        agentKeyCapView(
                            icon: "return", label: "发送 / 执行",
                            color: accentPurple, size: width * 0.13
                        )

                        Spacer().frame(width: width * 0.02)

                        agentToggleSwitchView(width: width * 0.06, height: height * 0.32)
                    }
                }
                .padding(.horizontal, width * 0.06)
                .padding(.vertical, height * 0.08)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 360)
    }

    private func agentLedBarView(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("状态灯")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .frame(height: height * 0.6)

                HStack(spacing: width * 0.04) {
                    ForEach(0..<5, id: \.self) { i in
                        let isCenter = i == 2
                        Capsule()
                            .fill(isCenter ? accentTeal : accentCyan.opacity(0.7))
                            .frame(
                                width: isCenter ? width * 0.14 : width * 0.08,
                                height: height * 0.3
                            )
                    }
                }
            }
            .frame(width: width, height: height * 0.6)
        }
    }

    private func agentOledView(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(accentGreen)
                        .frame(width: 6, height: 6)
                    Text("Claude Agent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("在线")
                    .font(.system(size: 10))
                    .foregroundStyle(accentGreen)
            }
        }
        .frame(width: width, height: height)
    }

    private func agentKeyCapView(icon: String, label: String, color: Color, size: CGFloat) -> some View {
        VStack(spacing: size * 0.06) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.22, blue: 0.28),
                                Color(red: 0.16, green: 0.16, blue: 0.22),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.system(size: max(size * 0.09, 9), weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func agentToggleSwitchView(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: autoApprove ? .top : .bottom) {
                RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * 0.6, height: width * 0.6)
                    .padding(4)
            }
            .frame(width: width, height: height)
            .onTapGesture { autoApprove.toggle() }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(autoApprove ? accentGreen : textTertiary)
                        .frame(width: 5, height: 5)
                    Text("自动批准")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(autoApprove ? textPrimary : textTertiary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(!autoApprove ? accentCyan : textTertiary)
                        .frame(width: 5, height: 5)
                    Text("手动确认")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(!autoApprove ? textPrimary : textTertiary)
                }
            }
        }
    }

    // MARK: - Agent 状态卡片行

    private var agentStatusCards: some View {
        HStack(spacing: 16) {
            agentStatusCard(
                icon: "brain.head.profile", iconColor: accentCyan,
                label: "当前 Agent", value: "\(selectedAgent.rawValue) Agent"
            )
            agentStatusCard(
                icon: "shield.checkered", iconColor: accentGreen,
                label: "授权策略", value: autoApprove ? "自动批准" : "手动确认"
            )
            agentStatusCard(
                icon: "bubble.left.fill", iconColor: accentTeal,
                label: "会话状态", value: "待命", valueColor: accentGreen
            )
            agentStatusCard(
                icon: "doc.text.fill", iconColor: textSecondary,
                label: "任务进度", value: "0 个任务"
            )
        }
    }

    private func agentStatusCard(
        icon: String, iconColor: Color,
        label: String, value: String,
        valueColor: Color? = nil
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(valueColor ?? textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Agent 右侧面板

    private var agentRightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Agent 接入
                agentConnectionSection

                // Agent 状态
                agentStatusSection

                // Agent 切换
                agentSwitchSection

                // 状态灯图例
                agentLedLegendSection

                // 操作按钮
                agentActionButtons
            }
            .padding(24)
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(bgSecondary)
    }

    private var agentConnectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent 接入")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(textPrimary)

            // API Key
            HStack(spacing: 10) {
                Text("API Key")
                    .font(.system(size: 13))
                    .foregroundStyle(textSecondary)
                    .frame(width: 56, alignment: .leading)

                HStack(spacing: 6) {
                    Text(apiKeyRevealed ? "sk-proj-abc123...xyz" : "sk-••••••••••••••••••••••")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)

                    Button {
                        apiKeyRevealed.toggle()
                    } label: {
                        Image(systemName: apiKeyRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Button("修改") { openDeviceSystem() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bgTertiary)
            )

            // 状态
            HStack(spacing: 10) {
                Text("状态")
                    .font(.system(size: 13))
                    .foregroundStyle(textSecondary)
                    .frame(width: 56, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accentGreen)
                    Text("已验证")
                        .font(.system(size: 13))
                        .foregroundStyle(accentGreen)
                }

                Spacer(minLength: 0)

                Button("重新验证") { openDeviceSystem() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bgTertiary)
            )
        }
    }

    private var agentStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent 状态")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentGreen)
                        .frame(width: 8, height: 8)
                    Text("在线")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentGreen)
                }

                agentInfoRow(label: "当前", value: "\(selectedAgent.rawValue) Agent")
                agentInfoRow(label: "最近心跳", value: "2s 前")
                agentInfoRow(label: "当前状态", value: "待命", valueColor: accentGreen)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bgTertiary)
            )
        }
    }

    private func agentInfoRow(label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(valueColor ?? textPrimary)
        }
    }

    private var agentSwitchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent 切换")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(textPrimary)

            HStack(spacing: 8) {
                ForEach(AgentType.allCases) { agent in
                    Button {
                        selectedAgent = agent
                    } label: {
                        Text(agent.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                selectedAgent == agent ? .white : textSecondary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        selectedAgent == agent
                                            ? accentTeal
                                            : Color.clear
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        selectedAgent == agent
                                            ? Color.clear
                                            : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var agentLedLegendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("状态灯")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(textPrimary)

            VStack(spacing: 10) {
                ledLegendRow(color: accentCyan, label: "蓝色常亮", meaning: "待命")
                ledLegendRow(color: accentTeal, label: "青色流水", meaning: "执行中")
                ledLegendRow(color: accentOrange, label: "橙色呼吸", meaning: "等待授权")
                ledLegendRow(color: accentGreen, label: "绿色闪烁", meaning: "任务完成")
                ledLegendRow(color: accentRed, label: "红色闪烁", meaning: "错误 / 断开")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bgTertiary)
            )
        }
    }

    private func ledLegendRow(color: Color, label: String, meaning: String) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: 40, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textPrimary)
            Spacer()
            Text(meaning)
                .font(.system(size: 12))
                .foregroundStyle(textSecondary)
        }
    }

    private var agentActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                openDeviceSystem()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                    Text("查看日志")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(bgTertiary)
                )
            }
            .buttonStyle(.plain)

            Button {
                StudioNavigationRouter.shared.selectSettingsTab(.hardware)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 13))
                    Text("同步到键盘")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentRed)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 工作台右侧面板（原有）

    private var rightPanelWorkbench: some View {
        let keyDraft = currentModeDraft.key(for: selectedKeyRole)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(keyDraft.description.isEmpty ? selectedKeyRole.defaultDescription : keyDraft.description) 键配置")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(textPrimary)

                configRow(
                    icon: "mic.fill",
                    iconColor: accentCyan,
                    sectionTitle: "当前功能",
                    title: functionTitle(for: selectedKeyRole),
                    hasChevron: true
                )

                configRow(
                    icon: "waveform",
                    iconColor: accentCyan,
                    sectionTitle: "触发方式",
                    title: triggerTitle(for: selectedKeyRole),
                    hasChevron: true
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷动作")
                        .font(.system(size: 11))
                        .foregroundStyle(textTertiary)
                        .padding(.leading, 4)

                    configActionRow(icon: "pencil", title: "修改映射", hasChevron: true)
                    configActionRow(icon: "play.fill", title: "测试按键", hasChevron: true)
                }
            }
            .padding(24)
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(bgSecondary)
    }

    private func functionTitle(for role: AhaKeyKeyRole) -> String {
        switch role {
        case .voice:   "语音输入"
        case .approve: "确认操作"
        case .reject:  "拒绝操作"
        case .submit:  "发送 / 执行"
        }
    }

    private func triggerTitle(for role: AhaKeyKeyRole) -> String {
        switch role {
        case .voice:   "按住说话 / 松开发送"
        case .approve: "单击触发"
        case .reject:  "单击触发"
        case .submit:  "单击触发"
        }
    }

    private func configRow(
        icon: String, iconColor: Color,
        sectionTitle: String, title: String, hasChevron: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sectionTitle)
                .font(.system(size: 11))
                .foregroundStyle(textTertiary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(textPrimary)

                Spacer()

                if hasChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(textTertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bgTertiary)
            )
        }
    }

    private func configActionRow(icon: String, title: String, hasChevron: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(textSecondary)
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(textPrimary)

            Spacer()

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textTertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgTertiary)
        )
    }

    // MARK: - 底部状态栏

    private var bottomStatusBar: some View {
        HStack(spacing: 20) {
            statusItem(icon: "waveform", iconColor: accentCyan, label: "语音服务", value: "运行中")
            statusDivider
            statusItem(icon: "antenna.radiowaves.left.and.right", iconColor: accentCyan, label: "蓝牙延迟", value: bleManager.isConnected ? "28ms" : "—")
            statusDivider
            statusItem(icon: "doc.text", iconColor: textSecondary, label: "固件", value: bleManager.firmwareRevision)
            statusDivider
            statusItem(icon: "brain.head.profile", iconColor: accentGreen, label: "Agent", value: "在线")
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(bgSecondary)
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 14)
    }

    private func statusItem(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textPrimary)
            }
        }
    }

    // MARK: - 占位页面

    private func placeholderPage(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hammer.fill")
                .font(.system(size: 36))
                .foregroundStyle(textTertiary)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgPrimary)
    }
}
