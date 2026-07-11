import AppKit
import CoreImage
import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct AhaKeyStudioView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    let presentation: AhaKeyStudioPresentation
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @StateObject private var ahaType = AhaTypeTextOptimizer.shared
    @StateObject private var cloudAccount = CloudAccountManager.shared
    @StateObject private var agentManager = AgentManager.shared
    @ObservedObject private var coachTips = FeatureCoachTipController.shared

    @State private var studioDraft: AhaKeyStudioDraft
    @State private var lastSyncedDraft: AhaKeyStudioDraft
    @State private var selectedMode: AhaKeyModeSlot
    @State private var selectedPart: AhaKeyStudioPart
    @State private var lightBarPreview: IDEState
    @State private var modeCustomNames: [Int: String] = [:]
    @State private var lastSyncDate: Date?
    @State private var syncStatusMessage = "修改会先保存在本地，连接设备后再同步。"
    @State private var isSyncing = false
    // AhaKeyStudio 交还蓝牙给 Agent 的过渡期：保持"已连接"显示，直到 Agent 接管或超时。
    @State private var isTransitioningToKeyboardControl = false
    @State private var showsOLEDPlaybackPreview = false
    @State private var showsDeviceInfo = false
    @State private var showsCloudAccount = false
    @State private var showsAhaTypeLoginRequiredToast = false
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false
    @State private var isEditingInspector = true
    @State private var showsDiagnostics = false
    @State private var selectedTriggerTab: Int = 0
    @State private var showMoreKeyOptions = false
    @State private var showMoreLightBarOptions = false
    /// 每次主 App 自占 BLE 连接成功只跑一次默认 LCD 自动同步。
    /// .onChange(of: isConnected) 在断开时重置；下次重连时再触发一次。
    @State private var oledAutoSyncDoneForConnection: Bool = false
    @State private var showsHelpCenter = false
    @State private var editingModeSlot: AhaKeyModeSlot?
    @State private var editingModeName: String = ""
    @FocusState private var modeNameFieldFocused: Bool
    @State private var showsWriteResultAlert = false
    @State private var writeResultAlertMessage = ""
    @AppStorage(DeviceCapabilityStorage.previewGenerationKey) private var previewGenerationRaw = DeviceGeneration.gen2.rawValue
    @State private var magneticModuleState: MagneticModuleState = MagneticModuleStateStore.load()
    @State private var oceanLightConfig: OceanLightConfig = OceanLightConfigStore.load()

    init(bleManager: AhaKeyBLEManager, presentation: AhaKeyStudioPresentation = .standalone) {
        self.bleManager = bleManager
        self.presentation = presentation
        let initialDraft = AhaKeyStudioStore.load() ?? .default
        // 注意：不要在这里调用 VoiceRelayService.updateRoutes —— SwiftUI 会因 bleManager
        // 的 @Published 属性（workMode/电量/连接状态等）频繁重建 view，init 会跟着多次执行。
        // 任何在 init 里调用 updateRoutes 都会重置 functionRelay 的 holdingRoute（按住状态），
        // 导致微信等"按住说话"过几秒就自动结束。正确入口在下面的 .onAppear。
        _studioDraft = State(initialValue: initialDraft)
        _lastSyncedDraft = State(initialValue: initialDraft)
        let initialMode = AhaKeyModeSlot(rawValue: bleManager.workMode) ?? .mode0
        _selectedMode = State(initialValue: initialMode)
        _selectedPart = State(initialValue: .key1)
        _lightBarPreview = State(initialValue: .preToolUse)
        _modeCustomNames = State(initialValue: AhaKeyModeNameStore.load())
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(isEmbedded ? 0.35 : 1)
            HStack(spacing: 0) {
                canvasPane
                Divider().opacity(isEmbedded ? 0.35 : 1)
                inspectorPane
            }
            Divider().opacity(isEmbedded ? 0.35 : 1)
            statusBar
        }
        .frame(
            minWidth: isEmbedded ? 0 : 1180,
            maxWidth: isEmbedded ? .infinity : nil,
            minHeight: isEmbedded ? 0 : 680,
            maxHeight: isEmbedded ? .infinity : nil
        )
        .background(studioBackground)
        .onAppear {
            agentManager.applyStoredBluetoothPreferenceOnLaunch(bleManager: bleManager)
            voiceRelay.start()
            nativeSpeech.start()
            bleManager.refreshBluetoothAuthorization()
            applyCursorRejectMacroSelfHealIfNeeded()
            voiceRelay.updateRoutes(from: studioDraft)
            SwitchStateNotifier.shared.bind(to: bleManager)
            magneticModuleState = MagneticModuleStateStore.load()
            oceanLightConfig = OceanLightConfigStore.load()
            bleManager.magneticModuleState = magneticModuleState
            bleManager.oceanLightConfig = oceanLightConfig
            NotificationCenter.default.post(
                name: .ahaKeyKeyboardWorkModeChanged,
                object: nil,
                userInfo: ["workMode": bleManager.workMode]
            )
            scheduleStartupPermissionOnboarding()
        }
        .onChange(of: studioDraft) { newValue in
            AhaKeyStudioStore.save(newValue)
            voiceRelay.updateRoutes(from: newValue)
        }
        // 键盘物理档位变化（BLE 查询/通知上报）→ 自动切到对应 Mode 标签，
        // 这样 LCD 预览、快捷键草稿、发出去的 updateState 三者一致。
        .onChange(of: bleManager.workMode) { newValue in
            if let slot = AhaKeyModeSlot(rawValue: newValue), slot != selectedMode {
                selectedMode = slot
            }
        }
        .onChange(of: selectedMode) { newValue in
            guard bleManager.isConnected,
                  bleManager.commandCharReady,
                  bleManager.workMode != newValue.rawValue else { return }
            bleManager.setWorkMode(UInt8(newValue.rawValue))
            syncStatusMessage = "已通知键盘切换到 \(newValue.title)。"
        }
        .onChange(of: bleManager.isConnected) { connected in
            if !connected { oledAutoSyncDoneForConnection = false }
        }
        .onChange(of: bleManager.keyboardPictureStates) { _ in
            guard !oledAutoSyncDoneForConnection else { return }
            // 四个 mode 都查回来才动手
            guard bleManager.keyboardPictureStates.count == AhaKeyModeSlot.allCases.count else { return }
            oledAutoSyncDoneForConnection = true
            Task { await autoSyncDefaultOLEDsIfNeeded() }
        }
        .onChange(of: bleManager.bluetoothPermissionGranted) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: bleManager.bluetoothPoweredOn) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: voiceRelay.inputMonitoringGranted) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: voiceRelay.accessibilityGranted) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: nativeSpeech.microphoneGranted) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: nativeSpeech.speechRecognitionGranted) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: nativeSpeech.siriEnabled) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: nativeSpeech.dictationEnabled) { _ in
            refreshStartupPermissionOnboarding()
        }
        .onChange(of: magneticModuleState) { newValue in
            MagneticModuleStateStore.save(newValue)
            bleManager.magneticModuleState = newValue
        }
        .onChange(of: oceanLightConfig) { newValue in
            OceanLightConfigStore.save(newValue)
            bleManager.oceanLightConfig = newValue
        }
        .onChange(of: previewGenerationRaw) { _ in
            if previewGeneration == .x1, selectedPart == .magneticPort {
                selectedPart = .key1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioSelectPart)) { notification in
            if let raw = notification.userInfo?[StudioNavigationUserInfoKey.part] as? String,
               let part = AhaKeyStudioPart(rawValue: raw) {
                selectedPart = part
                isEditingInspector = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioShowDeviceInfo)) { _ in
            openDeviceInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ahaKeyStudioNavigate)) { notification in
            handleStudioNavigation(notification)
        }
        .alert("Agent", isPresented: Binding(
            get: { agentManager.agentUserAlert != nil },
            set: { if !$0 { agentManager.agentUserAlert = nil } }
        )) {
            Button("好", role: .cancel) {
                agentManager.agentUserAlert = nil
            }
        } message: {
            Text(agentManager.agentUserAlert ?? "")
        }
        .alert("AhaType 未注册登录", isPresented: $showsAhaTypeLoginRequiredToast) {
            Button("知道了", role: .cancel) {}
            Button("注册登录") {
                openCloudAccountEntry()
            }
        } message: {
            Text("请先注册登录 AhaType 后再开启云端整理。")
        }
        .sheet(isPresented: $showsOLEDPlaybackPreview) {
            OLEDMotionPreviewSheet(
                modeTitle: selectedMode.title,
                assetPath: currentModeDraft.oled.localAssetPath
            )
        }
        .sheet(isPresented: $showsDeviceInfo) {
            DeviceInfoSheetContainer(bleManager: bleManager)
                .frame(width: 720, height: 720)
        }
        .sheet(isPresented: $showsCloudAccount) {
            CloudAccountSheet()
                .frame(width: 560, height: 680)
        }
    }

    private var isEmbedded: Bool { presentation == .embeddedClient }

    private func openCloudAccountEntry() {
        if isEmbedded {
            StudioNavigationRouter.shared.openUserCenter()
        } else {
            showsCloudAccount = true
        }
    }

    private func openDeviceInfo() {
        if isEmbedded {
            StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
        } else {
            showsDeviceInfo = true
        }
    }

    private var previewGeneration: DeviceGeneration {
        DeviceGeneration(rawValue: previewGenerationRaw) ?? .gen2
    }

    private var studioBackground: Color {
        isEmbedded ? AhaKeyStudioEmbeddedTheme.windowBackground : AhaKeyUI.ColorToken.base
    }

    private var islandLightBarPreview: LightBarPreviewState {
        switch lightBarPreview {
        case .permissionRequest:
            return .waitingApproval
        case .stop, .sessionEnd:
            return .stopped
        case .taskCompleted:
            return .taskCompleted
        default:
            return .aiRunning
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if isEmbedded {
            EmptyView()
        } else {
            standaloneTopBar
        }
    }

    private var embeddedTopBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VibeBarIslandDeviceStatusIcons(
                keyboardConnected: isEffectivelyConnected,
                batteryLevel: bleManager.batteryLevel,
                voiceRecording: nativeSpeech.isRecording,
                voiceListening: voiceRelay.isListening,
                leverIsAuto: bleManager.switchState == 0,
                leverKnown: bleManager.isConnected
            )

            Text(selectedMode.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AhaKeyStudioEmbeddedTheme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(AhaKeyStudioEmbeddedTheme.controlFill))

            Spacer(minLength: 0)

            if !bleManager.isConnected, agentManager.bluetoothConnectionOwner == .ahaKeyStudio {
                Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                    bleManager.userInitiatedConnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(bleManager.isScanning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(chromeBarBackground)
    }

    private var standaloneTopBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AhaKey Studio")
                    .font(AhaKeyUI.Font.largeTitle)
            }
            .layoutPriority(1)

            HStack(spacing: 8) {
                infoPill(
                    title: isEffectivelyConnected ? "已连接" : (bleManager.isScanning ? "扫描中" : "未连接"),
                    // 未连接时不再笼统显示「等待设备」，而是给出细分链路诊断（Issue #34）。
                    subtitle: isEffectivelyConnected ? (bleManager.deviceName ?? "已连接") : bleManager.linkDiagnostic.shortMessage,
                    accent: isEffectivelyConnected ? .green : .orange,
                    width: 118
                )
                .help(isEffectivelyConnected ? "" : bleManager.linkDiagnostic.detail)
                infoPill(
                    title: "电量",
                    subtitle: isEffectivelyConnected ? "\(bleManager.batteryLevel)%" : "—",
                    accent: .blue
                )
                infoPill(
                    title: "拨杆",
                    subtitle: currentSwitchTitle,
                    accent: currentSwitchTitle == "自动批准" ? .mint : .indigo
                )
            }
            .layoutPriority(2)

            Spacer(minLength: 0)

            if !bleManager.isConnected, agentManager.bluetoothConnectionOwner == .ahaKeyStudio {
                Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                    bleManager.userInitiatedConnect()
                }
                .buttonStyle(.bordered)
                .disabled(bleManager.isScanning)
            }

            ahaTypeModeStatus

            configurationModeStatus

            if shouldShowTopBarInstallStartButton {
                Button("安装启动") {
                    installStartAgentFromTopBar()
                }
                .buttonStyle(.borderedProminent)
                .disabled(agentManager.isAgentOperationInProgress)
                .help("安装/修复 Agent 与 Hook，并启动 Agent 控制键盘。")
            }

            Button {
                NSPasteboard.general.clearContents()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .help("清空剪贴板")

            Menu {
                Button("恢复当前模式默认值") {
                    restoreCurrentModeDefaults()
                }
                Button("重新连接设备") {
                    bleManager.disconnect()
                    bleManager.userInitiatedConnect()
                }
                Button("设备信息 · Agent…") {
                    openDeviceInfo()
                }
                Divider()
                Button("云端账号 · AhaType…") {
                    openCloudAccountEntry()
                }
                Button("刷新 AhaType 状态") {
                    ahaType.refreshFromDisk()
                }
                Divider()
                Button("隐藏到后台") {
                    NSApp.keyWindow?.close()
                }
                Button("退出 AhaKey Studio") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32, height: 28)
            .help("更多")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(chromeBarBackground)
    }

    private var configurationModeStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isEditingConfiguration ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(isEditingConfiguration ? "编辑配置中" : "键盘控制中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(configurationModeDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: 138, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .help("日常使用由 Agent 控制键盘；需要改键、LCD 或同步时，进入编辑配置后由 AhaKey Studio 临时接管蓝牙。")
    }

    private var ahaTypeModeStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ahaType.isEnabled ? Color.green : Color.gray.opacity(0.55))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(ahaType.isEnabled ? "AhaType 开启" : "AhaType 关闭")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ahaType.isEnabled ? "云端整理已启用" : "语音结果直接粘贴")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Toggle("", isOn: Binding(
                get: { ahaType.isEnabled },
                set: { enabled in
                    if enabled, !cloudAccount.isLoggedIn {
                        showsAhaTypeLoginRequiredToast = true
                    } else {
                        ahaType.setEnabled(enabled)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .frame(width: 150, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .help("开启后，macOS 原生语音转写会先经过 AhaType 云端整理，再粘贴到当前光标。")
    }

    private var canvasPane: some View {
        VStack(alignment: .leading, spacing: isEmbedded ? 12 : 16) {
            deviceHeader

            AhaKeyIslandKeyboardCanvasView(
                modeDraft: currentModeDraft,
                selectedPart: selectedPart,
                lightBarPreview: islandLightBarPreview,
                switchTitle: currentSwitchTitle,
                dirtyParts: dirtyPartsForCurrentMode(),
                deviceGeneration: previewGeneration,
                magneticModuleState: magneticModuleState,
                oceanLightConfig: oceanLightConfig,
                workMode: liveKeyboardWorkMode ?? bleManager.workMode,
                onSelect: { selectedPart = $0 },
                onModeSwitch: { cycleModeForward() },
                onKeySimulate: { role in
                    if role == .voice {
                        nativeSpeech.toggleRecordingFromVoiceKey()
                    }
                },
                onSwitchToggle: { toggleVirtualSwitch() },
                liveLightMode: liveCanvasLightMode,
                liveIDEStateValue: liveCanvasIDEStateValue,
                switchState: liveCanvasSwitchState,
                keyboardPictureFrameCount: bleManager.keyboardPictureStates[selectedMode.rawValue]?.frameCount,
                appearance: isEmbedded ? .vibeBarEmbedded : .studioLight
            )
            .aspectRatio(canvasAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, alignment: .top)

            modeSwitchPanel
                .featureCoachTip(
                    .hardwareModeVsAgent,
                    isActive: isEmbedded,
                    alignment: .topTrailing
                )

            hardwareAssemblyPlaceholder
        }
        .padding(isEmbedded ? EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16) : EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .featureCoachTip(
            .deviceConnect,
            isActive: isEmbedded && !bleManager.isConnected,
            alignment: .topTrailing
        )
    }

    private var canvasAspectRatio: CGFloat {
        let layout = isEmbedded ? KeyboardCanvasAppearance.vibeBarEmbedded.layout : KeyboardCanvasAppearance.studioLight.layout
        return layout.aspectRatio
    }

    @ViewBuilder
    private func modeTabItem(_ mode: AhaKeyModeSlot) -> some View {
        let isSelected = selectedMode == mode
        let isEditing = editingModeSlot == mode

        if isEditing {
            TextField("", text: $editingModeName, onCommit: { commitModeNameEdit() })
                .textFieldStyle(.plain)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .focused($modeNameFieldFocused)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color.accentColor.opacity(0.15))
                .onExitCommand { commitModeNameEdit() }
                .onAppear { modeNameFieldFocused = true }
                .onChange(of: modeNameFieldFocused) { focused in
                    if !focused { commitModeNameEdit() }
                }
        } else {
            Text(modeCustomNames[mode.rawValue] ?? mode.defaultName)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    commitModeNameEdit()
                    editingModeName = modeCustomNames[mode.rawValue] ?? mode.defaultName
                    editingModeSlot = mode
                    selectedMode = mode
                }
                .onTapGesture(count: 1) {
                    commitModeNameEdit()
                    selectedMode = mode
                }
        }
    }

    private func commitModeNameEdit() {
        guard let slot = editingModeSlot else { return }
        let capped = String(editingModeName.prefix(30))
        if capped.isEmpty || capped == slot.defaultName {
            modeCustomNames.removeValue(forKey: slot.rawValue)
        } else {
            modeCustomNames[slot.rawValue] = capped
        }
        AhaKeyModeNameStore.save(modeCustomNames)
        editingModeSlot = nil
    }

    /// 左栏顶：仅设备名与连接状态（Mode 在画布下方）。
    private var deviceHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(bleManager.deviceName ?? "AhaKey Mini")
                .font(.system(size: isEmbedded ? 22 : 20, weight: .semibold))
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            VibeBarIslandDeviceStatusIcons(
                keyboardConnected: isEffectivelyConnected,
                batteryLevel: bleManager.batteryLevel,
                voiceRecording: nativeSpeech.isRecording,
                voiceListening: voiceRelay.isListening,
                leverIsAuto: bleManager.switchState == 0,
                leverKnown: bleManager.isConnected
            )
        }
    }

    /// 画布下方：针对不同 Agent 的 Mode 切换 + 指引。
    private var modeSwitchPanel: some View {
        VStack(alignment: .leading, spacing: isEmbedded ? 8 : 10) {
            Text(isEmbedded ? "Agent 模式" : "Keyboard Mode")
                .font(isEmbedded ? .system(size: 12, weight: .semibold) : .system(size: 13, weight: .semibold))
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)

            if isEmbedded {
                Picker("模式", selection: $selectedMode) {
                    ForEach(AhaKeyModeSlot.allCases) { mode in
                        Text(modeCustomNames[mode.rawValue] ?? mode.defaultName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 0) {
                    ForEach(AhaKeyModeSlot.allCases) { mode in
                        modeTabItem(mode)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .frame(maxWidth: .infinity)
            }

            modeGuidanceRow
        }
        .padding(.top, isEmbedded ? 4 : 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText.opacity(0.12) : Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 0.5)
        }
    }

    private var modeGuidanceRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(selectedMode.guidance)
                .font(isEmbedded ? .system(size: 12) : .callout)
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail = selectedMode.guidanceHoverDetail {
                InspectorHelpButton(
                    title: "Mode 说明",
                    lines: [detail],
                    isEmbedded: isEmbedded,
                    width: 320,
                    arrowEdge: .top
                )
            }
        }
    }

    /// Agent 模式下方预留：用户自定义硬件组装设计（后续开发）。
    private var hardwareAssemblyPlaceholder: some View {
        VStack(alignment: .leading, spacing: isEmbedded ? 8 : 10) {
            Text("硬件组装")
                .font(isEmbedded ? .system(size: 12, weight: .semibold) : .system(size: 13, weight: .semibold))
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)

            HStack(spacing: 10) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.tertiaryText : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义硬件组装")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                    Text("在此设计磁吸模块与扩展件组合，功能开发中。")
                        .font(.caption)
                        .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.tertiaryText : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText.opacity(0.28) : Color(nsColor: .separatorColor))
            )
        }
        .padding(.top, isEmbedded ? 4 : 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText.opacity(0.12) : Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("硬件组装，功能开发中")
    }

    private var inspectorPane: some View {
        VStack(spacing: 0) {
            HardwarePartTabBar(
                parts: AhaKeyStudioPart.visibleParts(for: previewGeneration),
                selection: $selectedPart,
                dirtyParts: dirtyPartsForCurrentMode(),
                isEmbedded: isEmbedded
            )

            Divider().opacity(isEmbedded ? 0.35 : 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inspectorHeader
                    inspectorPartContent
                }
                .padding(isEmbedded ? 14 : 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            Divider()
            inspectorWriteBar
        }
        .frame(width: isEmbedded ? 340 : 390)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .featureCoachTip(
            .hardwareBindWrite,
            isActive: isEmbedded && bleManager.isConnected,
            alignment: .bottom
        )
        .onChange(of: selectedPart) { _ in
            commitModeNameEdit()
            isEditingInspector = true
            enterEditingConfiguration()
        }
        .onChange(of: selectedMode) { _ in
            if editingModeSlot != nil && editingModeSlot != selectedMode {
                commitModeNameEdit()
            }
        }
        .onChange(of: previewGenerationRaw) { _ in
            let visible = AhaKeyStudioPart.visibleParts(for: previewGeneration)
            if !visible.contains(selectedPart) {
                selectedPart = visible.first ?? .key1
            }
        }
        .onAppear {
            isEditingInspector = true
            enterEditingConfiguration()
        }
        .alert("写入结果", isPresented: $showsWriteResultAlert) {
            Button("继续编辑", role: .cancel) {}
            Button("完成编辑") {
                if writeResultAlertMessage.contains("成功") {
                    completeEditingAfterSuccessfulWrite()
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(writeResultAlertMessage)
        }
    }

    @ViewBuilder
    private var inspectorPartContent: some View {
        switch selectedPart {
        case .key1, .key2, .key3, .key4:
            keyInspector
        case .oledDisplay:
            oledInspector
        case .lightBar:
            if previewGeneration == .gen2 {
                OceanLightInspectorView(
                    config: $oceanLightConfig,
                    onApply: {
                        bleManager.applyOceanLightConfig(oceanLightConfig)
                        syncStatusMessage = "已更新海洋灯效配置（占位，待固件联调）。"
                    },
                    isEmbedded: isEmbedded
                )
            } else {
                lightBarInspector
            }
        case .toggleSwitch:
            switchInspector
        case .magneticPort:
            MagneticModuleInspectorView(
                moduleState: $magneticModuleState,
                onToggleVirtualSwitch: toggleVirtualSwitch,
                isEmbedded: isEmbedded
            )
        }
    }

    private var inspectorWriteBar: some View {
        HStack(spacing: 12) {
            if selectedPart == .lightBar {
                Button {
                    previewLightEffect(for: lightBarPreview)
                } label: {
                    Label("预览到键盘", systemImage: "play.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSyncing || !bleManager.isConnected || !bleManager.commandCharReady)
            }

            Spacer(minLength: 0)

            Button {
                writeToKeyboard()
            } label: {
                Label(isSyncing ? "写入中…" : "写入键盘", systemImage: isSyncing ? "arrow.trianglehead.2.clockwise" : "square.and.arrow.down")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isSyncing || !bleManager.isConnected)
            .overlay(alignment: .top) {
                if isEmbedded, coachTips.isShowing(.hardwareBindWrite) {
                    Text("点这里写入")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(AhakeySettingsTheme.accentBlue))
                        .offset(y: -30)
                }
            }
        }
        .padding(.horizontal, isEmbedded ? 16 : 24)
        .padding(.vertical, 12)
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Label(selectedPart.title, systemImage: selectedPart.systemImage)
                    .font(.system(size: isEmbedded ? 16 : 20, weight: .semibold))
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                Spacer(minLength: 0)
                if partIsDirty(selectedPart) {
                    Label("未同步", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                InspectorHelpButton(
                    title: inspectorHelpTitle,
                    lines: inspectorHelpLines,
                    isEmbedded: isEmbedded,
                    width: selectedPart == .toggleSwitch || selectedPart.isKey ? 300 : 280
                )
            }
            Text(selectedPart.subtitle)
                .font(.callout)
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
        }
    }

    private var inspectorHelpTitle: String {
        "\(selectedPart.title) · 说明"
    }

    private var inspectorHelpLines: [String] {
        switch selectedPart {
        case .key1, .key2, .key3, .key4:
            keyInspectorHelpLines
        case .oledDisplay:
            [
                "选择 GIF/图片并设置 FPS，写入后对应当前 Mode 的 LCD 动图。",
                "硬性限制：源文件 ≤ 2 MB，FPS 1–30，单模式最多 70 帧；Mode 1/2/3/4 固定写入 slot 10/80/150/220。",
                "切换到当前模式时，LCD 会先显示该模式的按键描述，约 1 秒后回到动图。",
                "文字状态、token、模型环境等显示能力后续版本提供。",
            ]
        case .lightBar:
            if previewGeneration == .gen2 {
                [
                    "选择预设并调节亮度后，用底部「写入键盘」同步。",
                    "IMU 重力联动与文字轮播为进阶选项；轮播经 BLE 0x98 下发（占位联调）。",
                    "「应用到设备」为占位入口，正式保存请用底部写入。",
                ]
            } else {
                [
                    "为各 IDE 状态选择灯效样式，并调节亮度。",
                    "在「更多灯效」里点状态可在虚拟键盘预览，并通过 0x91 瞬时预览到设备。",
                    "保存请使用底部「写入键盘」。",
                ]
            }
        case .toggleSwitch:
            [
                "拨杆是物理档位：0 档自动批准，1 档手动批准；此处只读上报，不模拟拨动。",
                "对 Claude / Cursor / Codex / Kimi 同时生效，与键盘当前 Mode 无关。",
                "自动批准：Claude / Codex PermissionRequest，Cursor preToolUse；须 Agent 与 Hook 就绪，且蓝牙由 Agent 占用。",
                "Kimi：安装 AhaKey Kimi Hooks 后接管当前会话；刚装完或升级 kimi-cli 后请完全关闭并重开一次 kimi。",
                "手动批准：交回用户/终端确认。若仍弹窗，请到设备信息查看工具批准诊断。",
            ]
        case .magneticPort:
            [
                "磁吸底座默认为空槽；从网格选择要吸附的模块。",
                "拨杆免费可用；摇杆、旋钮、滚轮、十字键需购买解锁（测试阶段可全部解锁）。",
                "已吸附模块可在下方做模拟操作；固件 0x95 通信仍在联调。",
                "滚轮模拟为 UI 占位；触控板滚动可改增量，正式固件协议待定。",
            ]
        }
    }

    private var keyInspectorHelpLines: [String] {
        let key = currentSelectedKey
        var lines: [String] = [
            "1. 点右侧元件 Tab，或点键盘热区选中部件。",
            "2. 配置完成后点「写入键盘」同步到键盘。",
            "同步后短按实体键切模式时，LCD 会先短暂显示按键描述，再回到该模式动图。",
            "设备实际写入描述：\(currentSelectedKeySanitizedDescription.isEmpty ? "空白" : currentSelectedKeySanitizedDescription)（仅稳定支持 ASCII）。",
        ]
        if selectedMode == .mode0 {
            lines.append("Mode 1 默认文案：Record / Accept / Reject / Backspace。")
        }
        if key.role == .voice {
            lines.append("语音输入方式独立于当前 Mode。")
            lines.append("选定输入方式后，下方展开对应绑定方法；该方式的注意事项见绑定旁问号。")
            lines.append("短按：按一下开始，再按一下结束；长按：按住录音，松手发送。")
            lines.append("长按绑定不同快捷键需固件 v2+；当前长按主要配置 AhaType 与触发阈值。")
        } else {
            lines.append(key.role.manualText)
            lines.append("快捷键与描述会一并写入；长按绑定需固件 v2+，当前仅短按写入设备。")
        }
        return lines
    }

    // MARK: - 权限诊断弹窗

    private var diagnosticsSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("权限诊断")
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button("关闭") { showsDiagnostics = false }
                        .buttonStyle(.bordered)
                }

                GroupBox("后台语音桥") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(voiceRelay.isListening ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(voiceRelay.isListening ? "后台监听中" : "等待系统权限")
                                .font(.callout.weight(.semibold))
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            permissionBadge(title: "输入监控", granted: voiceRelay.inputMonitoringGranted)
                            permissionBadge(title: "辅助功能", granted: voiceRelay.accessibilityGranted)
                        }
                        Text(voiceRelay.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(voiceRelay.lastPermissionCheckSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(voiceRelay.activeRouteSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("再次申请权限") {
                                requestPermissionsThenOpenPrivacySettingsIfNeeded(
                                    bleManager: bleManager,
                                    voiceRelay: voiceRelay,
                                    nativeSpeech: nativeSpeech
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            Button("重新检查权限") {
                                voiceRelay.refreshPermissions(deferredTCCRequery: true)
                            }
                            .buttonStyle(.bordered)
                            RestartToApplyPermissionsButton()
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("苹果原生转写") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(nativeSpeech.isRecording ? Color.red : (nativeSpeech.microphoneGranted && nativeSpeech.speechRecognitionGranted ? Color.green : Color.orange))
                                .frame(width: 10, height: 10)
                            Text(nativeSpeech.isRecording ? "录音转写中" : "等待触发")
                                .font(.callout.weight(.semibold))
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            permissionBadge(title: "麦克风", granted: nativeSpeech.microphoneGranted)
                            permissionBadge(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted)
                            permissionBadge(title: "Siri", granted: nativeSpeech.siriEnabled)
                            permissionBadge(title: "听写", granted: nativeSpeech.dictationEnabled)
                        }
                        Text(nativeSpeech.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(nativeSpeech.lastPermissionCheckSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()

                        HStack(spacing: 10) {
                            Circle()
                                .fill(nativeSpeech.isRecording ? Color.red : Color.clear)
                                .frame(width: 8, height: 8)
                            Text(nativeSpeech.isRecording ? "录音中" : "转写测试")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if !nativeSpeech.transcriptPreview.isEmpty {
                                Text(nativeSpeech.transcriptPreview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if !nativeSpeech.lastCommittedText.isEmpty {
                                Text("最近写入：\(nativeSpeech.lastCommittedText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        HStack(spacing: 8) {
                            Button(nativeSpeech.isRecording ? "结束并写入" : "开始录音") {
                                nativeSpeech.toggleRecordingFromVoiceKey()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("重新检查权限") {
                                nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                            }
                            .buttonStyle(.bordered)
                            RestartToApplyPermissionsButton()
                            if !nativeSpeechPermissionsReady {
                                Button("打开系统设置") { openNativeSpeechPrivacySettings() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                let voiceKey = currentModeDraft.key(for: .voice)
                if let preset = voiceKey.voicePreset, preset == .typeless {
                    GroupBox("Fn 语音输入法") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Typeless / 微信语音 / 豆包输入法使用 F19 触发，并注入 Fn 按住/松开。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("排查请看 voice-relay.log（matched · function relay · post fn）。路径：~/Library/Application Support/AhaKeyConfig/diagnostics/")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Button("模拟按一次语音键") {
                                voiceRelay.simulateInspectorVoiceKeyTap(for: selectedMode)
                            }
                            .buttonStyle(.borderedProminent)
                            if let hint = voiceRelay.lastInspectorSimulateHint {
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox("AhaType 状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { ahaType.isEnabled },
                                set: { ahaType.setEnabled($0) }
                            )) {
                                Text("AhaType 云端整理")
                                    .font(.callout.weight(.semibold))
                            }
                            .toggleStyle(.switch)
                            Spacer()
                            Button("刷新") { ahaType.refreshFromDisk() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        Text(ahaType.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ahaType.lastQuotaSummary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .frame(width: 500, height: 620)
    }

    // MARK: - Inspector Level 1 Summary

    private func summaryRow(_ title: String, value: String, dot: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 5) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                        .offset(y: -1)
                }
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var partSummaryContent: some View {
        switch selectedPart {
        case .key1:          voiceKeySummary
        case .key2, .key3, .key4: actionKeySummary
        case .oledDisplay:   oledSummary
        case .lightBar:
            if previewGeneration == .gen2 {
                OceanLightSummaryView(config: oceanLightConfig)
            } else {
                lightBarSummary
            }
        case .toggleSwitch:  switchSummary
        case .magneticPort:
            MagneticModuleSummaryView(moduleState: magneticModuleState)
        }
    }

    @ViewBuilder
    private var voiceKeySummary: some View {
        let key = currentSelectedKey
        let preset = key.voicePreset ?? .custom
        summaryRow("输入方式", value: preset.title)
        summaryRow("快捷键", value: key.displaySummary)
        if preset.isMacOSNativeFamily {
            summaryRow("触发方式", value: "短按 + 长按")
            let permCount = [nativeSpeech.microphoneGranted, nativeSpeech.speechRecognitionGranted,
                             nativeSpeech.siriEnabled, nativeSpeech.dictationEnabled].filter { $0 }.count
            summaryRow("转写权限", value: "\(permCount)/4 已授权",
                       dot: permCount == 4 ? .green : .orange)
        }
        summaryRow("语音桥", value: voiceRelay.isListening ? "运行中" : "等待权限",
                   dot: voiceRelay.isListening ? .green : .orange)
        summaryRow("按键描述", value: key.description.isEmpty ? "—" : key.description)
    }

    @ViewBuilder
    private var actionKeySummary: some View {
        let key = currentSelectedKey
        summaryRow("绑定", value: key.displaySummary)
        summaryRow("类型", value: key.usesMacro ? "固件宏（\(key.macro.count) 步）" : "单键 / 组合键")
        summaryRow("按键描述", value: key.description.isEmpty ? "—" : key.description)
    }

    @ViewBuilder
    private var oledSummary: some View {
        let oled = currentModeDraft.oled
        summaryRow("动图", value: oled.localAssetPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "默认动图")
        summaryRow("播放速度", value: "\(oled.framesPerSecond) FPS")
        summaryRow("状态行", value: oled.statusLine.isEmpty ? "—" : String(oled.statusLine.prefix(32)))
    }

    @ViewBuilder
    private var lightBarSummary: some View {
        let lb = currentModeDraft.lightBar
        ForEach(IDEState.allCases) { state in
            summaryRow(state.shortLabel, value: lb.effect(for: state).title)
        }
        summaryRow("亮度", value: "\(lb.brightness)%")
    }

    @ViewBuilder
    private var switchSummary: some View {
        let agentReady = agentManager.isInstalled && agentManager.isRunning && agentManager.hooksInstalled
        summaryRow("当前档位", value: currentSwitchTitle,
                   dot: currentSwitchTitle == "自动批准" ? .green : .indigo)
        summaryRow("Agent", value: agentReady ? "就绪" : "未就绪",
                   dot: agentReady ? .green : .orange)
        summaryRow("作用范围", value: "Claude · Cursor · Codex · Kimi")
    }

    // MARK: - Inspector Level 2 Detail

    private var keyInspector: some View {
        let key = currentSelectedKey
        return VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "按键描述", isEmbedded: isEmbedded) {
                HStack(alignment: .center, spacing: 12) {
                    Text("描述")
                        .font(.callout)
                        .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                    TextField("例如 Record / Accept / Reject / Backspace", text: selectedKeyDescriptionBinding)
                        .textFieldStyle(.roundedBorder)
                }
                if currentSelectedKey.description.containsNonASCII {
                    Text("设备 LCD 只稳定支持 ASCII；非 ASCII 写入时会被过滤。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            InspectorSection(title: "按键配置", isEmbedded: isEmbedded) {
                if key.role == .voice {
                    HStack(alignment: .center, spacing: 8) {
                        Text("语音输入方式")
                            .font(.callout)
                            .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        Picker("", selection: selectedVoicePresetBinding) {
                            ForEach(VoicePreset.visibleCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 120, alignment: .trailing)
                        .layoutPriority(1)
                    }
                } else {
                    keyBindingControls(for: key)
                }
            }

            if key.role == .voice {
                InspectorSection(title: "绑定方法", isEmbedded: isEmbedded) {
                    voiceBindingSection(for: key)
                }
            }

            AhaKeyStudioDisclosureSection(
                title: "更多设置",
                subtitle: key.role == .voice ? "长按与 AhaType" : "长按（固件预留）",
                isEmbedded: isEmbedded,
                isExpanded: $showMoreKeyOptions
            ) {
                if key.role == .voice {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("短按 · AhaType")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                        Toggle(isOn: $nativeSpeech.shortPressAhaTypeEnabled) {
                            HStack(spacing: 6) {
                                Text("使用 AhaType 整理")
                                    .font(.callout)
                                if !ahaType.isEnabled {
                                    Text("（总开关已关闭）")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!ahaType.isEnabled)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("长按")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                        Label("按住录音，松手即发送", systemImage: "hand.draw.fill")
                            .font(.callout.weight(.semibold))
                        Toggle(isOn: $nativeSpeech.longPressAhaTypeEnabled) {
                            HStack(spacing: 6) {
                                Text("使用 AhaType 整理")
                                    .font(.callout)
                                if !ahaType.isEnabled {
                                    Text("（总开关已关闭）")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!ahaType.isEnabled)
                        HStack(spacing: 10) {
                            Text("触发阈值")
                                .font(.callout)
                            Slider(
                                value: Binding(
                                    get: { Double(nativeSpeech.longPressThresholdMs) },
                                    set: { nativeSpeech.longPressThresholdMs = Int($0) }
                                ),
                                in: 200...1000,
                                step: 50
                            )
                            Text("\(nativeSpeech.longPressThresholdMs) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                } else {
                    Label("长按需固件 v2+ 支持", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: selectedPart) { _ in
            selectedTriggerTab = 0
            showMoreKeyOptions = false
        }
    }

    /// 语音键绑定方法（独立于「按键配置」模块，位于其下方）。
    /// 「按一下开始，再按一下结束」等操作说明收纳在问号帮助中，主区只保留绑定控件。
    @ViewBuilder
    private func voiceBindingSection(for key: AhaKeyKeyDraft) -> some View {
        let preset = displayedVoicePreset(for: key)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("短按绑定")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                Spacer(minLength: 4)
                InspectorHelpButton(
                    title: "绑定说明 · \(preset.title)",
                    lines: voiceBindingHelpLines(for: preset),
                    isEmbedded: isEmbedded,
                    width: 280
                )
            }

            keyBindingControls(for: key)

            if preset != .custom {
                Text("当前预设固定单键绑定；改宏请先将语音输入方式设为「自定义快捷键」。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func keyBindingControls(for key: AhaKeyKeyDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(key.displaySummary)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(key.usesMacro ? "固件宏" : "底层 HID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: selectedKeyBindingModeBinding) {
                Text("快捷键").tag(KeyBindingMode.shortcut)
                Text("宏").tag(KeyBindingMode.macro)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .disabled(key.role == .voice && displayedVoicePreset(for: key) != .custom)
            if key.usesMacro {
                macroEditor(for: key)
            } else {
                ShortcutBindingEditor(shortcut: selectedKeyShortcutBinding)
            }
        }
    }

    private func displayedVoicePreset(for key: AhaKeyKeyDraft) -> VoicePreset {
        let preset = key.voicePreset ?? .custom
        if preset.isMacOSNativeFamily { return .macOSNative }
        if preset == .wechat || preset == .doubao { return .typeless }
        return VoicePreset.visibleCases.contains(preset) ? preset : .custom
    }

    private func voiceBindingHelpLines(for preset: VoicePreset) -> [String] {
        var lines: [String] = [
            "短按：按一下开始，再按一下结束。",
            "长按：按住录音，松手即发送（见下方「更多设置」）。",
            "当前输入方式：\(preset.title)",
            preset.detail,
            "绑定方法决定按下语音键时发给系统的 HID / 宏；写入键盘后生效。",
        ]
        switch preset {
        case .macOSNative, .claudeCode, .kimiCode:
            lines.append("默认触发键为 F18；请确保麦克风、语音识别、听写等权限已开启。")
            lines.append("预设固定使用单键绑定，不可录制宏。")
        case .typeless, .wechat, .doubao:
            lines.append("默认触发键为 F19（Fn/Globe 路由）；请授予输入监控与辅助功能。")
            lines.append("预设固定使用单键绑定，不可录制宏。")
        case .custom:
            lines.append("可自由指定单键 / 组合键，或录制固件宏。")
        case .codex:
            lines.append("该方式仍在规划中。")
        }
        return lines
    }

    // MARK: - 宏编辑器视图

    @ViewBuilder
    private func macroEditor(for key: AhaKeyKeyDraft) -> some View {
        let stepCount = key.macro.count
        let byteCount = stepCount * 2
        let overLimit = byteCount > 98 // 固件 payload 上限

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("步骤")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(stepCount) · \(byteCount)/98B")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(overLimit ? .red : .secondary)
                    .lineLimit(1)
            }

            if key.macro.isEmpty {
                Text("空宏。点下方「添加步骤」开始录制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(key.macro.enumerated()), id: \.element.id) { index, step in
                        macroStepRow(
                            index: index,
                            step: step,
                            totalCount: key.macro.count
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    appendMacroStep()
                } label: {
                    Label("添加", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(overLimit)

                Button(role: .destructive) {
                    updateSelectedKey { $0.macro = [] }
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(key.macro.isEmpty)

                Spacer(minLength: 0)
            }

            if overLimit {
                Text("超过固件单键宏 98 字节 / 49 步上限，同步时会被拒绝。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("固件按顺序串行发送；延时单位 3ms（最大 765ms）。需要更长延时请叠加多个延时步骤。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !key.macro.isEmpty {
                Text("预览：\(key.macro.displaySummary)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func macroStepRow(index: Int, step: MacroStep, totalCount: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Picker("", selection: macroStepActionBinding(id: step.id)) {
                ForEach(MacroAction.allCases) { action in
                    Text(action.shortTitle).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 64)
            .layoutPriority(0)

            if step.action.takesKeycodeParam {
                Picker("", selection: macroStepKeycodeBinding(id: step.id)) {
                    Text("未设置").tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 88)
                .layoutPriority(1)
            } else if step.action.takesDelayParam {
                // 勿对带标题的 Stepper 用 labelsHidden()，否则连「15 ms」一并被藏掉。
                HStack(spacing: 4) {
                    Text("\(max(1, Int(step.param)) * 3) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 36, alignment: .trailing)
                    Stepper(
                        "",
                        value: macroStepDelayBinding(id: step.id),
                        in: 1...255
                    )
                    .labelsHidden()
                    .controlSize(.small)
                }
                .frame(maxWidth: 96)
            } else {
                Color.clear.frame(maxWidth: 88, maxHeight: 1)
            }

            Spacer(minLength: 2)

            HStack(spacing: 2) {
                Button {
                    moveMacroStep(from: index, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button {
                    moveMacroStep(from: index, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(index >= totalCount - 1)

                Button(role: .destructive) {
                    removeMacroStep(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    private func macroStepActionBinding(id: UUID) -> Binding<MacroAction> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.action ?? .noOp
            },
            set: { newAction in
                updateMacroStep(id: id) { step in
                    let previous = step.action
                    step.action = newAction
                    // 动作换类别后清零 param，避免把 "Enter 的 HID 码 0x28" 当成延时值 ×3ms 解读。
                    if previous.takesKeycodeParam != newAction.takesKeycodeParam
                        || previous.takesDelayParam != newAction.takesDelayParam
                    {
                        switch newAction {
                        case .delay:
                            step.param = 5 // 默认 15ms，比较通用
                        case .downKey, .upKey:
                            step.param = HIDUsage.enter
                        case .noOp, .upAllKeys:
                            step.param = 0
                        }
                    }
                }
            }
        )
    }

    private func macroStepKeycodeBinding(id: UUID) -> Binding<UInt8> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.param ?? 0
            },
            set: { newValue in
                updateMacroStep(id: id) { $0.param = newValue }
            }
        )
    }

    private func macroStepDelayBinding(id: UUID) -> Binding<UInt8> {
        Binding(
            get: {
                currentSelectedKey.macro.first { $0.id == id }?.param ?? 0
            },
            set: { newValue in
                updateMacroStep(id: id) { $0.param = newValue }
            }
        )
    }

    private var oledInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "显示配置", isEmbedded: isEmbedded) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.9))
                        .frame(height: 140)

                    if let image = currentOLEDPreviewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.8))
                            Text("当前仅支持动图")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("选择 GIF 或图片") {
                            selectOLEDGIF()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("预览动图") {
                            showsOLEDPlaybackPreview = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(currentModeDraft.oled.localAssetPath == nil)

                        Button("清空") {
                            clearCurrentOLED()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("仅清除当前自定义动图，不恢复出厂默认")
                    }

                    Button("清空并恢复默认") {
                        restoreDefaultOLED()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("清除自定义动图，并恢复当前 Mode 的出厂默认动图与 12 FPS")

                    Text("当前目标：\(selectedMode.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: oledFramesPerSecondBinding, in: 1 ... 30) {
                    Text("播放速度 \(currentModeDraft.oled.framesPerSecond) FPS")
                }

                Text(currentModeDraft.oled.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lightBarInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "亮度", isEmbedded: isEmbedded) {
                HStack {
                    Slider(value: brightnessBinding, in: 1...100, step: 1)
                    Text("\(currentModeDraft.lightBar.brightness)%")
                        .font(.callout.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }

            InspectorSection(title: "状态映射", isEmbedded: isEmbedded) {
                ForEach(IDEState.workflowOrder) { state in
                    HStack(spacing: 8) {
                        Text(state.shortLabel)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: 72, alignment: .leading)
                        Spacer(minLength: 4)
                        Picker("", selection: lightEffectBinding(for: state)) {
                            ForEach(LightEffectStyle.allCases) { effect in
                                Text(effect.title).tag(effect)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 120, alignment: .trailing)
                        .layoutPriority(1)
                    }
                }
            }

            AhaKeyStudioDisclosureSection(
                title: "更多灯效",
                subtitle: "状态预览格",
                isEmbedded: isEmbedded,
                isExpanded: $showMoreLightBarOptions
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lightBarPreview.shortLabel)
                        .font(.system(.title3, design: .rounded).weight(.semibold))

                    Text("画布预览：\(currentModeDraft.lightBar.effect(for: lightBarPreview).title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(IDEState.workflowOrder) { state in
                            Button {
                                lightBarPreview = state
                                previewLightEffect(for: state)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(state.shortLabel)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(currentModeDraft.lightBar.effect(for: state).title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(state == lightBarPreview ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(state == lightBarPreview ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onChange(of: selectedPart) { _ in showMoreLightBarOptions = false }
    }

    private var switchInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "实时档位", isEmbedded: isEmbedded) {
                HStack {
                    Text(currentSwitchTitle)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(currentSwitchTitle == "自动批准" ? Color.green : Color.indigo)
                        .frame(width: 10, height: 10)
                }
                Text("0 档自动批准 · 1 档手动批准（只读上报）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if bleManager.switchState == 0 {
                    Label("自动批准需 Agent、Hook，且蓝牙由 Agent 占用", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            switchEffectivenessBox
        }
    }

    @ViewBuilder
    private var switchEffectivenessBox: some View {
        let agentReady = agentManager.isInstalled && agentManager.isRunning && agentManager.hooksInstalled
        let hasAnyMissing = !agentManager.isInstalled || !agentManager.isRunning || !agentManager.hooksInstalled
        InspectorSection(title: "生效状态", isEmbedded: isEmbedded) {
            HStack(spacing: 8) {
                Image(systemName: agentReady ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(agentReady ? .green : .orange)
                Text(agentReady
                     ? "Agent 就绪：Claude / Cursor / Codex / Kimi 可随拨杆走批准。"
                     : "需先安装 Agent 与 Hook，并把蓝牙交给 Agent；否则仅为状态显示。")
                    .font(.callout)
            }

            if hasAnyMissing {
                VStack(alignment: .leading, spacing: 4) {
                    agentChecklistRow(label: "LaunchAgent 已安装", ok: agentManager.isInstalled)
                    agentChecklistRow(label: "Agent 已连接蓝牙", ok: agentManager.isRunning)
                    agentChecklistRow(label: "Claude / Cursor / Codex / Kimi Hook 已配置", ok: agentManager.hooksInstalled)
                }
                .padding(.leading, 4)

                HStack(spacing: 8) {
                    if !agentManager.isInstalled {
                        Button("安装 Agent + Hook") {
                            agentManager.install()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if !agentManager.isRunning {
                        Button("启动 Agent") {
                            agentManager.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(agentManager.bluetoothConnectionOwner == .ahaKeyStudio)
                        .help(
                            agentManager.bluetoothConnectionOwner == .ahaKeyStudio
                            ? "当前由本 App 占用蓝牙。请打开下方「设备信息…」，在「蓝牙连接」里选「由 Agent 占用」后再启 Agent；与设备信息里「启动」按钮规则一致。"
                            : "与「设备信息 · Agent」中的启动相同，由 launchd 加载并执行 ahakeyconfig-agent。"
                        )
                    }
                    Button("设备信息（蓝牙 / 启停 Agent）…") {
                        openDeviceInfo()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func agentChecklistRow(label: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(ok ? .primary : .secondary)
        }
    }


    private var statusBar: some View {
        HStack(alignment: .center, spacing: isEmbedded ? 12 : 16) {
            Label("\(selectedPart.title) · \(selectedMode.title)", systemImage: selectedPart.systemImage)
                .font(isEmbedded ? .system(size: 12, weight: .medium) : .callout)
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                .lineLimit(1)
                .layoutPriority(2)
            statusDivider
            HStack(spacing: 4) {
                Image(systemName: dirtyCount > 0 ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dirtyCount > 0 ? .orange : (isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary))
                if dirtyCount > 0 {
                    Text("\(dirtyCount)")
                        .font(isEmbedded ? .system(size: 12, weight: .semibold) : .callout)
                        .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .primary)
                }
            }
            .accessibilityLabel("未同步改动 \(dirtyCount)")
            statusDivider
            Text(syncStatusMessage)
                .font(isEmbedded ? .system(size: 12) : .callout)
                .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let lastSyncDate {
                Text("最近同步 \(Self.timeFormatter.string(from: lastSyncDate))")
                    .font(isEmbedded ? .system(size: 11) : .callout)
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                    .lineLimit(1)
            }
            if !isEmbedded {
                Button("权限诊断") {
                    showsDiagnostics = true
                }
                .buttonStyle(.borderless)
                .help("查看语音权限状态与诊断日志")
                .sheet(isPresented: $showsDiagnostics) {
                    diagnosticsSheet
                }

                Button("新手引导") {
                    voiceRelay.showsPermissionOnboarding = false
                    UnifiedOnboardingStorage.resetForReplay()
                    unifiedOnboardingCompleted = false
                }
                .buttonStyle(.borderless)
                .help("重新打开全屏新手引导，并重置各功能页一次性气泡提示")

                Button("帮助中心") {
                    showsHelpCenter = true
                }
                .buttonStyle(.borderless)
                .help("打开内嵌的帮助中心")
                .sheet(isPresented: $showsHelpCenter) {
                    HelpCenterSheet(
                        studioDraft: studioDraft,
                        selectedMode: selectedMode,
                        bleManager: bleManager
                    )
                }
            }
        }
        .padding(.horizontal, isEmbedded ? 16 : 24)
        .padding(.vertical, isEmbedded ? 10 : 12)
        .background(chromeBarBackground)
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 14)
            .opacity(isEmbedded ? 0.35 : 1)
    }

    private var chromeBarBackground: Color {
        isEmbedded ? AhaKeyStudioEmbeddedTheme.contentBackground : AhaKeyUI.ColorToken.card
    }

    private var currentModeDraft: AhaKeyModeDraft {
        studioDraft.draft(for: selectedMode)
    }

    private var currentSelectedKey: AhaKeyKeyDraft {
        let role = selectedPart.keyRole ?? .voice
        return currentModeDraft.key(for: role)
    }

    private var currentSwitchTitle: String {
        // 用统一的 liveKeyboardSwitchState：主 App 自占 BLE 时是 bleManager.switchState，
        // 否则取 agent 共享文件里的值（含用户拨杆覆盖）。否则点了画布拨杆，
        // 因为 bleManager.switchState 一直是初始 0，画布会一直停留在「自动批准」。
        liveKeyboardSwitchState == 0 ? "自动批准" : "手动批准"
    }

    /// 取键盘当前实时状态 (lightMode/switchState/workMode)：
    /// - 主 App 已自连 BLE（编辑配置时）→ 用主 App 自己的 BLE 读数
    /// - 主 App 未连，但 agent 仍占用 BLE 在写共享文件 → 读 agent 发布的缓存
    /// - 两者都没有 → nil（画布回落到模拟）
    private var liveKeyboardLightMode: Int? {
        if bleManager.isConnected { return bleManager.lightMode }
        return bleManager.agentLightMode
    }
    private var liveKeyboardSwitchState: Int {
        // 用户刚点完虚拟拨杆但 agent / BLE 还没回报新值时，优先用乐观值，按下立刻可见
        if let opt = bleManager.optimisticSwitchOverride { return opt }
        if bleManager.isConnected { return bleManager.switchState }
        return bleManager.agentSwitchState ?? 1
    }
    private var liveKeyboardWorkMode: Int? {
        if bleManager.isConnected { return bleManager.workMode }
        return bleManager.agentWorkMode
    }
    private var liveCanvasLightMode: Int? {
        guard let workMode = liveKeyboardWorkMode, selectedMode.rawValue == workMode else { return nil }
        return liveKeyboardLightMode
    }
    private var liveCanvasIDEStateValue: Int? {
        guard let workMode = liveKeyboardWorkMode, selectedMode.rawValue == workMode else { return nil }
        return bleManager.liveIDEStateValue
    }
    private var liveCanvasSwitchState: Int { liveKeyboardSwitchState }

    private func cycleModeForward() {
        let all = AhaKeyModeSlot.allCases
        let next = all[(all.firstIndex(of: selectedMode)! + 1) % all.count]
        selectedMode = next
    }

    /// 用户点击虚拟拨杆：在当前 effective switchState 基础上 0↔1 翻转，
    /// 只设置软件覆盖；最新固件中 0x91 是灯效预览，不再用于 sw_state。
    private func toggleVirtualSwitch() {
        let current = liveKeyboardSwitchState
        let next: UInt8 = current == 0 ? 1 : 0
        // 1) 立刻设乐观值 → 画布按钮即时翻转
        bleManager.applyOptimisticSwitchOverride(next)
        // 2) 保留调用入口，但 BLEManager 不会再发送旧 0x91，只写诊断日志
        if bleManager.isConnected {
            bleManager.setSwitchStateViaBLE(next)
        }
        // 3) 让 agent 设置软覆盖
        AgentManager.shared.sendSwitchOverride(next)
        // 4) 短延迟后强制重读共享文件，确认真实值已对齐（agent 写文件通常 < 100ms）
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak bleManager] in
            bleManager?.refreshAgentStateFromFileNow()
        }
        syncStatusMessage = next == 0
            ? "虚拟拨杆 → 自动批准（hook 自动放行；灯效若不变需先刷支持 0x91 的固件）"
            : "虚拟拨杆 → 手动批准（hook 交回终端确认）"
    }

    private var currentOLEDPreviewImage: NSImage? {
        guard let path = currentModeDraft.oled.localAssetPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var currentOLEDAssetURL: URL? {
        guard let path = currentModeDraft.oled.localAssetPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var currentLightEffect: LightEffectStyle {
        currentModeDraft.lightBar.effect(for: lightBarPreview)
    }

    private var isEditingConfiguration: Bool {
        agentManager.bluetoothConnectionOwner == .ahaKeyStudio
    }

    // AhaKeyStudio 直连、Agent 已连上键盘、或正在交还蓝牙的过渡期，任一满足即视为设备已连接。
    private var isEffectivelyConnected: Bool {
        bleManager.isConnected || agentManager.isAgentBLEConnected || isTransitioningToKeyboardControl
    }

    private var shouldShowTopBarInstallStartButton: Bool {
        !agentManager.isInstalled || !agentManager.hooksInstalled
    }

    private var configurationModeDetail: String {
        if isEditingConfiguration {
            if bleManager.isConnected {
                return "AhaKey Studio 正在配置键盘"
            }
            return bleManager.isScanning ? "AhaKey Studio 正在连接键盘" : "AhaKey Studio 等待连接键盘"
        }
        // 蓝牙交给 Agent：若顶栏仍显示「安装启动」，说明 Hook/Agent 未齐备，勿与左侧「已连接」拼成「已可控制」。
        if !isEditingConfiguration && shouldShowTopBarInstallStartButton && isEffectivelyConnected {
            if agentManager.isRunning && agentManager.isAgentBLEConnected {
                return "Agent 正在控制键盘"
            }
            return "安装启动后才能控制键盘"
        }
        // 蓝牙交给 Agent 时：与左侧 infoPill「已连接」口径一致（isEffectivelyConnected），避免出现「已连接」+「等待键盘」的互斥文案。
        if isEffectivelyConnected {
            if agentManager.isRunning && agentManager.isAgentBLEConnected {
                return "Agent 正在控制键盘"
            }
            if agentManager.isRunning {
                return "键盘已连接；正在同步 Agent 连接状态"
            }
            return "键盘已连接"
        }
        if agentManager.isRunning {
            return "Agent 运行中，等待键盘连接"
        }
        if agentManager.isInstalled {
            return "Agent 已安装，正在准备控制"
        }
        return "需要安装 Agent 后才能控制键盘"
    }

    private var configurationModeButtonTitle: String {
        if isSyncing {
            return "同步中…"
        }
        if isEditingConfiguration {
            return "保存配置"
        }
        return "编辑配置"
    }

    private var configurationModeButtonHelp: String {
        if isEditingConfiguration {
            if hasUnsyncedChanges {
                return "将当前草稿同步到键盘，然后把蓝牙交还给 Agent。"
            }
            return "没有未同步改动，直接把蓝牙交还给 Agent。"
        }
        return "临时由 AhaKey Studio 接管蓝牙，用于改键、LCD、同步和本机灯效测试。"
    }

    private var selectedVoicePresetBinding: Binding<VoicePreset> {
        Binding(
            get: {
                let preset = currentSelectedKey.voicePreset ?? .custom
                if preset.isMacOSNativeFamily { return .macOSNative }
                if preset == .wechat || preset == .doubao { return .typeless }
                return VoicePreset.visibleCases.contains(preset) ? preset : .custom
            },
            set: { applyVoicePreset($0) }
        )
    }

    private func permissionBadge(title: String, granted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(granted ? "已开启" : "未开启")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var currentSelectedKeySanitizedDescription: String {
        currentSelectedKey.description.sanitizedASCII(maxLength: 20)
    }

    private var selectedKeyDescriptionBinding: Binding<String> {
        Binding(
            get: { currentSelectedKey.description },
            set: { newValue in
                updateSelectedKey { key in
                    key.description = String(newValue.prefix(20))
                }
            }
        )
    }

    private var selectedKeyShortcutBinding: Binding<ShortcutBinding> {
        Binding(
            get: { currentSelectedKey.shortcut },
            set: { newValue in
                updateSelectedKey { $0.shortcut = newValue }
            }
        )
    }

    private var oledFramesPerSecondBinding: Binding<Int> {
        Binding(
            get: { currentModeDraft.oled.framesPerSecond },
            set: { newValue in
                updateCurrentMode { mode in
                    mode.oled.framesPerSecond = min(30, max(1, newValue))
                }
            }
        )
    }

    private var hasUnsyncedChanges: Bool {
        dirtyCount > 0
    }

    private var dirtyCount: Int {
        AhaKeyModeSlot.allCases.reduce(into: 0) { count, mode in
            let current = studioDraft.draft(for: mode)
            let baseline = lastSyncedDraft.draft(for: mode)
            for role in AhaKeyKeyRole.allCases where current.key(for: role) != baseline.key(for: role) {
                count += 1
            }
            if current.oled != baseline.oled {
                count += 1
            }
            if current.lightBar != baseline.lightBar {
                count += 1
            }
        }
    }

    private func restoreCurrentModeDefaults() {
        let restored = AhaKeyModeDraft.default(for: selectedMode)
        var next = studioDraft
        next.updateMode(restored)
        studioDraft = next
        syncStatusMessage = "\(selectedMode.title) 已恢复默认值，等待同步。"
    }

    private func clearCurrentOLED() {
        updateCurrentMode { mode in
            mode.oled.localAssetPath = nil
            mode.oled.statusLine = AhaKeyOLEDDraft.default(for: selectedMode).statusLine
        }
        syncStatusMessage = "\(selectedMode.title) LCD 动图已清空；写入键盘后设备端才会更新。"
    }

    /// 清除自定义动图，并恢复当前 Mode 的出厂默认（含 bundle 默认 GIF 与 12 FPS）。
    private func restoreDefaultOLED() {
        let restored = AhaKeyOLEDDraft.default(for: selectedMode)
        updateCurrentMode { mode in
            mode.oled = restored
        }
        let assetName = restored.localAssetPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "固件默认"
        syncStatusMessage = "\(selectedMode.title) LCD 已恢复默认（\(assetName)，\(restored.framesPerSecond) FPS）；请点「写入键盘」同步到设备。"
    }

    private func applyVoicePreset(_ preset: VoicePreset) {
        updateSelectedKey { key in
            key.voicePreset = preset
            if preset != .custom {
                key.shortcut = preset.defaultBinding
            }
            if key.description.isEmpty {
                key.description = key.role.defaultDescription
            }
        }
    }

    // MARK: - 宏编辑

    /// 按键当前处于 "宏" 还是 "快捷键" 录入模式。
    /// 状态仅由 `macro` 是否为空推导，避免多出一个独立 flag。
    private enum KeyBindingMode {
        case shortcut
        case macro
    }

    private var selectedKeyBindingModeBinding: Binding<KeyBindingMode> {
        Binding(
            get: { currentSelectedKey.usesMacro ? .macro : .shortcut },
            set: { newValue in
                switch newValue {
                case .shortcut:
                    updateSelectedKey { key in
                        key.macro = []
                    }
                case .macro:
                    updateSelectedKey { key in
                        guard key.macro.isEmpty else { return }
                        // Mode 0「No」键的 shortcut 故意为空，实际绑定是固件宏 ↓↓⏎；若仍用「空 shortcut → Enter 种子」，
                        // 从「单键」切回「宏」时会被误植成只按 Enter，覆盖用户刚配好的三键宏。
                        if selectedMode == .mode0, key.role == .reject {
                            key.macro = AhaKeyModeDraft.claudeNoMacroSteps.map { step in
                                MacroStep(action: step.action, param: step.param)
                            }
                            return
                        }
                        // 其它键：用当前 shortcut 的主键作种子（没配就用 Enter），避免空白宏列表。
                        let seed: UInt8 = key.shortcut.keyCode == 0 ? HIDUsage.enter : key.shortcut.keyCode
                        key.macro = [
                            MacroStep(action: .downKey, param: seed),
                            MacroStep(action: .upKey, param: seed),
                        ]
                    }
                }
            }
        )
    }

    private func appendMacroStep() {
        updateSelectedKey { key in
            // 默认追加 "按下 Enter"——多数用户添加步骤都是想按键，延时/松开可以再切。
            key.macro.append(MacroStep(action: .downKey, param: HIDUsage.enter))
        }
    }

    private func removeMacroStep(at index: Int) {
        updateSelectedKey { key in
            guard key.macro.indices.contains(index) else { return }
            key.macro.remove(at: index)
        }
    }

    private func moveMacroStep(from index: Int, by offset: Int) {
        updateSelectedKey { key in
            let target = index + offset
            guard key.macro.indices.contains(index), key.macro.indices.contains(target) else { return }
            key.macro.swapAt(index, target)
        }
    }

    private func updateMacroStep(id: UUID, transform: (inout MacroStep) -> Void) {
        updateSelectedKey { key in
            guard let idx = key.macro.firstIndex(where: { $0.id == id }) else { return }
            transform(&key.macro[idx])
        }
    }

    private func updateSelectedKey(_ transform: (inout AhaKeyKeyDraft) -> Void) {
        guard let role = selectedPart.keyRole else { return }
        updateCurrentMode { mode in
            var key = mode.key(for: role)
            transform(&key)
            mode.updateKey(key)
        }
    }

    private func updateCurrentMode(_ transform: (inout AhaKeyModeDraft) -> Void) {
        updateMode(selectedMode, transform)
    }

    private func updateMode(_ modeSlot: AhaKeyModeSlot, _ transform: (inout AhaKeyModeDraft) -> Void) {
        var next = studioDraft
        var mode = next.draft(for: modeSlot)
        transform(&mode)
        next.updateMode(mode)
        studioDraft = next
    }

    private func partIsDirty(_ part: AhaKeyStudioPart) -> Bool {
        let current = studioDraft.draft(for: selectedMode)
        let baseline = lastSyncedDraft.draft(for: selectedMode)
        switch part {
        case .key1, .key2, .key3, .key4:
            guard let role = part.keyRole else { return false }
            return current.key(for: role) != baseline.key(for: role)
        case .oledDisplay:
            return current.oled != baseline.oled
        case .lightBar:
            return current.lightBar != baseline.lightBar
        case .toggleSwitch:
            return false
        case .magneticPort:
            return false
        }
    }

    private func dirtyPartsForCurrentMode() -> Set<AhaKeyStudioPart> {
        Set(AhaKeyStudioPart.allCases.filter(partIsDirty(_:)))
    }

    private func selectOLEDGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OLEDFrameEncoder.validateGIFSourceFileSize(at: url)
                try OLEDFrameEncoder.validateFrameCount(at: url)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "图片文件不符合上传限制。"
                syncStatusMessage = msg
                updateCurrentMode { mode in
                    mode.oled.statusLine = msg
                }
                return
            }
            let frameCount = OLEDFrameEncoder.frameCount(at: url)
            updateCurrentMode { mode in
                mode.oled.localAssetPath = url.path
                mode.oled.statusLine = "已选 \(max(frameCount, 1)) 帧图片预览；写入时将上传到 \(selectedMode.title) 固定分区。"
            }
            syncStatusMessage = "已更新 \(selectedMode.title) 的 LCD 预览；写入设备请使用底部通用按钮。"
        }
    }

    private func handleConfigurationModeButton() {
        if isEditingConfiguration {
            finishEditingConfiguration()
        } else {
            enterEditingConfiguration()
        }
    }

    private func installStartAgentFromTopBar() {
        if agentManager.bluetoothConnectionOwner != .agentDaemon {
            agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        }
        if !agentManager.isInstalled || !agentManager.hooksInstalled {
            agentManager.install()
        } else {
            agentManager.start()
        }
    }

    private func enterEditingConfiguration() {
        isTransitioningToKeyboardControl = false
        agentManager.setBluetoothConnectionOwner(.ahaKeyStudio, bleManager: bleManager)
        syncStatusMessage = "已进入编辑配置，AhaKey Studio 将临时接管蓝牙。"
    }

    private func finishEditingConfiguration() {
        guard hasUnsyncedChanges else {
            returnToKeyboardControl()
            return
        }

        if bleManager.isConnected && bleManager.commandCharReady {
            syncAllModesToDevice(returnToKeyboardControlWhenDone: true)
        } else {
            syncStatusMessage = "设备连接中，连接成功后将自动同步并返回控制模式…"
            bleManager.userInitiatedConnect()
            waitForConnectionThenSync()
        }
    }

    private func writeToKeyboard() {
        performUnifiedDeviceWrite(returnToKeyboardControlWhenDone: false, showResultAlert: true)
    }

    private func completeEditingAfterSuccessfulWrite() {
        commitModeNameEdit()
        withAnimation(.easeInOut(duration: 0.18)) {
            isEditingInspector = false
        }
        returnToKeyboardControl()
    }

    // 轮询等待 BLE 连接且命令通道就绪（最多 10 秒），连接后自动同步并返回键盘控制。
    private func waitForConnectionThenSync() {
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if bleManager.isConnected && bleManager.commandCharReady {
                    syncAllModesToDevice(returnToKeyboardControlWhenDone: true)
                    return
                }
            }
            syncStatusMessage = "连接超时，本次未写入键盘；已释放蓝牙给 Agent，可再次进入编辑后重试保存。"
            returnToKeyboardControl()
        }
    }

    private func returnToKeyboardControl() {
        isTransitioningToKeyboardControl = true
        agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        syncStatusMessage = "正在恢复键盘控制，Agent 正在连接键盘…"
        monitorAgentReconnect()
    }

    // 返回键盘控制后每 2s 轮询一次 Agent BLE 状态（等待异步 socket 查询完成后再读值），
    // 最多等待 20s；超时后尝试重启 Agent。过渡期结束时清除 isTransitioningToKeyboardControl。
    private func monitorAgentReconnect() {
        Task { @MainActor in
            for i in 0..<10 {
                // 第一次等短些，让 Agent 有时间启动
                let waitMs: UInt64 = i == 0 ? 1_500_000_000 : 2_000_000_000
                try? await Task.sleep(nanoseconds: waitMs)
                agentManager.refresh()
                // 等待 refresh() 内部的异步 socket 查询写回主线程（最多 2.5s timeout）
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if agentManager.isAgentBLEConnected {
                    syncStatusMessage = "已返回键盘控制，Agent 将接管蓝牙。"
                    isTransitioningToKeyboardControl = false
                    return
                }
                // 约 10s 后 Agent 仍未连上，尝试重启
                if i == 2, !agentManager.isAgentBLEConnected {
                    agentManager.start()
                }
            }
            syncStatusMessage = "已返回键盘控制，Agent 将接管蓝牙。"
            isTransitioningToKeyboardControl = false
        }
    }

    private func syncAllModesToDevice(returnToKeyboardControlWhenDone: Bool = false) {
        performUnifiedDeviceWrite(returnToKeyboardControlWhenDone: returnToKeyboardControlWhenDone, showResultAlert: false)
    }

    private func performUnifiedDeviceWrite(returnToKeyboardControlWhenDone: Bool, showResultAlert: Bool) {
        guard bleManager.isConnected && bleManager.commandCharReady else {
            let message = showResultAlert ? "设备未连接，请先连接键盘后重试。" : "设备未连接或命令通道未就绪，当前只保存本地草稿。"
            syncStatusMessage = message
            if showResultAlert {
                writeResultAlertMessage = message
                showsWriteResultAlert = true
            }
            return
        }

        applyCursorRejectMacroSelfHealIfNeeded()
        isSyncing = true
        syncStatusMessage = "正在准备写入设备…"
        let returnAgent = returnToKeyboardControlWhenDone

        Task { @MainActor in
            do {
                let uploadedOLEDCount = try await uploadChangedOLEDsToDevice()
                var commands = commandsForModes(AhaKeyModeSlot.allCases)
                commands.append((data: AhaKeyCommand.saveConfig(), label: "保存全部配置到设备"))

                let total = commands.count
                if uploadedOLEDCount > 0 {
                    self.syncStatusMessage = "已上传 \(uploadedOLEDCount) 个 LCD 动图，正在写入灯效与键位配置（约 \(total) 条）…"
                } else {
                    self.syncStatusMessage = "正在写入灯效与键位配置（约 \(total) 条）…"
                }
                self.bleManager.writeCommandsSequentially(commands) {
                    Task { @MainActor in
                        // 队列与 50ms 间隔已保证顺序；略等再交还蓝牙，避免固件尚未处理完最后帧。
                        try? await Task.sleep(nanoseconds: UInt64(250) * 1_000_000)
                        self.lastSyncedDraft = self.studioDraft
                        self.lastSyncDate = Date()
                        self.isSyncing = false
                        self.syncStatusMessage = "已全部写入设备并保存。"
                        if showResultAlert {
                            self.writeResultAlertMessage = "配置已成功写入键盘。"
                            self.showsWriteResultAlert = true
                        }
                        if returnAgent {
                            self.returnToKeyboardControl()
                        }
                    }
                }
            } catch {
                let message = "写入键盘失败：\(error.localizedDescription)"
                self.isSyncing = false
                self.syncStatusMessage = message
                if showResultAlert {
                    self.writeResultAlertMessage = message
                    self.showsWriteResultAlert = true
                }
            }
        }
    }

    private func uploadChangedOLEDsToDevice() async throws -> Int {
        var uploadCount = 0

        for mode in AhaKeyModeSlot.allCases {
            let draft = studioDraft.draft(for: mode)
            guard let assetPath = draft.oled.localAssetPath else { continue }

            let baseline = lastSyncedDraft.draft(for: mode).oled
            let deviceFrameCount = bleManager.keyboardPictureStates[mode.rawValue]?.frameCount ?? 0
            guard draft.oled != baseline || deviceFrameCount == 0 else { continue }

            let assetURL = URL(fileURLWithPath: assetPath)
            try OLEDFrameEncoder.validateGIFSourceFileSize(at: assetURL)
            let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)

            updateMode(mode) { modeDraft in
                modeDraft.oled.statusLine = "正在上传动图到 \(mode.title)…"
            }
            syncStatusMessage = "正在上传 \(mode.title) 的 LCD 动图…"

            let startIndex = try await resolveOLEDUploadStartIndex(for: mode, frameCount: frames.count)
            try await bleManager.uploadOLEDFrames(
                frames,
                fps: draft.oled.framesPerSecond,
                mode: UInt8(mode.rawValue),
                startIndex: UInt16(startIndex)
            )

            updateMode(mode) { modeDraft in
                modeDraft.oled.statusLine = "已上传 \(frames.count) 帧到设备，槽位起点 \(startIndex)；切换模式时会先显示描述，再回到当前模式动图。"
            }
            uploadCount += 1
        }

        return uploadCount
    }

    private func resendCurrentModeToDevice() {
        guard bleManager.isConnected && bleManager.commandCharReady else {
            syncStatusMessage = "设备未连接或命令通道未就绪，当前只保存本地草稿。"
            return
        }

        applyCursorRejectMacroSelfHealIfNeeded()
        var commands = commandsForModes([selectedMode])
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存 \(selectedMode.title) 当前配置"))

        isSyncing = true
        syncStatusMessage = "正在写入 \(selectedMode.title)…"
        bleManager.writeCommandsSequentially(commands) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(150) * 1_000_000)
                self.lastSyncDate = Date()
                self.isSyncing = false
                self.syncStatusMessage = "已重新发送 \(self.selectedMode.title) 当前模式。"
            }
        }
    }

    /// Cursor 档「取消键」若仍为默认 ⌫ 却残留宏，同步会走 0x74 而非单键。清掉误残留宏并与迁移逻辑一致。
    private func applyCursorRejectMacroSelfHealIfNeeded() {
        var next = studioDraft
        var m1 = next.draft(for: .mode1)
        var reject = m1.key(for: .reject)
        let defaultR = AhaKeyModeDraft.default(for: .mode1).key(for: .reject)
        guard !reject.macro.isEmpty, reject.shortcut == defaultR.shortcut else { return }
        reject.macro = []
        m1.updateKey(reject)
        next.updateMode(m1)
        studioDraft = next
    }

    private func commandsForModes(_ modes: [AhaKeyModeSlot]) -> [(data: Data, label: String)] {
        var commands: [(data: Data, label: String)] = []

        for mode in modes {
            let draft = studioDraft.draft(for: mode)
            for role in AhaKeyKeyRole.allCases {
                let key = draft.key(for: role)
                let keyIndex = UInt8(role.rawValue)
                let modeByte = UInt8(mode.rawValue)

                if key.usesMacro {
                    // 固件对 0x73 快捷键、0x74 宏是分层存储的；从「快捷键」改「宏」时须先清掉旧快捷键，否则会残留。
                    commands.append((
                        data: AhaKeyCommand.setKeyMapping(
                            mode: modeByte,
                            keyIndex: keyIndex,
                            hidCodes: []
                        ),
                        label: "清除 \(mode.title) \(key.title) 快捷键层（将写入宏）"
                    ))
                    commands.append((
                        data: AhaKeyCommand.setKeyMacro(
                            mode: modeByte,
                            keyIndex: keyIndex,
                            macroData: key.macro.flattenedBytes
                        ),
                        label: "写入 \(mode.title) \(key.title) 宏: \(key.macro.displaySummary)"
                    ))
                } else {
                    // 从「宏」改「快捷键 / 无键」时须先发空 0x74，否则设备可能仍走旧宏（Cursor/其它 mode 上表现为改键不生效）。
                    commands.append((
                        data: AhaKeyCommand.setKeyMacro(
                            mode: modeByte,
                            keyIndex: keyIndex,
                            macroData: []
                        ),
                        label: "清除 \(mode.title) \(key.title) 宏层（将写入快捷键）"
                    ))
                    if !key.shortcut.hidCodes.isEmpty {
                        commands.append((
                            data: AhaKeyCommand.setKeyMapping(
                                mode: modeByte,
                                keyIndex: keyIndex,
                                hidCodes: key.shortcut.hidCodes
                            ),
                            label: "写入 \(mode.title) \(key.title) 快捷键: \(key.shortcut.displayLabel)"
                        ))
                    } else {
                        commands.append((
                            data: AhaKeyCommand.setKeyMapping(
                                mode: modeByte,
                                keyIndex: keyIndex,
                                hidCodes: []
                            ),
                            label: "清除 \(mode.title) \(key.title) 快捷键"
                        ))
                    }
                }

                let sanitizedDescription = key.description.sanitizedASCII(maxLength: 20)
                commands.append((
                    data: AhaKeyCommand.setKeyDescription(
                        mode: UInt8(mode.rawValue),
                        keyIndex: keyIndex,
                        text: key.description
                    ),
                    label: "写入 \(mode.title) \(key.title) 描述: \(sanitizedDescription.isEmpty ? "空白" : sanitizedDescription)"
                ))
            }
        }

        for mode in modes {
            let lb = studioDraft.draft(for: mode).lightBar
            let effects = IDEState.allCases.map { lb.effect(for: $0).firmwareIndex }
            commands.append((
                AhaKeyCommand.setLightMapping(mode: UInt8(mode.rawValue), stateEffects: effects),
                "灯效映射 \(mode.title)"
            ))
        }

        let brightness = UInt8(studioDraft.draft(for: modes[0]).lightBar.brightness)
        commands.append((AhaKeyCommand.setBrightness(brightness), "亮度 \(brightness)%"))

        return commands
    }

    /// 首次连接键盘后自动把 bundle 默认 GIF 推到没有上传过的 mode slot。
    /// 触发时机：bleManager.keyboardPictureStates 四个 mode 都查回来之后
    /// （由 .onChange(of: bleManager.keyboardPictureStates) 调度）。
    /// 守卫：
    /// - 只上传 picLength==0（slot 完全空）的 mode；非 0 视为用户已自定义或固件出厂图
    /// - 只在 draft 的 localAssetPath 仍指向 bundle 默认（用户没手动换过）时上传
    /// - 每次连接只跑一次（oledAutoSyncDoneForConnection 标志位由 .onChange(isConnected) 重置）
    private func autoSyncDefaultOLEDsIfNeeded() async {
        guard bleManager.isConnected else { return }
        // 四个 mode 全部 0x83 查询回来才动手，避免半截判断把已上传 slot 当成空
        guard bleManager.keyboardPictureStates.count == AhaKeyModeSlot.allCases.count else { return }

        for mode in AhaKeyModeSlot.allCases {
            guard let state = bleManager.keyboardPictureStates[mode.rawValue] else { continue }
            guard state.frameCount == 0 else { continue }
            guard let bundledPath = DefaultOLEDAssets.bundledAssetPath(for: mode) else { continue }
            let draft = studioDraft.draft(for: mode)
            guard let drafPath = draft.oled.localAssetPath,
                  DefaultOLEDAssets.isBundledPath(drafPath) else { continue }

            let assetURL = URL(fileURLWithPath: bundledPath)
            do {
                try OLEDFrameEncoder.validateGIFSourceFileSize(at: assetURL)
                let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)
                let startIndex = try await resolveOLEDUploadStartIndex(for: mode, frameCount: frames.count)
                try await bleManager.uploadOLEDFrames(
                    frames,
                    fps: draft.oled.framesPerSecond,
                    mode: UInt8(mode.rawValue),
                    startIndex: UInt16(startIndex)
                )
                updateMode(mode) { m in
                    m.oled.statusLine = "已自动同步默认动图（\(frames.count) 帧）。"
                }
            } catch {
                syncStatusMessage = "\(mode.title) 默认动图自动同步失败: \(error.localizedDescription)"
            }
        }
    }

    private func resolveOLEDUploadStartIndex(for targetMode: AhaKeyModeSlot, frameCount: Int) async throws -> Int {
        guard frameCount <= AhaKeyCommand.oledMaxFramesPerMode else {
            throw OLEDUploadError.tooManyFrames(max: AhaKeyCommand.oledMaxFramesPerMode)
        }

        _ = try? await bleManager.readPictureState(mode: UInt8(targetMode.rawValue))
        return Int(AhaKeyCommand.oledStartIndex(forMode: UInt8(targetMode.rawValue)))
    }

    private func canPlacePictureRange(
        start: Int,
        count: Int,
        occupiedRegions: [(start: Int, end: Int)],
        maxCapacity: Int
    ) -> Bool {
        let end = start + count
        guard start >= 0, end <= maxCapacity else { return false }
        return occupiedRegions.allSatisfy { region in
            end <= region.start || start >= region.end
        }
    }

    private func findFreePictureSpace(
        occupiedRegions: [(start: Int, end: Int)],
        neededCount: Int,
        maxCapacity: Int
    ) -> Int? {
        guard !occupiedRegions.isEmpty else { return 0 }

        if occupiedRegions[0].start >= neededCount {
            return 0
        }

        for index in 0 ..< (occupiedRegions.count - 1) {
            let gapStart = occupiedRegions[index].end
            let gapEnd = occupiedRegions[index + 1].start
            if gapEnd - gapStart >= neededCount {
                return gapStart
            }
        }

        let lastEnd = occupiedRegions.last?.end ?? 0
        if lastEnd + neededCount <= maxCapacity {
            return lastEnd
        }

        return nil
    }

    private func lightEffectBinding(for state: IDEState) -> Binding<LightEffectStyle> {
        Binding(
            get: { currentModeDraft.lightBar.effect(for: state) },
            set: { newEffect in
                var draft = studioDraft
                var mode = draft.draft(for: selectedMode)
                if let idx = mode.lightBar.stateMappings.firstIndex(where: { $0.state == state }) {
                    mode.lightBar.stateMappings[idx].effect = newEffect
                }
                draft.updateMode(mode)
                studioDraft = draft
                AhaKeyStudioStore.save(studioDraft)
                lightBarPreview = state
                previewLightEffect(newEffect)
            }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { Double(currentModeDraft.lightBar.brightness) },
            set: { newValue in
                var draft = studioDraft
                var mode = draft.draft(for: selectedMode)
                mode.lightBar.brightness = Int(newValue)
                draft.updateMode(mode)
                studioDraft = draft
                AhaKeyStudioStore.save(studioDraft)
                previewBrightness(Int(newValue))
            }
        )
    }

    private func previewLightEffect(for state: IDEState) {
        previewLightEffect(currentModeDraft.lightBar.effect(for: state))
    }

    private func previewLightEffect(_ effect: LightEffectStyle) {
        guard bleManager.isConnected && bleManager.commandCharReady else {
            syncStatusMessage = "已更新虚拟灯效预览；连接键盘后可预览到设备。"
            return
        }
        bleManager.previewLightEffect(effect.firmwareIndex)
        syncStatusMessage = "正在预览灯效：\(effect.title)。"
    }

    private func previewBrightness(_ value: Int) {
        guard bleManager.isConnected && bleManager.commandCharReady else {
            syncStatusMessage = "已更新亮度为 \(value)%；连接键盘后可预览到设备。"
            return
        }
        bleManager.setBrightness(UInt8(max(1, min(100, value))))
        syncStatusMessage = "正在预览灯光强度：\(value)% 。"
    }

    private func infoPill(title: String, subtitle: String, accent: Color, width: CGFloat = 86) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(subtitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func manualCallout(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.callout)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func openNativeSpeechPrivacySettings() {
        openNativeSpeechPrivacySettingsURL()
    }

    private var nativeSpeechPermissionsReady: Bool {
        nativeSpeech.microphoneGranted &&
            nativeSpeech.speechRecognitionGranted &&
            nativeSpeech.siriEnabled &&
            nativeSpeech.dictationEnabled
    }

    private var startupPermissionsReady: Bool {
        bleManager.bluetoothPermissionGranted &&
            bleManager.bluetoothPoweredOn &&
            voiceRelay.inputMonitoringGranted &&
            voiceRelay.accessibilityGranted &&
            nativeSpeech.microphoneGranted &&
            nativeSpeech.speechRecognitionGranted &&
            nativeSpeech.siriEnabled &&
            nativeSpeech.dictationEnabled
    }

    private func scheduleStartupPermissionOnboarding() {
        voiceRelay.showsPermissionOnboarding = false
        bleManager.refreshBluetoothAuthorization()
        voiceRelay.refreshPermissions(deferredTCCRequery: true)
        nativeSpeech.refreshPermissions(deferredTCCRequery: true)
    }

    private func refreshStartupPermissionOnboarding() {
        voiceRelay.showsPermissionOnboarding = false
    }

    private func handleStudioNavigation(_ notification: Notification) {
        if let partRaw = notification.userInfo?[StudioNavigationUserInfoKey.part] as? String,
           let part = AhaKeyStudioPart(rawValue: partRaw) {
            selectedPart = part
            isEditingInspector = false
            return
        }

        guard let raw = notification.userInfo?[StudioNavigationUserInfoKey.section] as? String,
              let section = StudioNavigationSection(rawValue: raw) else { return }

        switch section {
        case .voiceAgent:
            selectedPart = .key1
        case .device:
            openDeviceInfo()
        case .approve:
            selectedPart = .toggleSwitch
        case .oled:
            selectedPart = .oledDisplay
        case .voice:
            selectedPart = .key1
        }
    }
}

private struct VoicePermissionOnboardingSheet: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var voiceRelay: VoiceRelayService
    @ObservedObject var nativeSpeech: NativeSpeechTranscriptionService
    @Environment(\.dismiss) private var dismiss

    @State private var fixInProgress = false
    @State private var fixAlertTitle = ""
    @State private var fixAlertMessage = ""
    @State private var fixAlertIsSuccess = false
    @State private var showFixAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新手权限引导")
                .font(.system(size: 24, weight: .semibold))

            Text("AhaKey Studio 首次使用需要完成几项系统授权：连接键盘需要蓝牙，后台接管语音键需要输入监控与辅助功能，macOS 原生语音需要麦克风、语音转写、Siri 与听写。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(title: "蓝牙", granted: bleManager.bluetoothPermissionGranted && bleManager.bluetoothPoweredOn, detail: bleManager.bluetoothPermissionGranted ? "打开系统蓝牙，用于发现、连接和同步 AhaKey 键盘。" : "在「隐私与安全性 > 蓝牙」中允许 AhaKey Studio 使用蓝牙。")
                permissionRow(title: "麦克风", granted: nativeSpeech.microphoneGranted, detail: "允许 AhaKey Studio 使用苹果原生语音采集。")
                permissionRow(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted, detail: "允许 AhaKey Studio 使用苹果原生语音识别。")
                permissionRow(title: "Siri", granted: nativeSpeech.siriEnabled, detail: "在「系统设置 > Siri 与聚焦」里开启 Siri，供 macOS 原生语音能力使用。")
                permissionRow(title: "听写", granted: nativeSpeech.dictationEnabled, detail: "在「系统设置 > 键盘 > 听写」里开启听写，保证系统语音组件完整可用。")
                permissionRow(title: "辅助功能", granted: voiceRelay.accessibilityGranted, detail: "允许 AhaKey Studio 把语音键转换成苹果原生转写或 Fn/Globe。")
                permissionRow(title: "输入监控", granted: voiceRelay.inputMonitoringGranted, detail: "允许 AhaKey Studio 在后台监听实体语音键；设置完成后通常需要退出并重新打开。")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("授权步骤")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("1. 点「现在申请权限」，按系统弹窗允许蓝牙、麦克风和语音转写。")
                Text("2. 自动打开系统设置后，依次开启 Siri、听写、辅助功能。")
                Text("3. 最后开启输入监控；系统提示重启时退出并重新打开。")
                Text("4. 回到这里点「我已完成，重新检查」继续体验输入。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("若系统里已勾选允许，本应用仍显示未开启：请完全退出 AhaKey Studio 并再启动一次。输入监控、辅助功能等常按进程生效，只点「重新检查」或从后台切回，有时读到的仍是旧状态，重启后即可与系统设置一致。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("外发 / DMG / Xcode：默认正式包在系统「隐私与安全性」里显示为「AhaKey Studio」；用 Xcode 以 Debug 运行本工程时显示为「AhaKey Studio（调试）」，请按名称分别授权。路径或签名不同也会被系统当成另一款 App。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("蓝牙 \(bleManager.bluetoothPermissionGranted ? (bleManager.bluetoothPoweredOn ? "已开启" : "已授权但蓝牙关闭") : "未授权")")
                Text(voiceRelay.lastPermissionCheckSummary)
                Text(nativeSpeech.lastPermissionCheckSummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("现在申请权限") {
                    requestPermissionsThenOpenPrivacySettingsIfNeeded(
                        bleManager: bleManager,
                        voiceRelay: voiceRelay,
                        nativeSpeech: nativeSpeech
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("我已完成，重新检查") {
                    bleManager.refreshBluetoothAuthorization()
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                }
                .buttonStyle(.bordered)

                RestartToApplyPermissionsButton(title: "退出并重新打开")

                if !allPermissionsReady {
                    Button("打开系统设置") {
                        openCombinedVoicePrivacySettingsURL()
                    }
                    .buttonStyle(.bordered)
                }

                if DebugSigningFixer.isAvailable {
                    Button(fixInProgress ? "重置中…" : "⚙️ 重置开发环境签名（通常不需要）") {
                        runDebugSigningFix()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .disabled(fixInProgress)
                    .help("仅在异常情况下使用：证书过期 / 换 Mac / Team ID 变化 / 钥匙串损坏导致权限失效时，点一下会重新签名 app 并重置 TCC 授权。正式发行版（无源码目录）看不到此按钮。")
                }

                Spacer()

                Button("稍后再说") {
                    voiceRelay.dismissPermissionOnboarding()
                    dismiss()
                }
                .buttonStyle(.borderless)
            }

            if allPermissionsReady {
                Text("新手权限已经齐了。关闭这个弹窗后，AhaKey Studio 可以连接键盘、后台监听语音键，macOS 原生语音也可以正常使用。")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("仍有权限未开启。请按上方状态逐项处理，全部变为绿色后再关闭弹窗。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onChange(of: voiceRelay.inputMonitoringGranted) { _ in
            closeIfReady()
        }
        .onChange(of: voiceRelay.accessibilityGranted) { _ in
            closeIfReady()
        }
        .onChange(of: bleManager.bluetoothPermissionGranted) { _ in
            closeIfReady()
        }
        .onChange(of: bleManager.bluetoothPoweredOn) { _ in
            closeIfReady()
        }
        .alert(fixAlertTitle, isPresented: $showFixAlert) {
            if fixAlertIsSuccess {
                Button("立即退出 App") { NSApp.terminate(nil) }
                Button("稍后再退", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(fixAlertMessage)
        }
    }

    private func runDebugSigningFix() {
        fixInProgress = true
        DebugSigningFixer.run { result in
            fixInProgress = false
            fixAlertIsSuccess = result.success
            fixAlertTitle = result.success ? "修复完成" : "修复失败"
            fixAlertMessage = result.output
            showFixAlert = true
        }
    }

    private func closeIfReady() {
        guard allPermissionsReady else { return }
        voiceRelay.dismissPermissionOnboarding()
        dismiss()
    }

    private var allPermissionsReady: Bool {
        bleManager.bluetoothPermissionGranted &&
            bleManager.bluetoothPoweredOn &&
            voiceRelay.inputMonitoringGranted &&
            voiceRelay.accessibilityGranted &&
            nativeSpeech.microphoneGranted &&
            nativeSpeech.speechRecognitionGranted &&
            nativeSpeech.siriEnabled &&
            nativeSpeech.dictationEnabled
    }

    private func permissionRow(title: String, granted: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(granted ? "已开启" : "未开启")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ShortcutBindingEditor: View {
    @Binding var shortcut: ShortcutBinding
    @State private var isRecordingPrimaryKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("修饰键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(ShortcutModifier.allCases) { modifier in
                        Toggle(isOn: modifierBinding(modifier)) {
                            Text(modifier.symbol)
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .help(modifier.title)
                    }
                    if !shortcut.modifiers.isEmpty {
                        Button("清除") {
                            var next = shortcut
                            next.modifiers = []
                            shortcut = next
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("主键")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PrimaryKeyInputField(
                    shortcut: $shortcut,
                    isRecording: $isRecordingPrimaryKey
                )
            }

            if !shortcut.modifiers.isEmpty {
                Text("当前为组合键（\(shortcut.displayLabel)）。若你只想发单键 Enter，勿打开 ⌘/⌃ 等，或点「清除修饰键」后再选 Enter。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func modifierBinding(_ modifier: ShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { shortcut.modifiers.contains(modifier) },
            set: { on in
                var next = shortcut
                next.setModifier(modifier, enabled: on)
                shortcut = next
            }
        )
    }

}

private struct PrimaryKeyInputField: View {
    @Binding var shortcut: ShortcutBinding
    @Binding var isRecording: Bool

    private var displayText: String {
        shortcut.keyCode == 0 ? "直接按下键盘快捷键即可" : HIDUsage.name(for: shortcut.keyCode)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isRecording ? Color.accentColor : Color.black.opacity(0.12), lineWidth: isRecording ? 1.5 : 1)
                )

            KeyCaptureOverlay(
                shortcut: $shortcut,
                isRecording: $isRecording,
                onActivate: {
                    isRecording = true
                }
            )
            .padding(.trailing, 38)

            HStack(spacing: 8) {
                Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                    .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                Text(displayText)
                    .font(.callout)
                    .foregroundStyle(shortcut.keyCode == 0 && !isRecording ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer()

                Menu {
                    Button("直接按下键盘快捷键即可") {
                        shortcut = ShortcutBinding()
                        isRecording = false
                    }
                    Divider()
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Button(option.name) {
                            var next = shortcut
                            next.keyCode = option.code
                            shortcut = next
                            isRecording = false
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("展开下拉列表")
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .help("直接按键设置主键，点击箭头展开下拉列表。")
    }
}

private struct KeyCaptureOverlay: NSViewRepresentable {
    @Binding var shortcut: ShortcutBinding
    @Binding var isRecording: Bool
    let onActivate: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        configure(nsView)
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    private func configure(_ view: KeyCaptureNSView) {
        view.onBeginRecording = {
            onActivate()
            isRecording = true
        }
        view.onCapture = { event in
            guard let hidCode = HIDUsage.hidCode(forMacKeyCode: event.keyCode) else {
                NSSound.beep()
                isRecording = false
                return
            }
            shortcut = ShortcutBinding(
                modifiers: shortcutModifiers(from: event.modifierFlags),
                keyCode: hidCode
            )
            isRecording = false
        }
        view.onCaptureModifier = { keyCode in
            guard let hidCode = HIDUsage.hidCode(forMacKeyCode: keyCode) else {
                NSSound.beep()
                isRecording = false
                return
            }
            shortcut = ShortcutBinding(modifiers: [], keyCode: hidCode)
            isRecording = false
        }
    }

    final class KeyCaptureNSView: NSView {
        var onBeginRecording: (() -> Void)?
        var onCapture: ((NSEvent) -> Void)?
        var onCaptureModifier: ((UInt16) -> Void)?
        private var pendingModifierCapture: DispatchWorkItem?

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onBeginRecording?()
        }

        override func keyDown(with event: NSEvent) {
            pendingModifierCapture?.cancel()
            pendingModifierCapture = nil
            onCapture?(event)
        }

        override func flagsChanged(with event: NSEvent) {
            onBeginRecording?()
            pendingModifierCapture?.cancel()
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control)
                || flags.contains(.option)
                || flags.contains(.shift)
                || flags.contains(.command)
                || flags.contains(.capsLock)
                || flags.contains(.function)
            else {
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                self?.onCaptureModifier?(event.keyCode)
                self?.pendingModifierCapture = nil
            }
            pendingModifierCapture = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
        }
    }
}

private func shortcutModifiers(from flags: NSEvent.ModifierFlags) -> [ShortcutModifier] {
    var modifiers: [ShortcutModifier] = []
    if flags.contains(.control) { modifiers.append(.control) }
    if flags.contains(.option) { modifiers.append(.option) }
    if flags.contains(.shift) { modifiers.append(.shift) }
    if flags.contains(.command) { modifiers.append(.command) }
    return modifiers
}

private struct CanvasKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.12, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct AhaKeyKeyboardCanvasView: View {
    let modeDraft: AhaKeyModeDraft
    let selectedPart: AhaKeyStudioPart
    let lightBarPreview: IDEState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>
    let onSelect: (AhaKeyStudioPart) -> Void
    let onModeSwitch: () -> Void
    var onSwitchToggle: (() -> Void)? = nil
    var liveLightMode: Int? = nil
    var liveIDEStateValue: Int? = nil
    var switchState: Int = 1   // 0=auto, 1=manual; firmware uses for color/effect overrides
    /// 0x83 查询出的当前 mode flash 帧数：nil=尚未查询/未连接；0=用户没上传；>0=已上传 N 帧
    var keyboardPictureFrameCount: Int? = nil

    @State private var modeSwitchPressed = false
    @State private var leverPressed = false

    private let baseWidth: CGFloat = 109
    private let baseHeight: CGFloat = 54

    var body: some View {
        GeometryReader { proxy in
            let drawingWidth = min(proxy.size.width, proxy.size.height * (baseWidth / baseHeight))
            let drawingHeight = drawingWidth * (baseHeight / baseWidth)

            ZStack {
                keyboardFrame(width: drawingWidth, height: drawingHeight)
            }
            .frame(width: drawingWidth, height: drawingHeight)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func keyboardFrame(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color(red: 0.92, green: 0.95, blue: 0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 14)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                .padding(12)

            VStack {
                Spacer()
            }

            // 螺丝挪到真正的"边角内侧" + 缩小直径 4.8 → 3.6：
            // 旧位置 (8,8)/(8,46) 会被按键灰底矩形和灯条/Key1 边线擦边或交叠。
            // 新位置每颗距离灯条/按键灰底/Key 边都留出 ≥ 3 个基线单位。
            ForEach(Array([CGPoint(x: 5.5, y: 5.5), CGPoint(x: 103.5, y: 5.5), CGPoint(x: 5.5, y: 48.5), CGPoint(x: 103.5, y: 48.5)].enumerated()), id: \.offset) { _, point in
                Circle()
                    .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                    .background(Circle().fill(Color.white.opacity(0.4)))
                    .frame(width: scaled(3.6, in: width), height: scaled(3.6, in: width))
                    .position(position(point.x, point.y, width: width, height: height))
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .frame(width: scaled(4.2, in: width), height: scaled(12, in: width))
                .position(position(3.8, 28, width: width, height: height))

            // 按键灰底：略收一点尺寸，使它显著低于灯条选中态阴影的影响范围（≥ 5 个基线单位）
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.035))
                .frame(width: scaled(67, in: width), height: scaled(21, in: width))
                .position(position(43.8, 38.5, width: width, height: height))

            ledBarButton(width: width, height: height)
            oledButton(width: width, height: height)
            keyButton(for: .voice, width: width, height: height)
            keyButton(for: .approve, width: width, height: height)
            keyButton(for: .reject, width: width, height: height)
            keyButton(for: .submit, width: width, height: height)
            modeSwitchKey(width: width, height: height)
            switchButton(width: width, height: height)
        }
    }

    // 固件 ws2812_mode_e (psk_ws2812.h) → Swift 灯效样式
    private func lightModeToEffect(_ mode: Int) -> LightEffectStyle {
        switch mode {
        case 1: return .singleMove
        case 2: return .rainbowMove
        case 3: return .rainbowWave
        case 4: return .rainbowWaveSlow
        case 5: return .breathing
        case 6: return .middleLight
        default: return .off
        }
    }

    private static let firmwareRed = Color(red: 240 / 255, green: 32 / 255, blue: 41 / 255)
    private static let firmwareBlue = Color(red: 32 / 255, green: 80 / 255, blue: 255 / 255)

    private func firmwareLEDState(ideState: IDEState?, modeData: Int, switchState: Int) -> (LightEffectStyle, Color) {
        guard let s = ideState else {
            return (.off, Self.firmwareRed)
        }
        let effect = modeDraft.lightBar.effect(for: s)
        let color: Color = s == .preToolUse && switchState != 0 ? Self.firmwareBlue : Self.firmwareRed
        return (effect, color)
    }

    private func ledBarButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.lightBar
        let layout = KeyboardCanvasLayout.standard
        // 顶边与 OLED 屏幕顶边对齐（layout.lightBarY == layout.oledY）
        let rect = frame(
            layout.lightBarX1,
            layout.lightBarY,
            layout.lightBarWX1,
            8.6,
            width: width,
            height: height
        )
        let modeData = modeDraft.mode.rawValue
        let effect: LightEffectStyle
        let baseColor: Color
        if let live = liveLightMode {
            // BLE 连接且 mode tab 与物理 workMode 一致：直接信任固件回报的 ws2812_mode + claude_state
            effect = lightModeToEffect(live)
            let liveIDE: IDEState? = liveIDEStateValue.flatMap { IDEState(rawValue: UInt8($0)) }
            // 颜色：仅 preToolUse + manual 是蓝，其他均红（与固件 ws2812_single_color 设定一致）
            if let s = liveIDE, s == .preToolUse, switchState != 0 {
                baseColor = Self.firmwareBlue
            } else {
                baseColor = Self.firmwareRed
            }
        } else {
            // 离线/查看非物理档位：按固件逻辑模拟 update_claude_ws2812()
            let previewIDE = lightBarPreview
            (effect, baseColor) = firmwareLEDState(ideState: previewIDE, modeData: modeData, switchState: switchState)
        }
        return Button {
            onSelect(part)
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let colors = ledColors(effect: effect, time: context.date.timeIntervalSince1970, count: 10, baseColor: baseColor)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                    HStack(spacing: rect.width * 0.026) {
                        ForEach(0..<10, id: \.self) { index in
                            Capsule()
                                .fill(colors[index])
                                .frame(width: rect.width * 0.072, height: rect.height * 0.42)
                                .shadow(color: colors[index].opacity(0.65), radius: 2.5)
                        }
                    }
                    .padding(.horizontal, rect.width * 0.04)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func oledButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.oledDisplay
        let layout = KeyboardCanvasLayout.standard
        let rect = frame(layout.oledX, layout.oledY, layout.oledW, 13.4, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                    oledInnerContent(rect: rect)
                }
                // 右上角徽章：反映键盘 flash 真实状态
                pictureStateBadge(rect: rect)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func pictureStateBadge(rect: CGRect) -> some View {
        if let count = keyboardPictureFrameCount {
            let isUploaded = count > 0
            let label = isUploaded ? "✓ 已上传 \(count) 帧" : "未上传"
            Text(label)
                .font(.system(size: max(rect.height * 0.11, 8), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, rect.width * 0.04)
                .padding(.vertical, rect.height * 0.02)
                .background(
                    Capsule()
                        .fill(isUploaded ? Color.green.opacity(0.85) : Color.gray.opacity(0.85))
                )
                .padding(rect.width * 0.025)
        }
    }

    /// 真实 LCD 是 160×80（2:1）。在 slot 中央用一个 2:1 的"屏幕区"渲染内容，
    /// 周围留键盘黑壳作为外框；图片 / 占位都在屏幕区内 .fit，不会撑出范围、不会被裁切。
    private func screenInnerSize(for rect: CGRect) -> CGSize {
        let screenAspect: CGFloat = 2.0
        if rect.width / rect.height >= screenAspect {
            let h = rect.height * 0.86
            return CGSize(width: h * screenAspect, height: h)
        } else {
            let w = rect.width * 0.86
            return CGSize(width: w, height: w / screenAspect)
        }
    }

    private func oledInnerContent(rect: CGRect) -> some View {
        let size = screenInnerSize(for: rect)
        return ZStack {
            Color.clear
            screenBody(screenWidth: size.width, screenHeight: size.height)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func screenBody(screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        if let gifPath = modeDraft.oled.localAssetPath {
            // .id(gifPath) 强制 SwiftUI 在路径切换时销毁并重建视图，
            // 否则旧路径的 @State frames/currentFrame/timer 会与新路径错位，
            // 导致 Mode 切换瞬间画布渲染上一档 GIF 的某一帧（claude / cursor 互窜）。
            AnimatedGIFView(path: gifPath, fps: modeDraft.oled.framesPerSecond)
                .id(gifPath)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.black.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(alignment: .center, spacing: 2) {
                    if modeDraft.mode == .mode0 {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: screenHeight * 0.24, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.92))
                            Text(modeDraft.mode.title)
                                .font(.system(size: screenHeight * 0.20, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Text("默认动图")
                            .font(.system(size: screenHeight * 0.18))
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: {
                                if #available(macOS 13, *) { "sparkles.rectangle.stack" } else { "rectangle.stack" }
                            }())
                                .font(.system(size: screenHeight * 0.22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                            Text("未上传")
                                .font(.system(size: screenHeight * 0.20, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Text("等待自定义")
                            .font(.system(size: screenHeight * 0.18))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(screenWidth * 0.04)
                .multilineTextAlignment(.center)
            }
        }
    }

    private func keyButton(for role: AhaKeyKeyRole, width: CGFloat, height: CGFloat) -> some View {
        let part = role.part
        let keyDraft = modeDraft.key(for: role)
        let specs: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
        switch role {
        case .voice:
            specs = (10.2, 29.2, 16.2, 16.8)
        case .approve:
            specs = (27.2, 29.2, 16.2, 16.8)
        case .reject:
            specs = (44.2, 29.2, 16.2, 16.8)
        case .submit:
            specs = (61.2, 29.2, 16.2, 16.8)
        }
        let rect = frame(specs.x, specs.y, specs.w, specs.h, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.07) {
                ZStack {
                    RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.95, green: 0.96, blue: 0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    keyIcon(for: role, size: rect.height * 0.28)
                        .fixedSize()
                }
                .frame(width: rect.width * 0.8, height: rect.height * 0.76)

                Text(keyDraft.description.isEmpty ? keyDraft.displaySummary : keyDraft.description)
                    .font(.system(size: rect.height * 0.11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func keyIcon(for role: AhaKeyKeyRole, size: CGFloat) -> some View {
        CanvasKeyRoleIcon(role: role, size: size)
    }

    private func modeSwitchKey(width: CGFloat, height: CGFloat) -> some View {
        let rect = frame(78.9, 40.9, 8.0, 10.2, width: width, height: height)
        return Button {
            onModeSwitch()
        } label: {
            VStack(spacing: rect.height * 0.08) {
                ZStack {
                    RoundedRectangle(cornerRadius: rect.width * 0.2, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: rect.width * 0.2, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: rect.height * 0.18, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.72))
                }
                .frame(width: rect.width * 0.78, height: rect.height * 0.5)

                Text("Mode")
                    .font(.system(size: rect.height * 0.1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
        .help("点击切换 Mode（模拟实体键）")
    }

    private func switchButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.toggleSwitch
        let rect = frame(87.8, 35.6, 6.8, 10.6, width: width, height: height)
        return Button {
            onSelect(part)
            // 物理拨杆损坏的用户靠这个：点击即翻转 auto/manual。
            // 最新固件 0x91 用于灯效预览，因此这里只改 hook 软件覆盖。
            onSwitchToggle?()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    Capsule()
                        .fill(Color.white)
                        .frame(width: rect.width * 0.36, height: rect.height * 0.65)
                        .overlay(Circle().fill(Color.gray.opacity(0.24)).frame(width: rect.width * 0.28, height: rect.width * 0.28))
                        .offset(y: switchTitle == "自动批准" ? -rect.height * 0.08 : rect.height * 0.12)
                }
                .frame(width: rect.width * 0.58, height: rect.height * 0.78)

                Text(switchTitle)
                    .font(.system(size: rect.height * 0.12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: x / baseWidth * width,
            y: y / baseHeight * height,
            width: w / baseWidth * width,
            height: h / baseHeight * height
        )
    }

    private func position(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: x / baseWidth * width, y: y / baseHeight * height)
    }

    private func scaled(_ value: CGFloat, in width: CGFloat) -> CGFloat {
        value / baseWidth * width
    }

    private func ledColors(effect: LightEffectStyle, time: TimeInterval, count: Int,
                           baseColor: Color = Self.firmwareRed) -> [Color] {
        switch effect {
        case .off:
            return Array(repeating: Color.gray.opacity(0.15), count: count)
        case .middleLight:
            let center = Double(count - 1) / 2.0
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let pulse = (sin(time * 1.5) + 1.0) / 2.0 * 0.15
                return baseColor.opacity(0.2 + (1.0 - dist) * 0.65 + pulse)
            }
        case .singleMove:
            let period = 2.4
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = max(0.0, 1.0 - dist * 0.75)
                return baseColor.opacity(0.12 + brightness * 0.82)
            }
        case .breathing:
            let breath = (sin(time * Double.pi * 0.9) + 1.0) / 2.0
            return Array(repeating: baseColor.opacity(0.12 + breath * 0.78), count: count)
        case .rainbowMove:
            let period = 2.4
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = max(0.0, 1.0 - dist * 0.7)
                let hue = (Double(i) / Double(count) + time * 0.25).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.15 + brightness * 0.85)
            }
        case .rainbowWave:
            return (0..<count).map { i in
                let hue = (Double(i) / Double(count) + time * 0.4).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.9)
            }
        case .rainbowWaveSlow:
            return (0..<count).map { i in
                let hue = (Double(i) / Double(count) + time * 0.14).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.9)
            }
        case .typingRipple:
            let center = Double(count - 1) / 2.0
            let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
            let rippleRadius = phase * center * 1.8
            return (0..<count).map { i in
                let dist = abs(Double(i) - center)
                let wave = max(0, 1.0 - abs(dist - rippleRadius) * 0.8)
                return baseColor.opacity(0.1 + wave * 0.85)
            }
        case .comet:
            let period = 1.8
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t * Double(count + 3) - 1.5
            return (0..<count).map { i in
                let dist = Double(i) - pos
                let tail = dist >= 0 ? 0.0 : max(0, 1.0 + dist * 0.25)
                let head = dist >= 0 && dist < 1.5 ? max(0, 1.0 - dist * 0.65) : 0.0
                return baseColor.opacity(0.08 + max(tail, head) * 0.88)
            }
        case .scanBar:
            let period = 2.0
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = dist < 1.5 ? 1.0 - dist * 0.3 : 0.0
                return baseColor.opacity(0.08 + max(0, brightness) * 0.88)
            }
        case .pulseCenter:
            let center = Double(count - 1) / 2.0
            let pulse = (sin(time * Double.pi * 2.5) + 1.0) / 2.0
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let intensity = pulse * max(0, 1.0 - dist * 0.8)
                return baseColor.opacity(0.08 + intensity * 0.88)
            }
        case .warningBlink:
            let blink = sin(time * Double.pi * 4.0) > 0 ? 0.9 : 0.1
            let orange = Color(red: 1.0, green: 0.6, blue: 0.0)
            return Array(repeating: orange.opacity(blink), count: count)
        case .successSweep:
            let green = Color(red: 0.1, green: 0.85, blue: 0.3)
            let progress = time.truncatingRemainder(dividingBy: 2.0) / 2.0
            let fillPos = progress * Double(count + 2) - 1
            return (0..<count).map { i in
                let lit = Double(i) <= fillPos ? 1.0 : 0.0
                return green.opacity(0.08 + lit * 0.88)
            }
        case .blueThinking:
            let blue = Color(red: 0.2, green: 0.5, blue: 1.0)
            return (0..<count).map { i in
                let wave = (sin(time * Double.pi * 0.8 + Double(i) * 0.6) + 1.0) / 2.0
                return blue.opacity(0.15 + wave * 0.75)
            }
        case .lowBattery:
            let red = Color(red: 1.0, green: 0.15, blue: 0.1)
            let pulse = (sin(time * Double.pi * 0.5) + 1.0) / 2.0
            return Array(repeating: red.opacity(0.1 + pulse * 0.6), count: count)
        case .chargingFlow:
            let green = Color(red: 0.1, green: 0.85, blue: 0.3)
            let period = 3.0
            let progress = time.truncatingRemainder(dividingBy: period) / period
            let fillPos = progress * Double(count)
            return (0..<count).map { i in
                let lit = Double(i) < fillPos ? 0.85 : 0.08
                return green.opacity(lit)
            }
        case .approvalWait:
            let amber = Color(red: 1.0, green: 0.75, blue: 0.2)
            let center = Double(count - 1) / 2.0
            let breath = (sin(time * Double.pi * 1.2) + 1.0) / 2.0
            let centerBlink = sin(time * Double.pi * 3.0) > 0 ? 1.0 : 0.4
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let isCenter = dist < 0.2
                let intensity = isCenter ? centerBlink : breath * (1.0 - dist * 0.5)
                return amber.opacity(0.1 + intensity * 0.8)
            }
        }
    }

    private func openNativeSpeechPrivacySettings() {
        openNativeSpeechPrivacySettingsURL()
    }
}

private struct AnimatedGIFView: View {
    let path: String
    let fps: Int

    @State private var frames: [NSImage] = []
    @State private var currentFrame = 0
    @State private var gifTimer: Timer? = nil

    var body: some View {
        Group {
            if !frames.isEmpty, currentFrame >= 0, currentFrame < frames.count {
                Image(nsImage: frames[currentFrame])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { loadFrames() }
        .onDisappear {
            gifTimer?.invalidate()
            gifTimer = nil
        }
    }

    private func loadFrames() {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return }
        var images: [NSImage] = []
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            images.append(NSImage(cgImage: cgImage, size: .zero))
        }
        frames = images
        currentFrame = 0
        guard count > 1 else { return }
        let interval = 1.0 / Double(max(fps, 1))
        gifTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            currentFrame = (currentFrame + 1) % max(1, frames.count)
        }
    }
}

private func openNativeSpeechPrivacySettingsURL() {
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.Siri-Settings.extension",
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.security?Privacy"
    ]

    openFirstAvailableSystemSettingsURL(candidates)
}

/// 输入监控 / 辅助功能 / 麦克风和语音转写：系统在「已拒绝」或部分版本下不会再弹权限窗。主动申请后打开「隐私与安全性」相关页，保证有可操作反馈。
@MainActor
private func openCombinedVoicePrivacySettingsURL() {
    // 勿用未文档化的 `x-apple.systemsettings` + `.extension` 等组合；在部分系统上会被当成「文稿」，
    // 连续弹出「在 App Store 搜索… / 选取应用程序」而非进入设置。
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.Siri-Settings.extension",
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
    ]
    if openFirstAvailableSystemSettingsURL(candidates) { return }
    let appPaths = [
        "/System/Applications/System Settings.app",
        "/System/Library/CoreServices/Applications/System Settings.app",
        "/System/Applications/System Preferences.app",
    ]
    for path in appPaths where FileManager.default.fileExists(atPath: path) {
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            return
        }
    }
}

@discardableResult
private func openFirstAvailableSystemSettingsURL(_ candidates: [String]) -> Bool {
    for candidate in candidates {
        guard let url = URL(string: candidate) else { continue }
        if NSWorkspace.shared.open(url) {
            return true
        }
    }
    return false
}

@MainActor
private func openFirstMissingVoicePermissionSettings(
    bleManager: AhaKeyBLEManager,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService
) {
    if !bleManager.bluetoothPermissionGranted || !bleManager.bluetoothPoweredOn {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"]) { return }
    }
    if !nativeSpeech.microphoneGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"]) { return }
    }
    if !nativeSpeech.speechRecognitionGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"]) { return }
    }
    if !nativeSpeech.siriEnabled {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.Siri-Settings.extension"]) { return }
    }
    if !nativeSpeech.dictationEnabled {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]) { return }
    }
    if !voiceRelay.accessibilityGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]) { return }
    }
    if !voiceRelay.inputMonitoringGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]) { return }
    }
    openCombinedVoicePrivacySettingsURL()
}

/// 先走系统 API 申请；随后在桌面端打开「隐私与安全性」相关页。输入监控 / 辅助功能在多数 macOS 版本上**不会**像 iOS 那样弹窗，麦克风和语音在「已选择过」后也不再弹窗，因此必须配合系统设置界面。
@MainActor
private func requestPermissionsThenOpenPrivacySettingsIfNeeded(
    bleManager: AhaKeyBLEManager,
    voiceRelay: VoiceRelayService,
    nativeSpeech: NativeSpeechTranscriptionService,
    delay: TimeInterval = 0.45
) {
    bleManager.refreshBluetoothAuthorization()
    voiceRelay.refreshPermissions(requestIfNeeded: true)
    nativeSpeech.refreshPermissions(requestIfNeeded: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        bleManager.refreshBluetoothAuthorization()
        openFirstMissingVoicePermissionSettings(bleManager: bleManager, voiceRelay: voiceRelay, nativeSpeech: nativeSpeech)
    }
}

/// 先启动一个延迟重开助手，再退出当前进程。不要在旧进程仍存活时 `open -n`：
/// AppDelegate 有单实例保护，新实例会发现旧实例还在并立即退出，造成"新程序闪退、旧程序不关"。
private func relaunchApplicationForPermissionRefresh() {
    let bundlePath = Bundle.main.bundleURL.path
    let script = "sleep 0.8; /usr/bin/open \(shellQuoted(bundlePath))"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    do {
        try process.run()
    } catch {
        // 即使自动重开助手启动失败，也要让当前进程正常退出；用户可手动再打开。
    }

    NSApp.windows.forEach { $0.close() }
    NSApp.terminate(nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        if NSApp.isRunning {
            exit(0)
        }
    }
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

@MainActor
private func activateAhaKeyWindowForTextInput() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.keyWindow?.makeKeyAndOrderFront(nil)
    NSApp.mainWindow?.makeKeyAndOrderFront(nil)
}

/// 在系统「隐私与安全性」中改完权限后，用确认框引导用户：退出后由 `open -n` 自动拉起同一份 .app。
private struct RestartToApplyPermissionsButton: View {
    var title: String = "退出并重新打开…"
    @State private var showConfirm = false

    var body: some View {
        Button(title) { showConfirm = true }
            .buttonStyle(.bordered)
            .help("在系统设置中修改权限后，需重启本应用，检测才会与系统一致。")
            .alert("需要重启以刷新权限", isPresented: $showConfirm) {
                Button("取消", role: .cancel) {}
                Button("立即重启") { relaunchApplicationForPermissionRefresh() }
            } message: {
                Text("将先退出本应用，再自动重新打开。重新打开后「重新检查权限」会读取最新系统状态。")
            }
    }
}

private struct DeviceInfoSheetContainer: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        VStack(spacing: 0) {
            deviceInfoTitleChrome
            sheetScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            activateAhaKeyWindowForTextInput()
        }
    }

    @ViewBuilder
    private var sheetScrollView: some View {
        if #available(macOS 13.0, *) {
            ScrollView {
                sheetFormContent
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                sheetFormContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var sheetFormContent: some View {
        DeviceInfoView(bleManager: bleManager)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var deviceInfoTitleChrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("设备信息 · Agent")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider()
        }
        .layoutPriority(1)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 48)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CloudAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("用户中心")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            Divider()

            ScrollView {
                AhaKeyUserCenterContent()
                    .padding(18)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HotspotChrome: ViewModifier {
    let part: AhaKeyStudioPart
    let selectedPart: AhaKeyStudioPart
    let dirtyParts: Set<AhaKeyStudioPart>

    func body(content: Content) -> some View {
        let isSelected = selectedPart == part
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // 非选中时几乎隐形，避免每个 hotspot 都画一圈灰线和邻近元件视觉打架
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.black.opacity(0.015),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if dirtyParts.contains(part) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            // 选中态阴影从 10 收到 6，减少向邻近元件溢出的发光半径
            .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 6)
    }
}

private struct OLEDMotionPreviewSheet: View {
    let modeTitle: String
    let assetPath: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(modeTitle) 动图预览")
                        .font(.system(size: 20, weight: .semibold))
                    Text("这里展示的是你刚选中的 GIF 动图文件。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.92))

                if let assetPath {
                    DraggableAnimatedGIFPreview(path: assetPath)
                        .padding(12)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: {
                            if #available(macOS 14, *) { "film.stack" } else { "film" }
                        }())
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("还没有选择动图")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                        .frame(minWidth: 480, minHeight: 240)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 460)
            .clipped()
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 380)
    }
}

/// 支持鼠标按住拖拽（上下左右）查看大图，避免仅靠滚轮导致横向浏览困难。
private struct DraggableAnimatedGIFPreview: View {
    let path: String
    @State private var imageSize = CGSize(width: 480, height: 240)
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            AnimatedGIFPreview(path: path)
                .frame(width: imageSize.width, height: imageSize.height)
                .position(
                    x: viewportSize.width / 2 + offset.width,
                    y: viewportSize.height / 2 + offset.height
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let proposed = CGSize(
                                width: dragStartOffset.width + value.translation.width,
                                height: dragStartOffset.height + value.translation.height
                            )
                            offset = clampOffset(proposed, imageSize: imageSize, viewportSize: viewportSize)
                        }
                        .onEnded { _ in
                            dragStartOffset = offset
                        }
                )
                .onAppear {
                    reloadImageSizeAndResetOffset()
                }
                .onChange(of: path) { _ in
                    reloadImageSizeAndResetOffset()
                }
        }
    }

    private func reloadImageSizeAndResetOffset() {
        if let image = NSImage(contentsOfFile: path), image.size.width > 0, image.size.height > 0 {
            imageSize = image.size
        } else {
            imageSize = CGSize(width: 480, height: 240)
        }
        offset = .zero
        dragStartOffset = .zero
    }

    private func clampOffset(_ proposed: CGSize, imageSize: CGSize, viewportSize: CGSize) -> CGSize {
        let maxX = max(0, (imageSize.width - viewportSize.width) / 2)
        let maxY = max(0, (imageSize.height - viewportSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

private struct AnimatedGIFPreview: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.imageAlignment = .alignCenter
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOfFile: path)
    }
}

// MARK: - 帮助中心（内嵌弹窗）

private enum HelpTopic: String, CaseIterable, Identifiable {
    case overview = "总览"
    case modes = "四个 Mode"
    case canvas = "画布与按键"
    case toggleSwitch = "虚拟拨杆"
    case oled = "LCD 屏幕"
    case lightBar = "灯条颜色"
    case voice = "语音输入"
    case diagnostics = "权限诊断"
    case faq = "常见问题"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .overview: return "sparkles"
        case .modes: return "square.grid.3x1.below.line.grid.1x2"
        case .canvas: return "keyboard"
        case .toggleSwitch: return "switch.2"
        case .oled: return "play.tv"
        case .lightBar: return "rainbow"
        case .voice: return "mic.circle"
        case .diagnostics: return "stethoscope"
        case .faq: return "questionmark.bubble"
        }
    }
}

private struct HelpCenterSheet: View {
    let studioDraft: AhaKeyStudioDraft
    let selectedMode: AhaKeyModeSlot
    @ObservedObject var bleManager: AhaKeyBLEManager
    @Environment(\.dismiss) private var dismiss
    @State private var topic: HelpTopic = .overview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("AhaKey Studio 帮助中心")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.thinMaterial)

            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 188)
                    .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    contentForTopic
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(topic)
            }
        }
        .frame(width: 880, height: 620)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(HelpTopic.allCases) { t in
                Button {
                    topic = t
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.iconName)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(t.rawValue)
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(t == topic ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                    .foregroundStyle(t == topic ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder
    private var contentForTopic: some View {
        switch topic {
        case .overview:      OverviewTopicView()
        case .modes:         ModesTopicView(selectedMode: selectedMode)
        case .canvas:        CanvasTopicView()
        case .toggleSwitch:  ToggleSwitchTopicView(bleManager: bleManager)
        case .oled:          OLEDTopicView(studioDraft: studioDraft, bleManager: bleManager)
        case .lightBar:      LightBarTopicView()
        case .voice:         VoiceTopicView()
        case .diagnostics:   DiagnosticsTopicView()
        case .faq:           FAQTopicView()
        }
    }
}

// MARK: 帮助中心 - 通用排版

private struct HelpTitle: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(title).font(.title2.weight(.semibold))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 12)
    }
}

private struct HelpSection: View {
    let title: String
    let text: String

    init(title: String, body text: String) {
        self.title = title
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
    }
}

private struct HelpNote: View {
    let icon: String
    let tint: Color
    let text: String

    init(_ icon: String, tint: Color = .orange, body text: String) {
        self.icon = icon
        self.tint = tint
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.vertical, 6)
    }
}

private struct HelpSwatch: View {
    let color: Color
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: 帮助中心 - 各章节

private struct OverviewTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "sparkles",
                title: "总览",
                subtitle: "AhaKey Studio 是 AhaKey 小键盘的 macOS 配置中心"
            )

            HelpSection(
                title: "三件套是怎么协同的",
                body: """
                • 主 App（你正在用的）— 看配置、改键位、上传 LCD 动图、查诊断
                • Agent 守护进程 — 后台常驻；监听 IDE 的 Hook（Claude / Cursor / Codex / Kimi），并在 BLE 上向键盘转发当前 AI 状态
                • 键盘固件 — 收到 BLE 状态后驱动灯条颜色、LCD 显示、按键映射
                """
            )

            HelpSection(
                title: "BLE 占用是一道单行道",
                body: """
                同一时刻只有一个进程能持有键盘的 BLE 连接：
                • 默认 Agent 占用 → Hook 状态实时上键盘、自动批准链可用
                • 你在画布点「修改」时 → 主 App 临时接管，能上传 LCD 动图、改键位、读图片元信息
                • 点「返回」 → 主 App 释放，Agent 自动接回
                """
            )

            HelpNote("info.circle.fill", tint: .blue, body: "首次连接，可以先打开「权限诊断」过一遍权限项；任何 Hook 不生效的问题大多在权限里。")
        }
    }
}

private struct ModesTopicView: View {
    let selectedMode: AhaKeyModeSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "square.grid.3x1.below.line.grid.1x2",
                title: "四个 Mode",
                subtitle: "硬件物理键码 + 软件配置同步切换"
            )

            ForEach(AhaKeyModeSlot.allCases) { mode in
                modeCard(mode)
            }

            HelpNote("hand.tap.fill", tint: .accentColor, body: "切换方式：键盘上的 Mode 拨杆，或主 App 顶部 Picker，或点画布上的 Mode 按钮。三处任一改动会同步另外两个。")
        }
    }

    @ViewBuilder
    private func modeCard(_ mode: AhaKeyModeSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(modeChipColor(mode), in: Capsule())
                Text(mode.name).font(.headline)
                if mode == selectedMode {
                    Text("当前").font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Text(mode.subtitle).font(.callout).foregroundStyle(.secondary)
            Text(mode.guidance).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 6)
    }

    private func modeChipColor(_ mode: AhaKeyModeSlot) -> Color {
        switch mode {
        case .mode0: return Color.orange
        case .mode1: return Color.purple
        case .mode2: return Color.green
        case .mode3: return Color.blue
        }
    }
}

private struct CanvasTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "keyboard",
                title: "画布与按键",
                subtitle: "中间那个像键盘的图就是你的小键盘 1:1 镜像，所有元件可点"
            )

            HelpSection(title: "六大热区", body: "灯条、LCD 屏幕、Key1（语音）、Key2、Key3、Key4、拨杆。点哪个就在右侧 Inspector 看到那个元件的配置。")

            VStack(alignment: .leading, spacing: 10) {
                hotspotRow("rainbow", "灯条", "点亮键盘顶端 8 颗 WS2812 LED；颜色和效果跟随 IDE Hook 状态。")
                hotspotRow("play.tv", "LCD 屏幕", "0.96\" IPS 显示；可上传 GIF 动图（160×80, RGB565）。")
                hotspotRow("mic", "Key 1 / 语音键", "macOS 原生语音默认 F18；Typeless / 微信的 Fn 触发使用 F19。")
                hotspotRow("checkmark.circle", "Key 2 / 通过键", "依 Mode 默认：Y / ↵ / ↵。可改成宏序列。")
                hotspotRow("xmark.circle", "Key 3 / 拒绝键", "依 Mode 默认：N / ⌫ / Esc。可改成宏序列。")
                hotspotRow("delete.left", "Key 4 / 删除键", "默认 Backspace，可改任意短按 / 长按。")
                hotspotRow("switch.2", "拨杆", "auto 批准 vs manual 批准；详见「虚拟拨杆」章节。")
            }

            HelpNote("hand.point.up.left", tint: .accentColor, body: """
                点完元件 → Inspector 显示「修改」按钮。点「修改」会接管 BLE 进入编辑态；改完点「写入键盘」写入配置，点「返回」退出编辑。
                """)
        }
    }

    private func hotspotRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct ToggleSwitchTopicView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "switch.2",
                title: "虚拟拨杆",
                subtitle: "物理拨杆坏了？或想软件控制？看这里"
            )

            HelpSection(title: "两档分别管什么", body: """
                • 自动批准（switchState=0）：Hook 拦截每次工具调用 / 命令请求时直接放行
                • 手动批准（switchState=1）：Hook 把决定交回终端，由你手动按 Key2/Key3 通过或拒绝
                """)

            VStack(alignment: .leading, spacing: 8) {
                Text("点画布拨杆触发三件事（不是所有都生效）：").font(.subheadline.weight(.medium))
                triggerRow(
                    num: "1",
                    title: "乐观更新画布",
                    desc: "立即翻转画布拨杆位置 + 顶部状态栏；视觉零延迟",
                    works: true
                )
                triggerRow(
                    num: "2",
                    title: "通知 Agent 设置 userSwitchOverride",
                    desc: "Hook 的 auto-approve 立即切换到你选的档位。持久化到 UserDefaults，agent 重启仍生效",
                    works: true
                )
                triggerRow(
                    num: "3",
                    title: "软件覆盖拨杆",
                    desc: "最新固件 0x91 已用于灯效预览；虚拟拨杆只影响 Hook auto-approve，不再写键盘 sw_state。",
                    works: false,
                    requiresPatch: false
                )
            }

            HelpNote("exclamationmark.triangle.fill", tint: .orange, body: "虚拟拨杆不再占用 0x91，避免与最新固件的灯效预览命令冲突。")

            VStack(alignment: .leading, spacing: 8) {
                Text("现状一览").font(.subheadline.weight(.medium))
                stateRow("当前生效值", "\(bleManager.agentSwitchState ?? bleManager.switchState)")
                stateRow("Agent 端覆盖", bleManager.agentSwitchState != nil ? "\(bleManager.agentSwitchState!)（覆盖中）" : "未设置（用键盘真实值）")
                stateRow("乐观显示中", bleManager.optimisticSwitchOverride != nil ? "是（等待对齐）" : "否")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func triggerRow(num: String, title: String, desc: String, works: Bool, requiresPatch: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(works ? Color.green : Color.orange))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.callout.weight(.medium))
                    if requiresPatch {
                        Text("需固件支持").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                    }
                }
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func stateRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospaced())
        }
    }
}

private struct OLEDTopicView: View {
    let studioDraft: AhaKeyStudioDraft
    @ObservedObject var bleManager: AhaKeyBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "play.tv",
                title: "LCD 屏幕",
                subtitle: "0.96\" IPS · 160×80 · RGB565 · 内置 16 Mbit Flash 存帧"
            )

            HelpSection(title: "默认动图（连接即自动同步）", body: """
                Mode 1 → claude_0.gif（出厂内置）
                Mode 2 → cursor.gif
                Mode 3 → codex.gif
                Mode 4 → 预留/自定义

                首次连接键盘且发现某个 Mode 的 flash slot 为空时，主 App 会自动把对应 bundle GIF 推到键盘上。
                """)

            HelpSection(title: "替换成自己的 GIF", body: """
                1. 画布点 LCD 屏幕 → Inspector 显示「修改」
                2. 点「修改」进入编辑态（接管 BLE）
                3. 选择你的 .gif（推荐 ≤200 帧、≤2MB），可先在虚拟屏幕里预览
                4. 确认后点底部「写入键盘」统一写入设备
                """)

            HelpSection(title: "LCD 角标的含义", body: """
                • 绿色「✓ 已上传 N 帧」：键盘 flash 真有 N 帧（你或自动同步推的）
                • 灰色「未上传」：键盘 flash 空，正显示固件默认或留空
                • 没有徽章：还没自占 BLE 查到（点过一次「修改」就有了）
                """)

            VStack(alignment: .leading, spacing: 6) {
                Text("现在键盘 flash 各 Mode 状态").font(.subheadline.weight(.medium))
                ForEach(AhaKeyModeSlot.allCases) { mode in
                    HStack {
                        Text(mode.title + " · " + mode.name).font(.callout)
                        Spacer()
                        if let s = bleManager.keyboardPictureStates[mode.rawValue] {
                            if s.frameCount > 0 {
                                Label("\(s.frameCount) 帧", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)
                            } else {
                                Label("空", systemImage: "tray").foregroundStyle(.secondary).font(.callout)
                            }
                        } else {
                            Text("尚未查询").font(.callout).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            HelpNote("info.circle.fill", tint: .blue, body: "切换 Mode 时 LCD 会先闪一下当前按键 description 文本（机械感效果），约 1 秒后回到该 Mode 的动图。")
        }
    }
}

private struct LightBarTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "rainbow",
                title: "灯条颜色",
                subtitle: "8 颗 WS2812B，颜色由固件 update_claude_ws2812() 决定，1:1 还原在画布上"
            )

            HelpSection(title: "颜色对照表", body: "下面是 Mode 1（Claude）下，固件按 IDE state 的实际行为：")

            VStack(alignment: .leading, spacing: 8) {
                HelpSwatch(
                    color: Color(red: 240/255, green: 32/255, blue: 41/255),
                    label: "0xF02029 (红)",
                    detail: "SessionStart / Stop / PostToolUse / PermissionRequest / UserPromptSubmit"
                )
                HelpSwatch(
                    color: Color(red: 32/255, green: 80/255, blue: 255/255),
                    label: "0x2050FF (蓝)",
                    detail: "PreToolUse — 工具开始执行（manual 档专属）"
                )
                HelpSwatch(
                    color: Color.gray.opacity(0.3),
                    label: "OFF (熄灭)",
                    detail: "SessionEnd — Claude 会话结束"
                )
            }

            HelpSection(title: "Auto 档的彩虹覆盖", body: """
                当拨杆 = auto (switchState=0) 时，固件把部分 state 强制改成彩虹效果：
                • PreToolUse / PermissionRequest → 整条彩虹波浪
                • PostToolUse / UserPromptSubmit → 单点彩虹流水
                这就是你看到「Cursor 一跑灯条变彩虹」的原因——是 auto 档的视觉提示，不是 Cursor 专属。
                """)

            HelpNote("exclamationmark.triangle.fill", tint: .orange, body: "Mode 1 / Mode 2 时，固件的 update_claude_ws2812() 直接 return，**灯条不再随 IDE state 变**，会停在上一次设定的颜色上。这是固件设计，不是 bug。")
        }
    }
}

private struct VoiceTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "mic.circle",
                title: "语音输入",
                subtitle: "macOS 原生语音走 F18；Fn / Globe 触发走 F19"
            )

            HelpSection(title: "几种预设的差别", body: """
                • macOS 原生转写：在地化语言识别，识别完 ⌘V 写回光标。适合任何输入框
                • Fn/Globe：用于 Typeless、微信语音、豆包输入法，在对应软件内把快捷键设为 Fn/Globe
                • 自定义快捷键：只写入键盘，不接管为固定语音预设
                • AhaType：先识别再优化提示词（需登录）
                """)

            HelpSection(title: "短按 vs 长按", body: """
                • 短按（Toggle）：第一次按开始，第二次按结束 — 适合长段话
                • 长按（Hold-to-speak）：按住时录音，松开停 — 适合微信、豆包等需要"按住"的输入法

                两种模式在 Key 1 Inspector 的「触发方式」Tab 里切换。
                """)

            HelpNote("hand.raised.fill", tint: .red, body: "麦克风 + 输入监控 + 辅助功能三个权限都得给。打开「权限诊断」可以一键跳到系统设置对应页。")
        }
    }
}

private struct DiagnosticsTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "stethoscope",
                title: "权限诊断",
                subtitle: "点底栏的「权限诊断」按钮打开（不是这里的页面）"
            )

            HelpSection(title: "权限清单", body: """
                • 蓝牙：连接键盘必须
                • 麦克风：苹果原生转写、AhaType、按住说话所有语音功能都需要
                • 输入监控：捕获语音键的按下/松开事件
                • 辅助功能：模拟键盘按键（用于 ⌘V 写回文本、注入 Fn/Globe 等）
                • 语音识别：苹果原生转写
                • Siri 与听写（macOS 13+）：原生转写依赖项
                """)

            HelpSection(title: "Agent 健康检查", body: """
                打开「权限诊断」可以看到 Agent 自检结果：
                • LaunchAgent 已注册：login item 装好
                • 进程在跑：launchd 拉起了 ahakeyconfig-agent
                • Hook 已配置：Claude/Cursor/Codex/Kimi 的 .json / settings 都加好了 ahakey-hook 引用
                """)

            HelpSection(title: "转写测试在哪", body: "权限诊断弹窗里。可以不连键盘就验证 macOS 原生转写是否能识别。如果转写失败，多半是麦克风权限或没装语言模型（系统设置 → Siri 与听写 → 听写语言）。")
        }
    }
}

private struct FAQTopicView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle(
                icon: "questionmark.bubble",
                title: "常见问题",
                subtitle: "如果下面没你的问题，可以提 issue 到 GitHub 仓库"
            )

            faq(
                q: "Hook 拦不住，AI 还是会停下来问我",
                a: """
                按这顺序排查：
                1. Agent 在跑吗？打开「权限诊断」看
                2. Agent 是否占着蓝牙？画布顶部应显示已连接，且不在编辑态
                3. 拨杆在 auto 档？看顶部状态栏；不是的话点画布拨杆切到 auto
                4. IDE 的 Hook 文件配了吗？「权限诊断」会列出 Claude/Cursor/Codex/Kimi 各自的 Hook 安装状态
                5. 装完后是否重启过 IDE？尤其 Kimi 安装/升级后必须完全关闭再重开
                """
            )

            faq(
                q: "画布上灯条不变色",
                a: """
                • 检查右上角是否「已连接」
                • 切到正在用的 Mode
                • 触发一次工具调用让 Hook 真的发 0x90 给键盘
                • 如果是手动批准档 + Mode 1：preToolUse 是蓝、其他状态是红
                """
            )

            faq(
                q: "LCD 自动同步没触发",
                a: """
                自动同步只在主 App 自占 BLE 时才查图片元信息。流程：
                1. 至少点一次「修改」让主 App 接管 BLE
                2. 四个 Mode 的 0x83 查询完成后才会触发
                3. 只对 flash 为空（picLength=0）的 Mode 生效
                4. 如果你曾经手动改过 Inspector 里的「上传 GIF」路径，自动同步会跳过那个 Mode（不覆盖你的选择）
                """
            )

            faq(
                q: "拨杆我点了，但键盘灯效没切",
                a: """
                最新固件中 0x91 已用于灯效预览。虚拟拨杆只作为 Hook 软件覆盖，不再写入键盘 sw_state。
                """
            )

            faq(
                q: "OTA 升级有吗？",
                a: """
                规划中，下一版本会做。当前所有固件升级都需要 USB-ISP（拆机短 BOOT + wchisp）。详细方案在仓库 docs 里。
                """
            )
        }
    }

    private func faq(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.tint)
                    .padding(.top, 1)
                Text(q).font(.callout.weight(.medium))
            }
            Text(a)
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(.leading, 26)
                .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.leading, 26).padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}
