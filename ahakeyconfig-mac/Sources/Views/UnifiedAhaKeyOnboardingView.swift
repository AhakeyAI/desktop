import SwiftUI

enum UnifiedOnboardingStorage {
    static let completedKey = "AhaKey.UnifiedOnboarding.v2.completed"
    static let micGrantedKey = "AhaKey.UnifiedOnboarding.v2.micPreGranted"
    static let pasteGrantedKey = "AhaKey.UnifiedOnboarding.v2.pastePreGranted"
}

struct AhaKeyOnboardingPermissionState: Equatable {
    var bluetoothPermissionGranted: Bool
    var bluetoothPoweredOn: Bool
    var inputMonitoringGranted: Bool
    var accessibilityGranted: Bool
    var microphoneGranted: Bool
    var speechRecognitionGranted: Bool
    var siriEnabled: Bool
    var dictationEnabled: Bool
    var voiceSummary: String
    var speechSummary: String
    var isRecording: Bool
    var transcriptPreview: String
    var lastCommittedText: String
    var speechStatusMessage: String

    var bluetoothReady: Bool {
        bluetoothPermissionGranted && bluetoothPoweredOn
    }

    var backgroundPermissionsGranted: Bool {
        inputMonitoringGranted && accessibilityGranted
    }

    var nativeSpeechPermissionsGranted: Bool {
        microphoneGranted && speechRecognitionGranted && siriEnabled && dictationEnabled
    }

    var allPermissionsGranted: Bool {
        bluetoothReady && backgroundPermissionsGranted && nativeSpeechPermissionsGranted
    }

    var canTrySpeechInput: Bool {
        microphoneGranted && speechRecognitionGranted
    }
}

struct AhaKeyOnboardingActions {
    var requestPermissions: () -> Void
    var requestPermission: (AhaKeyOnboardingPermissionKind) -> Void
    var recheckPermissions: () -> Void
    var openSystemSettings: () -> Void
    var toggleTryExperience: () -> Void
}

enum AhaKeyOnboardingPermissionKind {
    case bluetooth
    case inputMonitoring
    case accessibility
    case microphone
    case speechRecognition
    case siri
    case dictation
}

struct UnifiedAhaKeyOnboardingView: View {
    var permissionState: AhaKeyOnboardingPermissionState
    var actions: AhaKeyOnboardingActions
    var onCompleted: (_ micGranted: Bool, _ pasteGranted: Bool) -> Void

    @State private var step: AhaKeyOnboardingStep = .welcome
    @State private var didRunTryExperience = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 980
            let contentMinHeight = max(420, geometry.size.height - 116)
            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.45)
                if compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            mainPanel
                            guidePanel
                        }
                        .padding(24)
                        .padding(.bottom, 12)
                    }
                } else {
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            mainPanel
                                .frame(width: max(500, geometry.size.width * 0.48), alignment: .topLeading)
                                .padding(.horizontal, 48)
                                .padding(.vertical, 34)
                                .background(Color(nsColor: .textBackgroundColor))

                            Divider().opacity(0.45)

                            guidePanel
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.horizontal, 46)
                                .padding(.vertical, 34)
                                .background(Color(nsColor: .windowBackgroundColor))
                        }
                        .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)
                    }
                }
                Divider().opacity(0.45)
                bottomNavigationBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .onChange(of: permissionState.transcriptPreview) { newValue in
            if !newValue.isEmpty {
                didRunTryExperience = true
            }
        }
        .onChange(of: permissionState.lastCommittedText) { newValue in
            if !newValue.isEmpty {
                didRunTryExperience = true
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            stepper
            Spacer(minLength: 0)
            Button("跳过") {
                finish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 22)
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // 顶部步骤导航，所有步骤均可点击跳转
    private var stepper: some View {
        HStack(spacing: 12) {
            ForEach(AhaKeyOnboardingStep.allCases) { item in
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            step = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 15, weight: step == item ? .semibold : .medium))
                            .foregroundStyle(step == item ? Color.primary : Color.secondary)
                            .frame(width: 78, height: 34)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(step == item ? Color.primary : Color.clear)
                                    .frame(height: 2)
                            }
                    }
                    .buttonStyle(.plain)

                    if item != AhaKeyOnboardingStep.allCases.last {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Main Panel

    @ViewBuilder
    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case .welcome:
                welcomePanel
            case .systemPermissions:
                systemPermissionsPanel
            case .voicePermissions:
                voicePermissionsPanel
            case .tryInput:
                tryInputPanel
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var welcomePanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("在这台 Mac 上设置 AhaKey")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("完成键盘连接、后台语音键接管、macOS 原生语音和一次真实输入体验。")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                onboardingCard(systemImage: "keyboard", title: "连接与控制", detail: "开启蓝牙后，AhaKey Studio 会接管出厂语音键并同步当前 Mode。")
                onboardingCard(systemImage: "lock.shield", title: "分步授权", detail: "先设置蓝牙、输入监控和辅助功能，再设置麦克风、语音转写、Siri 与听写。")
                onboardingCard(systemImage: "mic", title: "体验输入", detail: "最后可以直接口述一句话，确认识别和写入链路都已准备好。")
            }
        }
    }

    private var systemPermissionsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                title: "第一步：系统控制授权",
                detail: "这些权限用于连接键盘，以及让语音键在后台稳定地触发 AhaKey Studio。"
            )

            VStack(spacing: 12) {
                PermissionStatusRow(
                    title: "蓝牙",
                    detail: bluetoothDetail,
                    granted: permissionState.bluetoothReady,
                    actionTitle: permissionState.bluetoothReady ? nil : "申请",
                    action: { actions.requestPermission(.bluetooth) }
                )
                PermissionStatusRow(
                    title: "输入监控",
                    detail: "允许 AhaKey Studio 在后台监听实体语音键。",
                    granted: permissionState.inputMonitoringGranted,
                    actionTitle: permissionState.inputMonitoringGranted ? nil : "申请",
                    action: { actions.requestPermission(.inputMonitoring) }
                )
                PermissionStatusRow(
                    title: "辅助功能",
                    detail: "允许 AhaKey Studio 把语音键转换成 macOS 原生转写或 Fn/Globe。",
                    granted: permissionState.accessibilityGranted,
                    actionTitle: permissionState.accessibilityGranted ? nil : "申请",
                    action: { actions.requestPermission(.accessibility) }
                )
            }

            HStack(spacing: 10) {
                Button("重新检查") {
                    actions.recheckPermissions()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

        }
    }

    private var voicePermissionsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                title: "第二步：macOS 原生语音授权",
                detail: "默认使用 macOS 原生语音时，需要麦克风、语音转写、Siri 与听写都可用。"
            )

            VStack(spacing: 12) {
                PermissionStatusRow(
                    title: "麦克风",
                    detail: "允许 AhaKey Studio 使用苹果原生语音采集。",
                    granted: permissionState.microphoneGranted,
                    actionTitle: permissionState.microphoneGranted ? nil : "申请",
                    action: { actions.requestPermission(.microphone) }
                )
                PermissionStatusRow(
                    title: "语音转写",
                    detail: "允许 AhaKey Studio 使用苹果原生语音识别。",
                    granted: permissionState.speechRecognitionGranted,
                    actionTitle: permissionState.speechRecognitionGranted ? nil : "申请",
                    action: { actions.requestPermission(.speechRecognition) }
                )
                PermissionStatusRow(
                    title: "Siri",
                    detail: "在系统设置 > Siri 与聚焦里开启 Siri。",
                    granted: permissionState.siriEnabled,
                    actionTitle: permissionState.siriEnabled ? nil : "打开设置",
                    action: { actions.requestPermission(.siri) }
                )
                PermissionStatusRow(
                    title: "听写",
                    detail: "在系统设置 > 键盘 > 听写里开启听写。",
                    granted: permissionState.dictationEnabled,
                    actionTitle: permissionState.dictationEnabled ? nil : "打开设置",
                    action: { actions.requestPermission(.dictation) }
                )
            }

            HStack(spacing: 10) {
                Button("重新检查") {
                    actions.recheckPermissions()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

        }
    }

    private var tryInputPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                title: "第三步：体验输入",
                detail: "按下方按钮或键盘上的语音键，说一句话，再结束录音，确认文字可以写入当前光标。"
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(permissionState.isRecording ? Color.red : (permissionState.canTrySpeechInput ? Color.green : Color.orange))
                        .frame(width: 10, height: 10)
                    Text(permissionState.isRecording ? "录音中" : (permissionState.canTrySpeechInput ? "语音已准备" : "仍缺语音权限"))
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(tryPreviewText)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                Text(permissionState.speechStatusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(permissionState.isRecording ? "结束并写入" : "开始试说") {
                    didRunTryExperience = true
                    actions.toggleTryExperience()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!permissionState.canTrySpeechInput)

                Button("重新检查") {
                    actions.recheckPermissions()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

        }
    }

    // MARK: - Guide Panel（右侧，分组高亮）

    private var guidePanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(step.guideTitle)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
            Text(step.guideDetail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                PermissionGroupSection(
                    groupLabel: "系统授权",
                    isHighlighted: step == .systemPermissions,
                    items: [
                        ("蓝牙", permissionState.bluetoothReady),
                        ("输入监控", permissionState.inputMonitoringGranted),
                        ("辅助功能", permissionState.accessibilityGranted),
                    ]
                )

                PermissionGroupSection(
                    groupLabel: "语音授权",
                    isHighlighted: step == .voicePermissions || step == .tryInput,
                    items: [
                        ("麦克风", permissionState.microphoneGranted),
                        ("语音转写", permissionState.speechRecognitionGranted),
                        ("Siri", permissionState.siriEnabled),
                        ("听写", permissionState.dictationEnabled),
                    ]
                )
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("当前状态")
                    .font(.system(size: 15, weight: .semibold))
                Text(permissionState.voiceSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(permissionState.speechSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom Navigation（文字次级按钮）

    private var bottomNavigationBar: some View {
        HStack(spacing: 0) {
            Spacer()

            if step != .welcome {
                Button("上一步") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = step.previous
                    }
                }
                .buttonStyle(OnboardingTextButtonStyle())
            }

            Button(bottomNextTitle) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    goForward()
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .padding(.leading, step == .welcome ? 0 : 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var bottomNextTitle: String {
        switch step {
        case .welcome: return "开始设置"
        case .tryInput: return "进入工作台"
        default: return "下一步"
        }
    }

    // MARK: - Helpers

    private var bluetoothDetail: String {
        if !permissionState.bluetoothPermissionGranted {
            return "允许 AhaKey Studio 扫描并连接 AhaKey 键盘。"
        }
        if !permissionState.bluetoothPoweredOn {
            return "已授权，但系统蓝牙当前关闭，请在控制中心或系统设置中打开。"
        }
        return "蓝牙可用，可以扫描并连接键盘。"
    }

    private var tryPreviewText: String {
        if !permissionState.transcriptPreview.isEmpty {
            return permissionState.transcriptPreview
        }
        if !permissionState.lastCommittedText.isEmpty {
            return permissionState.lastCommittedText
        }
        return "这里会显示实时识别或最近写入的内容。"
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingCard(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func goForward() {
        if step == .tryInput {
            finish()
            return
        }
        step = AhaKeyOnboardingStep(rawValue: min(AhaKeyOnboardingStep.tryInput.rawValue, step.rawValue + 1)) ?? .tryInput
    }

    private func finish() {
        UserDefaults.standard.set(permissionState.microphoneGranted, forKey: UnifiedOnboardingStorage.micGrantedKey)
        UserDefaults.standard.set(permissionState.backgroundPermissionsGranted, forKey: UnifiedOnboardingStorage.pasteGrantedKey)
        onCompleted(permissionState.microphoneGranted, permissionState.backgroundPermissionsGranted)
    }
}

// MARK: - Permission Group Section（右侧分组视窗）

private struct PermissionGroupSection: View {
    var groupLabel: String
    var isHighlighted: Bool
    var items: [(String, Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(groupLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.0) { title, granted in
                    summaryRow(title: title, granted: granted)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHighlighted)
    }

    private func summaryRow(title: String, granted: Bool) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(granted ? "已开启" : "待开启")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(granted ? Color.green : Color.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Permission Status Row

private struct PermissionStatusRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(granted ? "已开启" : "待开启")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(granted ? Color.green : Color.orange)
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                if granted {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(true)
                    .padding(.top, 1)
                } else {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .padding(.top, 1)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Onboarding Steps

private enum AhaKeyOnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case systemPermissions
    case voicePermissions
    case tryInput

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .systemPermissions: return "系统授权"
        case .voicePermissions: return "语音授权"
        case .tryInput: return "开始体验"
        }
    }

    var previous: AhaKeyOnboardingStep {
        AhaKeyOnboardingStep(rawValue: max(0, rawValue - 1)) ?? .welcome
    }

    var guideTitle: String {
        switch self {
        case .welcome: return "设置路线"
        case .systemPermissions: return "先让键盘和后台控制可用"
        case .voicePermissions: return "再打开 macOS 原生语音"
        case .tryInput: return "最后试一次真实输入"
        }
    }

    var guideDetail: String {
        switch self {
        case .welcome:
            return "引导会按实际功能分为系统授权、语音授权和体验输入，完成后进入主工作台。"
        case .systemPermissions:
            return "蓝牙负责设备连接；输入监控和辅助功能负责后台接管语音键。"
        case .voicePermissions:
            return "麦克风和语音转写负责识别；Siri 与听写是 macOS 原生语音链路的系统开关。"
        case .tryInput:
            return "这里使用软件内同一套语音链路测试，不再只是展示授权状态。"
        }
    }
}

// MARK: - Button Styles

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1.0), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.7 : 1.0), in: RoundedRectangle(cornerRadius: 7))
    }
}

// 次级文字按钮（底部导航"上一步"使用）
private struct OnboardingTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.secondary : Color.primary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .contentShape(Rectangle())
    }
}
