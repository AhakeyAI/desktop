import SwiftUI

// MARK: - 按键配置页面

/// 原型图「按键配置」页面——卡片式布局，色板跟随 Settings 外观。
/// 展示单个按键的完整配置：功能类型、语音方案、触发方式、绑定键位、按键名称，
/// 以及权限状态和操作按钮。
struct AhaKeyKeyConfigPageView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared

    @Binding var studioDraft: AhaKeyStudioDraft
    let selectedMode: AhaKeyModeSlot
    let selectedKeyRole: AhaKeyKeyRole

    // MARK: - 主题色板（自适应浅/深）

    private var bgPage: Color { AhakeySettingsTheme.contentBackground }
    private var bgCard: Color { AhakeySettingsTheme.cardBackground }
    private var bgCardBorder: Color { AhakeySettingsTheme.divider }
    private var bgField: Color { AhakeySettingsTheme.controlFill }
    private var bgFieldBorder: Color { AhakeySettingsTheme.divider }
    private var accentIndigo: Color { AhakeySettingsTheme.accentBlue }
    private let accentCyan = Color(red: 0.20, green: 0.70, blue: 0.82)
    private let accentPurple = Color(red: 0.48, green: 0.32, blue: 0.86)
    private let accentGreen = Color(red: 0.18, green: 0.68, blue: 0.32)
    private var textPrimary: Color { AhakeySettingsTheme.primaryText }
    private var textSecondary: Color { AhakeySettingsTheme.secondaryText }
    private var textTertiary: Color { AhakeySettingsTheme.tertiaryText }

    // MARK: - 数据

    private var currentModeDraft: AhaKeyModeDraft {
        studioDraft.draft(for: selectedMode)
    }

    private var keyDraft: AhaKeyKeyDraft {
        currentModeDraft.key(for: selectedKeyRole)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader
                statusSummaryCard
                keyConfigCard
                permissionsCard
                usageInstructionsCard
            }
            .padding(28)
        }
        .background(bgPage)
    }

    // MARK: - 页面头部

    private var pageHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AhakeySettingsTheme.accentBlue.opacity(0.85))
                    .frame(width: 52, height: 52)

                Image(systemName: selectedKeyRole.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Key \(selectedKeyRole.rawValue + 1)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(textPrimary)
                Text(selectedKeyRole.title)
                    .font(.system(size: 14))
                    .foregroundStyle(textSecondary)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - 状态概览卡片

    private var statusSummaryCard: some View {
        HStack(spacing: 0) {
            // 当前功能
            summaryItem(
                icon: "waveform",
                iconBg: accentIndigo,
                label: "当前功能",
                value: functionTitle
            )

            summaryDivider

            // 当前方案
            summaryItem(
                icon: "square.3.layers.3d",
                iconBg: accentPurple.opacity(0.2),
                iconFg: accentPurple,
                label: "当前方案",
                value: schemeTitle
            )

            summaryDivider

            // 当前状态
            summaryItem(
                icon: "checkmark.circle.fill",
                iconBg: Color.clear,
                iconFg: accentGreen,
                label: "当前状态",
                value: statusTitle
            )
        }
        .padding(20)
        .background(cardBackground)
    }

    private func summaryItem(
        icon: String,
        iconBg: Color,
        iconFg: Color = .white,
        label: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if iconBg != .clear {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 36, height: 36)
                }
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconFg)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(textTertiary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textPrimary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 8)
    }

    // MARK: - 按键配置卡片

    private var keyConfigCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡片标题行
            HStack {
                Text("按键配置")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(textPrimary)
                Spacer()
                Button {
                    // 同步到设备
                } label: {
                    Text("同步到设备")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accentIndigo)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!bleManager.isConnected)
            }
            .padding(.bottom, 20)

            // 表单行
            VStack(spacing: 16) {
                formPickerRow(
                    label: "功能类型",
                    value: functionTitle,
                    options: ["语音输入", "确认操作", "拒绝操作", "发送 / 执行"],
                    onChange: { _ in }
                )

                formPickerRow(
                    label: "语音方案",
                    value: schemeTitle,
                    options: VoicePreset.allCases.filter(\.availableInV1).map(\.title),
                    onChange: { newTitle in
                        if let preset = VoicePreset.allCases.first(where: { $0.title == newTitle }) {
                            updateKey { key in
                                key.voicePreset = preset
                                if preset != .custom {
                                    key.shortcut = preset.defaultBinding
                                }
                            }
                        }
                    }
                )

                formPickerRow(
                    label: "触发方式",
                    value: triggerTitle,
                    options: ["单击开始，再按结束", "按住说话 / 松开发送", "单击触发"],
                    onChange: { _ in }
                )

                formPickerRow(
                    label: "绑定键位",
                    value: boundKeyTitle,
                    options: ["F18", "F19", "F20"] + HIDUsage.allOptions.prefix(20).map(\.name),
                    onChange: { newName in
                        if let option = HIDUsage.allOptions.first(where: { $0.name == newName }) {
                            updateKey { key in
                                key.shortcut = ShortcutBinding(keyCode: option.code)
                            }
                        }
                    }
                )

                formTextFieldRow(
                    label: "按键名称",
                    text: keyDescriptionBinding
                )
            }
        }
        .padding(24)
        .background(cardBackground)
    }

    private func formPickerRow(
        label: String,
        value: String,
        options: [String],
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(textSecondary)
                .frame(width: 80, alignment: .leading)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        onChange(option)
                    }
                }
            } label: {
                HStack {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(bgField)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(bgFieldBorder, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func formTextFieldRow(
        label: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(textSecondary)
                .frame(width: 80, alignment: .leading)

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(bgField)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(bgFieldBorder, lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - 状态与权限卡片

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("状态与权限")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(textPrimary)

            // 权限状态指示器
            HStack(spacing: 10) {
                permissionBadge(
                    title: "后台监听",
                    granted: voiceRelay.isListening
                )
                permissionBadge(
                    title: "麦克风",
                    granted: nativeSpeech.microphoneGranted
                )
                permissionBadge(
                    title: "输入监控",
                    granted: voiceRelay.inputMonitoringGranted
                )
                permissionBadge(
                    title: "语音转写",
                    granted: nativeSpeech.speechRecognitionGranted
                )
            }

            // 操作按钮
            HStack(spacing: 12) {
                actionButton(
                    icon: "shield.lefthalf.filled",
                    title: "检查权限"
                ) {
                    voiceRelay.refreshPermissions(requestIfNeeded: true)
                    nativeSpeech.refreshPermissions(requestIfNeeded: true)
                }

                actionButton(
                    icon: "waveform",
                    title: "测试按键"
                ) {
                    if selectedKeyRole == .voice {
                        nativeSpeech.toggleRecordingFromVoiceKey()
                    }
                }
            }
        }
        .padding(24)
        .background(cardBackground)
    }

    private func permissionBadge(title: String, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? accentGreen : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textPrimary)
                Text(granted ? "已开启" : "未开启")
                    .font(.system(size: 10))
                    .foregroundStyle(textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bgField)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(bgFieldBorder, lineWidth: 1)
                )
        )
    }

    private func actionButton(
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bgField)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(bgFieldBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 使用说明（可折叠）

    @State private var showsUsageInstructions = false

    private var usageInstructionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsUsageInstructions.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(textTertiary)
                    Text("使用说明")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Image(systemName: showsUsageInstructions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(textTertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if showsUsageInstructions {
                Divider()
                    .overlay(Color.white.opacity(0.06))

                VStack(alignment: .leading, spacing: 10) {
                    instructionStep("1", "在上方「功能类型」中选择这个按键的用途。")
                    instructionStep("2", "如果是语音键，选择语音方案和触发方式。")
                    instructionStep("3", "在「绑定键位」中设置底层 HID 键码。")
                    instructionStep("4", "填写按键名称，切换模式时 OLED 会短暂显示。")
                    instructionStep("5", "点击「同步到设备」把配置写入键盘。")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardBackground)
    }

    private func instructionStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(accentCyan)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(accentCyan.opacity(0.12))
                )
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(textSecondary)
        }
    }

    // MARK: - 通用

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(bgCardBorder, lineWidth: 1)
            )
    }

    // MARK: - 计算属性

    private var functionTitle: String {
        switch selectedKeyRole {
        case .voice:   "语音输入"
        case .approve: "确认操作"
        case .reject:  "拒绝操作"
        case .submit:  "发送 / 执行"
        }
    }

    private var schemeTitle: String {
        if selectedKeyRole == .voice {
            return (keyDraft.voicePreset ?? .custom).title
        }
        return "—"
    }

    private var triggerTitle: String {
        if selectedKeyRole == .voice {
            switch keyDraft.voicePreset ?? .custom {
            case .macOSNative, .claudeCode:
                return "单击开始，再按结束"
            case .typeless, .wechat:
                return "按住说话 / 松开发送"
            default:
                return "单击触发"
            }
        }
        return "单击触发"
    }

    private var boundKeyTitle: String {
        keyDraft.shortcut.displayLabel
    }

    private var statusTitle: String {
        if selectedKeyRole == .voice {
            let hasPerms = voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted
            return hasPerms ? "可用" : "需要权限"
        }
        return keyDraft.shortcut.isConfigured ? "可用" : "未配置"
    }

    // MARK: - 数据绑定

    private var keyDescriptionBinding: Binding<String> {
        Binding(
            get: { keyDraft.description },
            set: { newValue in
                updateKey { key in
                    key.description = String(newValue.prefix(20))
                }
            }
        )
    }

    private func updateKey(_ transform: (inout AhaKeyKeyDraft) -> Void) {
        var next = studioDraft
        var mode = next.draft(for: selectedMode)
        var key = mode.key(for: selectedKeyRole)
        transform(&key)
        mode.updateKey(key)
        next.updateMode(mode)
        studioDraft = next
    }
}
