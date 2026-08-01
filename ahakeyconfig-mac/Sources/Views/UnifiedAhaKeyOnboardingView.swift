import SwiftUI

enum UnifiedOnboardingStorage {
    static let completedKey = "AhaKey.UnifiedOnboarding.v2.completed"
    static let micGrantedKey = "AhaKey.UnifiedOnboarding.v2.micPreGranted"
    static let pasteGrantedKey = "AhaKey.UnifiedOnboarding.v2.pastePreGranted"
    static let currentStepKey = "AhaKey.UnifiedOnboarding.v2.currentStep"
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
    /// 空串 = 自动跟随系统首选语言
    var speechLocaleIdentifier: String
    var activeLocaleDescription: String
    var availableSpeechLocales: [SpeechLocaleOption]

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
    var setSpeechLocale: (String) -> Void
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

    @State private var step: AhaKeyOnboardingStep = .restoredProgress
    @State private var didRunTryExperience = false
    @State private var tryInputFieldText = ""
    @FocusState private var tryInputFieldFocused: Bool

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
        .onAppear {
            resumeProgressIfReady()
        }
        .onChange(of: step) { newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: UnifiedOnboardingStorage.currentStepKey)
        }
        .onChange(of: permissionState) { _ in
            resumeProgressIfReady()
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
                            moveToStep(item)
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
            case .dialogPermissions:
                dialogPermissionsPanel
            case .settingsPermissions:
                settingsPermissionsPanel
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
                onboardingCard(systemImage: "lock.shield", title: "分步授权", detail: "先完成蓝牙、麦克风、语音转写等弹窗授权，再依次开启 Siri、听写、辅助功能，最后处理输入监控并重启。")
                onboardingCard(systemImage: "mic", title: "体验输入", detail: "最后可以直接口述一句话，确认识别和写入链路都已准备好。")
            }
        }
    }

    private var dialogPermissionsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                title: "第一步：弹窗确认授权",
                detail: "以下权限点击「申请」后会弹出系统对话框，直接点允许即可。"
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
            }

            HStack(spacing: 10) {
                Button("重新检查") {
                    actions.recheckPermissions()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

        }
    }

    private var settingsPermissionsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader(
                title: "第二步：系统设置授权",
                detail: "以下权限需要前往系统设置手动开启，点击「打开设置」后在系统设置中操作。"
            )

            VStack(spacing: 12) {
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
                PermissionStatusRow(
                    title: "辅助功能",
                    detail: "允许 AhaKey Studio 把语音键转换成 macOS 原生转写或 Fn/Globe。",
                    granted: permissionState.accessibilityGranted,
                    actionTitle: permissionState.accessibilityGranted ? nil : "打开设置",
                    action: { actions.requestPermission(.accessibility) }
                )
                PermissionStatusRow(
                    title: "输入监控",
                    detail: "允许 AhaKey Studio 在后台监听实体语音键；设置完成后通常需要退出并重新打开。",
                    granted: permissionState.inputMonitoringGranted,
                    actionTitle: permissionState.inputMonitoringGranted ? nil : "打开设置",
                    action: {
                        UserDefaults.standard.set(AhaKeyOnboardingStep.tryInput.rawValue, forKey: UnifiedOnboardingStorage.currentStepKey)
                        actions.requestPermission(.inputMonitoring)
                    }
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
                detail: "请蓝牙连接小键盘后，将光标放在这里，按下麦克风键开始说话。"
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("识别语言")
                        .font(.system(size: 15, weight: .semibold))
                    Picker("", selection: Binding(
                        get: { permissionState.speechLocaleIdentifier },
                        set: { actions.setSpeechLocale($0) }
                    )) {
                        Text("自动（跟随系统）").tag("")
                        Divider()
                        ForEach(permissionState.availableSpeechLocales) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    Spacer(minLength: 0)
                }
                Text("当前生效：\(permissionState.activeLocaleDescription)。说的语言和这里不一致就会转写成乱码，先选对再试。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(permissionState.isRecording ? Color.red : (permissionState.canTrySpeechInput ? Color.green : Color.orange))
                        .frame(width: 10, height: 10)
                    Text(permissionState.isRecording ? "录音中" : (permissionState.canTrySpeechInput ? "语音已准备" : "仍缺语音权限"))
                        .font(.system(size: 15, weight: .semibold))
                }

                ZStack(alignment: .topLeading) {
                    if tryInputFieldText.isEmpty {
                        Text("请蓝牙连接小键盘后，将光标放在这里，按下麦克风键开始说话")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $tryInputFieldText)
                        .font(.system(size: 18, weight: .medium))
                        .focused($tryInputFieldFocused)
                        .modifier(HideScrollContentBackgroundModifier())
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .onAppear { tryInputFieldFocused = true }

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
                    groupLabel: "弹窗授权",
                    isHighlighted: step == .dialogPermissions,
                    items: [
                        ("蓝牙", permissionState.bluetoothReady),
                        ("麦克风", permissionState.microphoneGranted),
                        ("语音转写", permissionState.speechRecognitionGranted),
                    ]
                )

                PermissionGroupSection(
                    groupLabel: "系统设置授权",
                    isHighlighted: step == .settingsPermissions || step == .tryInput,
                    items: [
                        ("Siri", permissionState.siriEnabled),
                        ("听写", permissionState.dictationEnabled),
                        ("辅助功能", permissionState.accessibilityGranted),
                        ("输入监控", permissionState.inputMonitoringGranted),
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
                        moveToStep(step.previous)
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

    private var manualSettingsPermissionsGranted: Bool {
        permissionState.siriEnabled &&
            permissionState.dictationEnabled &&
            permissionState.accessibilityGranted &&
            permissionState.inputMonitoringGranted
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

    private func moveToStep(_ next: AhaKeyOnboardingStep) {
        step = next
        UserDefaults.standard.set(next.rawValue, forKey: UnifiedOnboardingStorage.currentStepKey)
    }

    private func resumeProgressIfReady() {
        guard step == .settingsPermissions, manualSettingsPermissionsGranted else { return }
        moveToStep(.tryInput)
    }

    private func goForward() {
        if step == .tryInput {
            finish()
            return
        }
        moveToStep(AhaKeyOnboardingStep(rawValue: min(AhaKeyOnboardingStep.tryInput.rawValue, step.rawValue + 1)) ?? .tryInput)
    }

    private func finish() {
        UserDefaults.standard.set(permissionState.microphoneGranted, forKey: UnifiedOnboardingStorage.micGrantedKey)
        UserDefaults.standard.set(permissionState.backgroundPermissionsGranted, forKey: UnifiedOnboardingStorage.pasteGrantedKey)
        UserDefaults.standard.removeObject(forKey: UnifiedOnboardingStorage.currentStepKey)
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
    static var restoredProgress: AhaKeyOnboardingStep {
        let rawValue = UserDefaults.standard.integer(forKey: UnifiedOnboardingStorage.currentStepKey)
        return AhaKeyOnboardingStep(rawValue: rawValue) ?? .welcome
    }

    case welcome
    case dialogPermissions
    case settingsPermissions
    case tryInput

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "欢迎"
        case .dialogPermissions: return "弹窗授权"
        case .settingsPermissions: return "系统设置"
        case .tryInput: return "开始体验"
        }
    }

    var previous: AhaKeyOnboardingStep {
        AhaKeyOnboardingStep(rawValue: max(0, rawValue - 1)) ?? .welcome
    }

    var guideTitle: String {
        switch self {
        case .welcome: return "设置路线"
        case .dialogPermissions: return "先完成弹窗确认的权限"
        case .settingsPermissions: return "再到系统设置中开启"
        case .tryInput: return "最后试一次真实输入"
        }
    }

    var guideDetail: String {
        switch self {
        case .welcome:
            return "引导分两步授权：先完成系统弹窗确认的权限，再前往系统设置开启其余权限，最后体验输入。"
        case .dialogPermissions:
            return "蓝牙、麦克风和语音转写可以直接弹窗确认，点击「申请」后在弹窗中允许即可。"
        case .settingsPermissions:
            return "请依次开启 Siri、听写、辅助功能，最后开启输入监控。输入监控设置后通常需要退出并重新打开，本引导会记住进度。"
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

private struct HideScrollContentBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
