import SwiftUI

/// 用户中心「设置」：外观、权限、接入、设备联动。
struct AhaKeyUserCenterSettingsContent: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var onOpenAccount: (() -> Void)? = nil

    @StateObject private var cloudAccount = CloudAccountManager.shared
    @StateObject private var optimizer = AhaTypeTextOptimizer.shared
    @ObservedObject private var agentManager = AgentManager.shared
    @ObservedObject private var voiceRelay = VoiceRelayService.shared
    @ObservedObject private var nativeSpeech = NativeSpeechTranscriptionService.shared

    @AppStorage(AhaKeyAppearanceMode.storageKey) private var appearanceModeRaw = AhaKeyAppearanceMode.defaultMode.rawValue
    @AppStorage(AhakeyGeneralSettingsStore.languageKey) private var languageRaw = AhaKeyAppLanguage.system.rawValue
    @AppStorage(AhakeyGeneralSettingsStore.regionKey) private var regionRaw = AhaKeyAppRegion.system.rawValue

    @State private var apiKeyDraft = AhakeyGeneralSettingsStore.agentAPIKey
    @State private var apiKeyRevealed = false
    @State private var apiKeySavedMessage: String?
    @State private var showAppearanceLanguage = true
    @State private var showPermissions = false
    @State private var showServices = false
    @State private var showDeviceLinkage = false
    @FocusState private var apiKeyFocused: Bool

    private var permissionsReady: Bool {
        voiceRelay.inputMonitoringGranted
            && voiceRelay.accessibilityGranted
            && nativeSpeech.microphoneGranted
            && nativeSpeech.speechRecognitionGranted
    }

    private var appearanceBinding: Binding<AhaKeyAppearanceMode> {
        Binding(
            get: { AhaKeyAppearanceMode(rawValue: appearanceModeRaw) ?? .defaultMode },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var languageBinding: Binding<AhaKeyAppLanguage> {
        Binding(
            get: { AhaKeyAppLanguage(rawValue: languageRaw) ?? .system },
            set: { languageRaw = $0.rawValue }
        )
    }

    private var regionBinding: Binding<AhaKeyAppRegion> {
        Binding(
            get: { AhaKeyAppRegion(rawValue: regionRaw) ?? .system },
            set: { regionRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AhaKeySettingsDisclosureSection(
                title: "外观与语言",
                subtitle: "主题、界面语言与地区格式",
                isExpanded: $showAppearanceLanguage
            ) {
                appearanceCard
                languageRegionCard
            }

            AhaKeySettingsDisclosureSection(
                title: "权限与隐私",
                subtitle: permissionsReady ? "系统权限已就绪" : "一次性授权，用于语音与快捷键联动",
                isExpanded: $showPermissions
            ) {
                permissionsCard
                privacyCard
            }
            .featureCoachTip(.userCenterPermissions, isActive: true, alignment: .topTrailing)
            .onReceive(NotificationCenter.default.publisher(for: .ahaKeyExpandUserCenterPermissions)) { _ in
                showPermissions = true
            }

            AhaKeySettingsDisclosureSection(
                title: "接入与服务",
                subtitle: "Agent API 与 AhaType",
                isExpanded: $showServices
            ) {
                agentAPISection
                ahaTypeSection
            }

            AhaKeySettingsDisclosureSection(
                title: "设备联动",
                subtitle: "Studio 与 Agent 蓝牙占用",
                isExpanded: $showDeviceLinkage
            ) {
                bluetoothOwnerSection
            }
        }
        .onAppear {
            apiKeyDraft = AhakeyGeneralSettingsStore.agentAPIKey
            optimizer.refreshFromDisk()
            voiceRelay.refreshPermissions(deferredTCCRequery: true)
            nativeSpeech.refreshPermissions(deferredTCCRequery: true)
        }
    }

    private var appearanceCard: some View {
        AhakeySettingsCard(sectionTitle: "外观") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("外观", selection: appearanceBinding) {
                    ForEach(AhaKeyAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("默认深色。切换后侧栏、内容区与卡片整页同步；跟随系统时随 macOS 浅色 / 深色自动切换。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var languageRegionCard: some View {
        AhakeySettingsCard(sectionTitle: "语言与地区") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("语言")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer()
                    Picker("", selection: languageBinding) {
                        ForEach(AhaKeyAppLanguage.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }

                AhakeySettingsCardDivider()

                HStack {
                    Text("地区")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer()
                    Picker("", selection: regionBinding) {
                        ForEach(AhaKeyAppRegion.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }

                Text("完整界面翻译后续补齐；本版先影响日期/数字等系统格式与后续本地化入口。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var permissionsCard: some View {
        AhakeySettingsCard(sectionTitle: "系统权限") {
            permissionRow("输入监控", granted: voiceRelay.inputMonitoringGranted)
            AhakeySettingsCardDivider()
            permissionRow("辅助功能", granted: voiceRelay.accessibilityGranted)
            AhakeySettingsCardDivider()
            permissionRow("麦克风", granted: nativeSpeech.microphoneGranted)
            AhakeySettingsCardDivider()
            permissionRow("语音转写", granted: nativeSpeech.speechRecognitionGranted)
            AhakeySettingsCardDivider()
            HStack {
                Button("重新检查权限") {
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var privacyCard: some View {
        AhakeySettingsCard(sectionTitle: "隐私") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Text("您的语音口述是私密的，零数据保留。它们仅存储在您的设备上，无法从其他地方访问。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private func permissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private var agentAPISection: some View {
        AhakeySettingsCard(sectionTitle: "Agent 接入") {
            VStack(alignment: .leading, spacing: 12) {
                Text("API Key")
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)

                HStack(spacing: 8) {
                    Group {
                        if apiKeyRevealed {
                            TextField("sk-...", text: $apiKeyDraft)
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("sk-...", text: $apiKeyDraft)
                                .textFieldStyle(.plain)
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .focused($apiKeyFocused)

                    Button {
                        apiKeyRevealed.toggle()
                    } label: {
                        Image(systemName: apiKeyRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AhakeySettingsTheme.controlFill)
                )

                HStack(spacing: 10) {
                    Button("保存") {
                        AhakeyGeneralSettingsStore.setAgentAPIKey(apiKeyDraft)
                        apiKeySavedMessage = "已保存"
                    }
                    .buttonStyle(.borderedProminent)

                    if !AhakeyGeneralSettingsStore.agentAPIKey.isEmpty {
                        Text("当前：\(AhakeyGeneralSettingsStore.maskedAgentAPIKey)")
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                }

                if let apiKeySavedMessage {
                    Text(apiKeySavedMessage)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(Color.green.opacity(0.85))
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, AhakeySettingsTheme.rowPaddingV)
        }
    }

    private var ahaTypeSection: some View {
        AhakeySettingsCard(sectionTitle: "AhaType") {
            AhakeySettingsToggleRow(
                title: "启用 AhaType 云端整理",
                subtitle: "语音转写完成后先经云端整理再粘贴；失败时回退原始转写。",
                isOn: Binding(
                    get: { optimizer.isEnabled },
                    set: { enabled in
                        if enabled, !cloudAccount.isLoggedIn {
                            onOpenAccount?()
                            return
                        }
                        optimizer.setEnabled(enabled)
                    }
                )
            )
            AhakeySettingsCardDivider()
            VStack(alignment: .leading, spacing: 8) {
                Text(optimizer.statusMessage)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Text(optimizer.lastQuotaSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)

                if !cloudAccount.isLoggedIn {
                    Button {
                        onOpenAccount?()
                    } label: {
                        HStack(spacing: 6) {
                            Text("去账户登录")
                                .font(AhakeySettingsTheme.rowTitleFont)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var bluetoothOwnerSection: some View {
        AhakeySettingsCard(sectionTitle: "蓝牙占用方") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("连接方", selection: bluetoothOwnerSelection) {
                    ForEach(BluetoothConnectionOwner.allCases) { owner in
                        Text(owner.title).tag(owner)
                    }
                }
                .pickerStyle(.segmented)

                Text(agentManager.bluetoothConnectionOwner.shortDetail)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var bluetoothOwnerSelection: Binding<BluetoothConnectionOwner> {
        Binding(
            get: { agentManager.bluetoothConnectionOwner },
            set: { agentManager.setBluetoothConnectionOwner($0, bleManager: bleManager) }
        )
    }
}

/// 用户中心「使用数据」。
struct AhaKeyUserCenterUsageDataContent: View {
    @StateObject private var account = CloudAccountManager.shared
    @StateObject private var optimizer = AhaTypeTextOptimizer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AhakeySettingsCard(sectionTitle: "数据说明") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("本地数据（语音转写、按键配置、插件目录）保存在本机；云端整理与额度仅在登录并开启 AhaType 后使用。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("您的语音口述是私密的，零数据保留。它们仅存储在您的设备上，无法从其他地方访问。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }

            if account.isLoggedIn {
                AhakeySettingsCard(sectionTitle: "额度摘要") {
                    VStack(alignment: .leading, spacing: 0) {
                        quotaRow("每日", account.quotaText("daily"))
                        AhakeySettingsCardDivider()
                        quotaRow("每周", account.quotaText("weekly"))
                        AhakeySettingsCardDivider()
                        quotaRow("每月", account.quotaText("monthly"))
                        if !optimizer.lastQuotaSummary.isEmpty {
                            AhakeySettingsCardDivider()
                            Text(optimizer.lastQuotaSummary)
                                .font(.system(size: 11))
                                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                                .padding(.vertical, 10)
                        }
                    }
                }
            } else {
                AhakeySettingsCard(sectionTitle: "额度摘要") {
                    Text("登录后可查看云端整理额度。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                        .padding(.vertical, 14)
                }
            }

            AhakeySettingsCard(sectionTitle: "管理") {
                disabledActionRow(title: "清除本地缓存", detail: "清理临时文件与非必要缓存")
                AhakeySettingsCardDivider()
                disabledActionRow(title: "导出使用数据", detail: "导出本机配置与诊断摘要")
            }
        }
        .onAppear { optimizer.refreshFromDisk() }
    }

    private func quotaRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private func disabledActionRow(title: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text(detail)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            Spacer()
            Text("即将开放")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
        .opacity(0.85)
    }
}

/// 用户中心「帮助中心」。
struct AhaKeyUserCenterHelpContent: View {
    var onCloseUserCenter: (() -> Void)? = nil

    @ObservedObject private var voiceRelay = VoiceRelayService.shared
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false
    @State private var showsHelpDocsDetail = false

    var body: some View {
        Group {
            if showsHelpDocsDetail {
                helpDocsDetail
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    AhakeySettingsCard(sectionTitle: "新手引导") {
                        Button(action: replayOnboarding) {
                            helpActionRow(
                                title: "重新打开新手引导",
                                detail: unifiedOnboardingCompleted
                                    ? "将再次走全屏权限引导，并重置各功能页的一次性气泡提示。"
                                    : "首次使用引导尚未完成，点此继续。",
                                trailing: "开始",
                                trailingIsBadge: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    AhakeySettingsCard(sectionTitle: "帮助文档") {
                        Button {
                            showsHelpDocsDetail = true
                        } label: {
                            helpActionRow(
                                title: "查看帮助文档",
                                detail: "产品说明、常见问题与操作指引（即将补齐）。",
                                trailing: "占位",
                                trailingIsBadge: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var helpDocsDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showsHelpDocsDetail = false
            } label: {
                Label("返回帮助中心", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            .buttonStyle(.plain)

            AhakeySettingsCard(sectionTitle: "即将开放") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("这里将汇总硬件改键、语音输入、Agent 联动与灵动岛等说明，并接入可检索的帮助条目。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("现阶段可先使用「新手引导」完成权限与基础体验。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }

            AhakeySettingsCard(sectionTitle: "相关入口") {
                Button(action: replayOnboarding) {
                    helpActionRow(
                        title: "打开新手引导",
                        detail: "权限授权与语音体验流程",
                        trailing: nil,
                        trailingIsBadge: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func replayOnboarding() {
        voiceRelay.suppressPermissionOnboarding(for: 60)
        UnifiedOnboardingStorage.resetForReplay()
        unifiedOnboardingCompleted = false
        showsHelpDocsDetail = false
        onCloseUserCenter?()
    }

    private func helpActionRow(
        title: String,
        detail: String,
        trailing: String?,
        trailingIsBadge: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text(detail)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                if trailingIsBadge {
                    Text(trailing)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AhakeySettingsTheme.controlFill))
                } else {
                    Text(trailing)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }
}

/// 用户中心「关于我们」。
struct AhaKeyUserCenterAboutContent: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "AhaKey Studio"
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short)（\(build)）"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AhakeySettingsCard(sectionTitle: nil) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AhaKey")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("为创造者打造的模块化输入与工作流工具。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("AhaKey 把磁吸硬件、语音输入、Agent 联动与灵动岛状态层连成一体：在键盘上完成改键与模式切换，在桌面上用 Studio 配置、调试并扩展能力。我们相信输入设备不该只是按键集合，而应成为可组合、可开源扩展的创作伙伴。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 16)
            }

            AhakeySettingsCard(sectionTitle: "我们在做什么") {
                VStack(alignment: .leading, spacing: 0) {
                    aboutPillar(
                        title: "硬件与 Studio",
                        detail: "原生 macOS 工作台连接 AhaKey 设备，完成布局映射、语音与 Agent 配置。"
                    )
                    AhakeySettingsCardDivider()
                    aboutPillar(
                        title: "开源插件生态",
                        detail: "通过插件市场发现、安装并回馈社区扩展，让能力随社区一起生长。"
                    )
                    AhakeySettingsCardDivider()
                    aboutPillar(
                        title: "创造者工作流",
                        detail: "把常用动作放回指尖与岛上状态，减少在窗口之间来回切换的成本。"
                    )
                }
            }

            AhakeySettingsCard(sectionTitle: "本应用") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appName)
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("版本 \(versionText)")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    Text("硬件改键、语音输入、Agent 联动与灵动岛的统一工作台。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }
        }
    }

    private func aboutPillar(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Text(detail)
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }
}

/// 用户中心「版本说明」。
struct AhaKeyUserCenterReleaseNotesContent: View {
    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AhakeySettingsCard(sectionTitle: "当前版本") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AhaKey Studio \(versionText)")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("完整版本说明与更新日志即将开放。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }
        }
    }
}
