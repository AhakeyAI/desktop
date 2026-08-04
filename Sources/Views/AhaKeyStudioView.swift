import AppKit
import CoreImage
import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct AhaKeyStudioView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @StateObject private var ahaType = AhaTypeTextOptimizer.shared
    @StateObject private var cloudAccount = CloudAccountManager.shared
    @StateObject private var agentManager = AgentManager.shared

    @State private var studioDraft: AhaKeyStudioDraft
    @State private var lastSyncedDraft: AhaKeyStudioDraft
    @State private var selectedMode: AhaKeyModeSlot
    @State private var selectedPart: AhaKeyStudioPart
    @State private var lightBarPreview: LightBarPreviewState
    @State private var lastSyncDate: Date?
    @State private var syncStatusMessage = "修改会先保存在本地，连接设备后再同步。"
    @State private var isSyncing = false
    // AhaKeyStudio 交还蓝牙给 Agent 的过渡期：保持"已连接"显示，直到 Agent 接管或超时。
    @State private var isTransitioningToKeyboardControl = false
    @State private var showsOLEDPlaybackPreview = false
    @State private var selectedOLEDGIFSet = 0
    @State private var selectedOLEDTaskState: AhaKeyTaskDisplayState = .sessionEnd
    @State private var showsDeviceInfo = false
    @State private var showsCloudAccount = false
    @State private var showsAhaTypeLoginRequiredToast = false
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var unifiedOnboardingCompleted = false
    @State private var isEditingInspector = false
    @State private var showsDiagnostics = false
    @State private var showsKeyHelp = false
    @State private var selectedTriggerTab: Int = 0
    /// 每次主 App 自占 BLE 连接成功只跑一次默认 OLED 自动同步。
    /// .onChange(of: isConnected) 在断开时重置；下次重连时再触发一次。
    @State private var oledAutoSyncDoneForConnection: Bool = false
    @State private var showsHelpCenter = false
    @State private var showsGuidanceDetail = false

    init(bleManager: AhaKeyBLEManager) {
        self.bleManager = bleManager
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
        _lightBarPreview = State(initialValue: .aiRunning)
    }

    private struct TaskGIFChange {
        let slot: KeyboardTaskPictureSlot
        let asset: AhaKeyTaskGIFAssetDraft
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                canvasPane
                Divider()
                inspectorPane
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 1180, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            agentManager.applyStoredBluetoothPreferenceOnLaunch(bleManager: bleManager)
            voiceRelay.start()
            nativeSpeech.start()
            bleManager.refreshBluetoothAuthorization()
            applyCursorRejectMacroSelfHealIfNeeded()
            voiceRelay.updateRoutes(from: studioDraft)
            SwitchStateNotifier.shared.bind(to: bleManager)
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
        .onChange(of: bleManager.isConnected) { connected in
            if !connected { oledAutoSyncDoneForConnection = false }
        }
        .onChange(of: bleManager.keyboardPictureStates) { _ in
            guard !oledAutoSyncDoneForConnection else { return }
            // 三个 mode 都查回来才动手
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
                showsCloudAccount = true
            }
        } message: {
            Text("请先注册登录 AhaType 后再开启云端整理。")
        }
        .sheet(isPresented: $showsOLEDPlaybackPreview) {
            OLEDMotionPreviewSheet(
                modeTitle: selectedMode.title,
                assetPath: currentOLEDTaskAsset.localAssetPath
            )
        }
        .sheet(isPresented: $showsDeviceInfo) {
            DeviceInfoSheetContainer(bleManager: bleManager)
                .frame(width: 720, height: 720)
        }
        .sheet(isPresented: $showsCloudAccount) {
            CloudAccountView()
                .frame(width: 520, height: 620)
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AhaKey Studio")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
            .layoutPriority(1)

            HStack(spacing: 8) {
                infoPill(
                    title: isEffectivelyConnected ? "已连接" : (bleManager.isScanning ? "扫描中" : "未连接"),
                    subtitle: bleManager.deviceName ?? "等待设备",
                    accent: isEffectivelyConnected ? .green : .orange
                )
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
            .help("清空剪贴板 / 刷新剪贴板")

            Menu {
                Button("恢复当前模式默认值") {
                    restoreCurrentModeDefaults()
                }
                Button("重新连接设备") {
                    bleManager.disconnect()
                    bleManager.userInitiatedConnect()
                }
                Button("设备信息 · Agent…") {
                    showsDeviceInfo = true
                }
                Divider()
                Button("云端账号 · AhaType…") {
                    showsCloudAccount = true
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
        VStack(alignment: .leading, spacing: 18) {
            modeEditorHeader

            VStack(alignment: .leading, spacing: 8) {
                AhaKeyKeyboardCanvasView(
                    modeDraft: currentModeDraft,
                    oledAssetPath: currentOLEDTaskAsset.localAssetPath,
                    oledFramesPerSecond: currentOLEDTaskAsset.framesPerSecond,
                    selectedPart: selectedPart,
                    lightBarPreview: lightBarPreview,
                    switchTitle: currentSwitchTitle,
                    dirtyParts: dirtyPartsForCurrentMode(),
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
                    keyboardPictureFrameCount: bleManager.keyboardPictureStates[selectedMode.rawValue]?.frameCount
                )
                .aspectRatio(109.0 / 54.0, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Text("点按灯条、屏幕、四个按键或拨杆即可进入对应配置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modeEditorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Keyboard Mode")
                    .font(.system(size: 17, weight: .semibold))

                Picker("模式", selection: $selectedMode) {
                    ForEach(AhaKeyModeSlot.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(selectedMode.guidance)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let detail = selectedMode.guidanceHoverDetail {
                    Button {
                        showsGuidanceDetail.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .help(detail)
                    .onHover { showsGuidanceDetail = $0 }
                    .popover(isPresented: $showsGuidanceDetail, arrowEdge: .top) {
                        Text(detail)
                            .font(.callout)
                            .padding(14)
                            .frame(width: 320)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isEditingInspector {
                    // ── Level 2: 全量编辑 ──────────────────────────────────
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingInspector = false
                                returnToKeyboardControl()
                            }
                        } label: {
                            Label("取消编辑", systemImage: "xmark")
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingInspector = false
                                finishEditingConfiguration()
                            }
                        } label: {
                            Label(isSyncing ? "同步中…" : "返回并保存", systemImage: isSyncing ? "arrow.trianglehead.2.clockwise" : "checkmark")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSyncing)
                    }

                    Label(selectedPart.title, systemImage: selectedPart.systemImage)
                        .font(.system(size: 18, weight: .semibold))

                    Group {
                        switch selectedPart {
                        case .key1, .key2, .key3, .key4: keyInspector
                        case .oledDisplay: oledInspector
                        case .lightBar: lightBarInspector
                        case .toggleSwitch: switchInspector
                        }
                    }

                } else {
                    // ── Level 1: 摘要卡片 ──────────────────────────────────
                    inspectorHeader

                    VStack(alignment: .leading, spacing: 0) {
                        partSummaryContent
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
                            )
                    )

                    // macOS HIG：主操作按钮跟随内容尺寸，右下角对齐，标准 control size
                    HStack {
                        Spacer()
                        Button {
                            enterEditingConfiguration()
                            withAnimation(.easeInOut(duration: 0.2)) { isEditingInspector = true }
                        } label: {
                            Label("修改", systemImage: "pencil")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .keyboardShortcut("e", modifiers: .command)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .frame(width: 390)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .onChange(of: selectedPart) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { isEditingInspector = false }
        }
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label(selectedPart.title, systemImage: selectedPart.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                if partIsDirty(selectedPart) {
                    Label("未同步", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if selectedPart.isKey {
                    Button {
                        showsKeyHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .onHover { showsKeyHelp = $0 }
                    .popover(isPresented: $showsKeyHelp, arrowEdge: .leading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("如何使用")
                                .font(.headline)
                            Divider()
                            Text("1. 点击虚拟键盘对应按键选中它。")
                            Text("2. 语音键先选预设；其他键按需选单键或宏。")
                            Text("3. 配置完成后点「返回并保存」同步到键盘。")
                            Text("4. 切模式时 LCD 先显示描述，再回到该模式动图。")
                        }
                        .font(.callout)
                        .padding(16)
                        .frame(width: 270)
                    }
                }
            }
            Text(selectedPart.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
                if let preset = voiceKey.voicePreset, preset == .typeless || preset == .wechat || preset == .doubao {
                    GroupBox("Fn 语音输入法") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Typeless / 微信会注入 Fn 按住/松开；豆包会切到豆包输入源并放行真实 F18。")
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
        case .lightBar:      lightBarSummary
        case .toggleSwitch:  switchSummary
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
        ForEach(LightBarPreviewState.allCases) { state in
            summaryRow(state.title, value: AhaKeyLightBarDraft.hardwareEffect(for: state).title)
        }
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
            GroupBox("按键描述") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("例如 Record / Accept / Reject / Enter", text: selectedKeyDescriptionBinding)
                        .textFieldStyle(.roundedBorder)
                    if currentSelectedKey.description.containsNonASCII {
                        Text("设备 LCD 只稳定支持 ASCII。中文、emoji 和全角字符会在写入时被自动过滤，避免乱码。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("设备实际写入：\(currentSelectedKeySanitizedDescription.isEmpty ? "空白" : currentSelectedKeySanitizedDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("同步到键盘后，短按实体键切换模式时，LCD 会先短暂显示这里的描述，然后回到该模式的动图。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedMode == .mode0 {
                        Text("Mode 0 默认文案：Record / Accept / Reject / Enter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            if key.role == .voice {
                GroupBox("语音输入方式") {
                    VStack(alignment: .leading, spacing: 12) {
                        VoicePresetPicker(
                            selectedPreset: key.voicePreset ?? .custom,
                            onSelect: applyVoicePreset
                        )
                        if (key.voicePreset ?? .custom).isMacOSNativeFamily {
                            Text("只要 AhaKey Studio 在后台运行，Mode 0 出厂语音键发出的 F18 就会被直接接管到苹果原生转写。现在不再依赖系统听写快捷键。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("语音键的输入方式独立于当前 Mode，在任意 Mode 下都可使用相同的语音输入设置。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
            } else {
                GroupBox("按键职责") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(key.role.manualText)
                            .font(.callout)
                        Text("当前会把快捷键和按键描述一起写入键盘。切换模式时，设备会先显示描述，再回到该模式的 LCD 动图。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // ── 触发方式（短按 / 长按 Tab）──────────────────────────────
            GroupBox("触发方式") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $selectedTriggerTab) {
                        Text("短按").tag(0)
                        Text("长按").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Divider()

                    if key.role == .voice {
                        // ── 语音键触发方式 ──────────────────────────────
                        if selectedTriggerTab == 0 {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("按一下开始，再按一下结束", systemImage: "hand.tap.fill")
                                    .font(.callout.weight(.semibold))
                                Text("录音结束后根据下方开关决定是否经 AhaType 整理，再写入光标。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Toggle(isOn: $nativeSpeech.shortPressAhaTypeEnabled) {
                                    HStack(spacing: 6) {
                                        Text("使用 AhaType 整理")
                                            .font(.callout)
                                        if !ahaType.isEnabled {
                                            Text("（AhaType 总开关已关闭）")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.switch)
                                .disabled(!ahaType.isEnabled)

                                Divider()

                                // 绑定摘要（短按 = 语音键 HID 绑定）
                                HStack {
                                    Text(key.displaySummary)
                                        .font(.system(.callout, design: .rounded).weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(key.usesMacro ? "固件宏" : "底层 HID")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Picker("", selection: selectedKeyBindingModeBinding) {
                                    Text("单键 / 组合键").tag(KeyBindingMode.shortcut)
                                    Text("宏").tag(KeyBindingMode.macro)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .disabled((key.voicePreset ?? .custom) != .custom)
                                if key.usesMacro {
                                    macroEditor(for: key)
                                } else {
                                    ShortcutBindingEditor(shortcut: selectedKeyShortcutBinding)
                                }
                                Text(voicePresetDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if (key.voicePreset ?? .custom) != .custom {
                                    Text("语音键预设会固定使用单键绑定；如需录制宏，请先把预设改为自定义快捷键。")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        } else {
                            // 长按 Tab（语音键）— 始终开启，仅配置 AhaType 与阈值
                            VStack(alignment: .leading, spacing: 10) {
                                Label("按住录音，松手即发送", systemImage: "hand.draw.fill")
                                    .font(.callout.weight(.semibold))
                                Text("按住键盘录音键不松手开始录音，松手后直接将 ASR 结果写入，响应更快。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Toggle(isOn: $nativeSpeech.longPressAhaTypeEnabled) {
                                    HStack(spacing: 6) {
                                        Text("使用 AhaType 整理")
                                            .font(.callout)
                                        if !ahaType.isEnabled {
                                            Text("（AhaType 总开关已关闭）")
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
                        }
                    } else {
                        // ── 普通键触发方式 ──────────────────────────────
                        if selectedTriggerTab == 0 {
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
                                    Text("单键 / 组合键").tag(KeyBindingMode.shortcut)
                                    Text("宏").tag(KeyBindingMode.macro)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                if key.usesMacro {
                                    macroEditor(for: key)
                                } else {
                                    ShortcutBindingEditor(shortcut: selectedKeyShortcutBinding)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("需要固件 v2+ 支持", systemImage: "exclamationmark.triangle")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.orange)
                                Text("长按绑定不同快捷键需固件升级后生效，当前仅短按绑定会写入设备。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .onChange(of: selectedPart) { _ in selectedTriggerTab = 0 }

        }
    }

    // MARK: - 宏编辑器视图

    @ViewBuilder
    private func macroEditor(for key: AhaKeyKeyDraft) -> some View {
        let stepCount = key.macro.count
        let byteCount = stepCount * 2
        let overLimit = byteCount > 98 // 固件 payload 上限

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("步骤（依次执行）")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(stepCount) 步 · \(byteCount) / 98 字节")
                    .font(.caption)
                    .foregroundStyle(overLimit ? .red : .secondary)
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
            }

            HStack(spacing: 10) {
                Button {
                    appendMacroStep()
                } label: {
                    Label("添加步骤", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(overLimit)

                Button(role: .destructive) {
                    updateSelectedKey { $0.macro = [] }
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(key.macro.isEmpty)
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
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Picker("", selection: macroStepActionBinding(id: step.id)) {
                ForEach(MacroAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 96)

            if step.action.takesKeycodeParam {
                Picker("", selection: macroStepKeycodeBinding(id: step.id)) {
                    Text("未设置").tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 96)
            } else if step.action.takesDelayParam {
                // 勿对带标题的 Stepper 用 labelsHidden()，否则连「15 ms」一并被藏掉。
                HStack(spacing: 8) {
                    Text("\(max(1, Int(step.param)) * 3) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, alignment: .trailing)
                    Stepper(
                        "",
                        value: macroStepDelayBinding(id: step.id),
                        in: 1...255
                    )
                    .labelsHidden()
                }
                .frame(minWidth: 120)
            } else {
                Color.clear.frame(minWidth: 96, maxHeight: 1)
            }

            Spacer(minLength: 0)

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
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
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
            GroupBox("任务状态动图") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("套图", selection: $selectedOLEDGIFSet) {
                        Text("套图 A").tag(0)
                        Text("套图 B").tag(1)
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(AhaKeyTaskDisplayState.allCases) { state in
                            let isSelected = state == selectedOLEDTaskState
                            let asset = currentModeDraft.oled.taskAsset(set: selectedOLEDGIFSet, state: state)
                            Button {
                                selectedOLEDTaskState = state
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(state.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(asset.localAssetPath == nil ? "未配置" : "已选 GIF")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.9))
                            .frame(height: 140)

                        if let image = currentOLEDPreviewImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "play.tv")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.75))
                                Text("未配置 GIF")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button("选择 GIF") {
                            selectOLEDGIF()
                        }
                        .buttonStyle(.bordered)

                        Button("预览") {
                            showsOLEDPlaybackPreview = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentOLEDTaskAsset.localAssetPath == nil)

                        Button("清空") {
                            clearCurrentOLED()
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)

                        Text("\(selectedOLEDTaskState.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Stepper(value: oledFramesPerSecondBinding, in: 5 ... 20) {
                        Text("播放速度 \(currentOLEDTaskAsset.framesPerSecond) FPS")
                    }

                    Text(currentModeDraft.oled.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("套图切换") {
                VStack(alignment: .leading, spacing: 8) {
                    let deviceSet = bleManager.activeTaskPictureSets[selectedMode.rawValue]
                    HStack {
                        Text(deviceSet == nil ? "设备套图未读取" : "设备当前：套图 \((deviceSet ?? 0) + 1)")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button {
                            Task {
                                do {
                                    let next = ((deviceSet ?? 0) + 1) % 2
                                    _ = try await bleManager.setActiveTaskPictureSet(
                                        mode: UInt8(selectedMode.rawValue),
                                        set: UInt8(next)
                                    )
                                    syncStatusMessage = "已切换 \(selectedMode.title) 到套图 \(next + 1)。"
                                } catch {
                                    syncStatusMessage = "切换设备套图失败：\(error.localizedDescription)"
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .help("切换设备当前 GIF 套图")
                        .disabled(!bleManager.isConnected || isSyncing)
                    }
                    Text("电源键双击同样切换当前 Mode 的套图，并在断电后保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var lightBarReadOnlyInfo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("出厂灯条映射（只读）")
                    .font(.subheadline.weight(.semibold))
                Text("灯条由键盘固件根据 Hook 上报的 IDE 状态点亮，本软件不能改写。下表展示的是各业务场景通常对应的 Hook 状态与出厂灯效。下方画布只预览到虚拟键盘；写入设备统一使用底部操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private var lightBarInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            lightBarReadOnlyInfo

            GroupBox("业务状态 → Hook 状态 → 出厂灯效") {
                VStack(alignment: .leading, spacing: 12) {
                    let cases = Array(LightBarPreviewState.allCases)
                    ForEach(Array(cases.enumerated()), id: \.offset) { index, state in
                        let hw = AhaKeyLightBarDraft.hardwareEffect(for: state)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(state.title)
                                    .font(.callout.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(hw.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                            }
                            Text("Hook 上报：\(state.ideState.label)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(hw.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if index < cases.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("状态预览") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(lightBarPreview.title)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    }

                    Text("当前画布预览：\(currentLightEffect.title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("当前业务状态对应 Hook：\(lightBarPreview.ideState.label)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("预览仅更新左侧虚拟键盘画布；需要写入设备时请使用底部通用写入按钮。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(LightBarPreviewState.allCases) { state in
                            Button {
                                lightBarPreview = state
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(state.title)
                                        .font(.callout.weight(.semibold))
                                    Text(AhaKeyLightBarDraft.hardwareEffect(for: state).title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(state == lightBarPreview ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(state == lightBarPreview ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这里的灯效预览只作用于虚拟键盘。写入设备后，实际灯效由 Hook 状态和键盘固件映射共同决定。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var switchInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("实时档位") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(currentSwitchTitle)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Spacer()
                        Circle()
                            .fill(currentSwitchTitle == "自动批准" ? Color.green : Color.indigo)
                            .frame(width: 10, height: 10)
                    }
                    Text("拨杆是物理档位，不是按下瞬态。0 档显示「自动批准」，1 档显示「手动批准」。这里只读取键盘上报的位置，不模拟物理拨动。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            switchEffectivenessBox

            if bleManager.switchState == 0 {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("自动批准依赖 Agent 与 Hook，且须蓝牙由 Agent 占用", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout.weight(.semibold))
                        Text("Claude：PermissionRequest allow。Cursor：preToolUse 等与 cli-config。Codex：PermissionRequest allow。Kimi：安装过 AhaKey Kimi Hooks 后，**拨杆会直接接管当前会话的自动批准**；若刚装完或刚升级 kimi-cli，请**完全关闭并重新打开一次 kimi**。钩子 stdout 只对 **`permissionDecision: deny`** 有特殊拦截语义。Agent 须在跑且蓝牙由其占用。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("如何理解这个部件") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("拨杆对 Claude / Cursor / Codex / Kimi **同时生效**，与键盘当前所在 Mode 无关。Agent 后台同时监听所有 IDE 的 Hook，拨杆拨动后四个 IDE 的批准行为立即切换。")
                    Divider()
                    Text("自动批准：**Claude / Codex PermissionRequest**，**Cursor preToolUse**（含 cli-config）。**Kimi**：安装过 AhaKey Kimi Hooks 后，拨杆会直接接管**当前会话**的自动批准；刚装完或刚升级 kimi-cli 时，重开一次 kimi 即可。")
                    Text("手动批准：会交回用户/终端确认。若 Cursor、Codex 或 Kimi 仍弹窗，请看 diagnostics 里的 ide 与 diagnostic 字段。")
                    Text("若仍出现手动：在「设备信息」里打开「工具批准诊断」查看 permission-request.log（含 ide、hookEvent、diagnostic 等）。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var switchEffectivenessBox: some View {
        let agentReady = agentManager.isInstalled && agentManager.isRunning && agentManager.hooksInstalled
        let hasAnyMissing = !agentManager.isInstalled || !agentManager.isRunning || !agentManager.hooksInstalled
        GroupBox(agentReady ? "已生效" : "未生效") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: agentReady ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(agentReady ? .green : .orange)
                    Text(agentReady
                         ? "Agent 就绪时 Claude/Cursor/Codex 可随拨杆走批准。**Kimi**：安装过 AhaKey Kimi Hooks 后，拨杆会直接接管当前会话；若刚装完或刚升级 kimi-cli，重开一次 kimi 即可。"
                         : "拨杆在 IDE 中生效需先安装 Agent 与 Hook，并把蓝牙交给 Agent；否则仅为状态显示。")
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
                            // 与「设备信息 · Agent」相同：在 launchd 中 load + start 守护进程。
                            // 若当前由本 App 占用蓝牙，此处也应引导先去设备信息把「蓝牙连接」切给 Agent，否则与主流程二选一相冲突（故与 DeviceInfo 同样禁用直接启动）。
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
                            showsDeviceInfo = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 4)
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
        HStack(spacing: 16) {
            Label("\(selectedPart.title) · \(selectedMode.title)", systemImage: selectedPart.systemImage)
                .font(.callout)
            Divider()
                .frame(height: 14)
            Text("未同步改动 \(dirtyCount)")
                .font(.callout)
            Divider()
                .frame(height: 14)
            Text(syncStatusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let lastSyncDate {
                Text("最近同步 \(Self.timeFormatter.string(from: lastSyncDate))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
                unifiedOnboardingCompleted = false
            }
            .buttonStyle(.borderless)
            .help("重新打开 AhaKey Studio 新手引导")

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
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(chromeBarBackground)
    }

    private var chromeBarBackground: Color {
        Color(nsColor: .controlBackgroundColor)
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
    /// 同时走两条路保证最大兼容性：
    /// - 主 App 已自占 BLE → 直发 0x91（需 patch 固件支持，老固件会被忽略）
    /// - 否则委托 agent socket 设置 override（hook 批准逻辑立刻生效；agent 占 BLE 时
    ///   也会替我们发 0x91 给键盘）。
    private func toggleVirtualSwitch() {
        let current = liveKeyboardSwitchState
        let next: UInt8 = current == 0 ? 1 : 0
        // 1) 立刻设乐观值 → 画布按钮即时翻转
        bleManager.applyOptimisticSwitchOverride(next)
        // 2) 主 App 自占 BLE 时直接发 0x91（需固件已 patch 0x91）
        if bleManager.isConnected {
            bleManager.setSwitchStateViaBLE(next)
        }
        // 3) 让 agent 设置软覆盖 + 替我们走 BLE
        AgentManager.shared.sendSwitchOverride(next)
        // 4) 短延迟后强制重读共享文件，确认真实值已对齐（agent 写文件通常 < 100ms）
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak bleManager] in
            bleManager?.refreshAgentStateFromFileNow()
        }
        syncStatusMessage = next == 0
            ? "虚拟拨杆 → 自动批准（hook 自动放行；灯效若不变需先刷支持 0x91 的固件）"
            : "虚拟拨杆 → 手动批准（hook 交回终端确认）"
    }

    private var currentOLEDTaskAsset: AhaKeyTaskGIFAssetDraft {
        currentModeDraft.oled.taskAsset(set: selectedOLEDGIFSet, state: selectedOLEDTaskState)
    }

    private var currentOLEDPreviewImage: NSImage? {
        guard let path = currentOLEDTaskAsset.localAssetPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var currentOLEDAssetURL: URL? {
        guard let path = currentOLEDTaskAsset.localAssetPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var currentLightEffect: LightEffectStyle {
        AhaKeyLightBarDraft.hardwareEffect(for: lightBarPreview)
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

    private var voicePresetDetail: String {
        let preset = currentSelectedKey.voicePreset ?? .custom
        return preset.detail
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
            get: { currentOLEDTaskAsset.framesPerSecond },
            set: { newValue in
                updateCurrentMode { mode in
                    var asset = mode.oled.taskAsset(set: selectedOLEDGIFSet, state: selectedOLEDTaskState)
                    asset.framesPerSecond = min(20, max(5, newValue))
                    mode.oled.updateTaskAsset(set: selectedOLEDGIFSet, asset: asset)
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
            var asset = mode.oled.taskAsset(set: selectedOLEDGIFSet, state: selectedOLEDTaskState)
            asset.localAssetPath = nil
            mode.oled.updateTaskAsset(set: selectedOLEDGIFSet, asset: asset)
            mode.oled.statusLine = "已清空套图 \(selectedOLEDGIFSet + 1) · \(selectedOLEDTaskState.title)，写入设备后生效。"
        }
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
        case .lightBar, .toggleSwitch:
            return false
        }
    }

    private func dirtyPartsForCurrentMode() -> Set<AhaKeyStudioPart> {
        Set(AhaKeyStudioPart.allCases.filter(partIsDirty(_:)))
    }

    private func selectOLEDGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gif")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OLEDFrameEncoder.validateGIFSourceFileSize(at: url)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "GIF 文件过大。"
                syncStatusMessage = msg
                updateCurrentMode { mode in
                    mode.oled.statusLine = msg
                }
                return
            }
            let frameCount = OLEDFrameEncoder.frameCount(at: url)
            updateCurrentMode { mode in
                var asset = mode.oled.taskAsset(set: selectedOLEDGIFSet, state: selectedOLEDTaskState)
                asset.localAssetPath = url.path
                mode.oled.updateTaskAsset(set: selectedOLEDGIFSet, asset: asset)
                mode.oled.statusLine = "已选 \(max(frameCount, 1)) 帧 GIF：套图 \(selectedOLEDGIFSet + 1) · \(selectedOLEDTaskState.title)。"
            }
            syncStatusMessage = "已更新 \(selectedMode.title) 套图 \(selectedOLEDGIFSet + 1) 的 \(selectedOLEDTaskState.title) 预览；写入设备请使用底部通用按钮。"
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
        syncModesToDevice(
            AhaKeyModeSlot.allCases,
            returnToKeyboardControlWhenDone: returnToKeyboardControlWhenDone
        )
    }

    private func resendCurrentModeToDevice() {
        syncModesToDevice([selectedMode])
    }

    private func syncModesToDevice(
        _ modes: [AhaKeyModeSlot],
        returnToKeyboardControlWhenDone: Bool = false
    ) {
        guard bleManager.isConnected && bleManager.commandCharReady else {
            syncStatusMessage = "设备未连接或命令通道未就绪，当前只保存本地草稿。"
            return
        }

        applyCursorRejectMacroSelfHealIfNeeded()
        let legacyGIFBootstrapModes = modes.filter {
            studioDraft.draft(for: $0).oled.taskGIFSchemaVersion < 1
        }
        let taskChanges = taskGIFChanges(for: modes)
        var commands = commandsForModes(modes)
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存设备配置"))
        let returnAgent = returnToKeyboardControlWhenDone

        isSyncing = true
        let gifWorkCount = taskChanges.count + legacyGIFBootstrapModes.count
        syncStatusMessage = gifWorkCount == 0
            ? "正在写入设备（\(commands.count) 条配置）…"
            : "正在写入设备（\(gifWorkCount) 个任务动图 + \(commands.count) 条配置）…"

        Task {
            do {
                try await bootstrapLegacyGIFsIfNeeded(for: legacyGIFBootstrapModes)
                try await syncTaskGIFChanges(taskChanges)
                bleManager.writeCommandsSequentially(commands) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(250) * 1_000_000)
                        self.markModesSynced(modes)
                        self.lastSyncDate = Date()
                        self.isSyncing = false
                        self.syncStatusMessage = "已写入设备并保存。"
                        if returnAgent {
                            self.returnToKeyboardControl()
                        }
                    }
                }
            } catch {
                isSyncing = false
                syncStatusMessage = "任务动图写入失败：\(error.localizedDescription)"
                if returnAgent {
                    returnToKeyboardControl()
                }
            }
        }
    }

    private func markModesSynced(_ modes: [AhaKeyModeSlot]) {
        var current = studioDraft
        var baseline = lastSyncedDraft
        for mode in modes {
            var modeDraft = current.draft(for: mode)
            modeDraft.oled.taskGIFSchemaVersion = 1
            current.updateMode(modeDraft)
            baseline.updateMode(modeDraft)
        }
        studioDraft = current
        lastSyncedDraft = baseline
    }

    private func bootstrapLegacyGIFsIfNeeded(for modes: [AhaKeyModeSlot]) async throws {
        for mode in modes {
            let oled = studioDraft.draft(for: mode).oled
            guard let assetPath = oled.localAssetPath else { continue }

            let assetURL = URL(fileURLWithPath: assetPath)
            try OLEDFrameEncoder.validateGIFSourceFileSize(at: assetURL)
            let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)
            let startIndex = try await resolveOLEDUploadStartIndex(for: mode, frameCount: frames.count)
            try await bleManager.uploadOLEDFrames(
                frames,
                fps: oled.framesPerSecond,
                mode: UInt8(mode.rawValue),
                startIndex: UInt16(startIndex)
            )
        }
    }

    private func taskGIFChanges(for modes: [AhaKeyModeSlot]) -> [TaskGIFChange] {
        var changes: [TaskGIFChange] = []
        for mode in modes {
            let currentOLED = studioDraft.draft(for: mode).oled
            let baselineOLED = lastSyncedDraft.draft(for: mode).oled
            for set in 0 ..< 2 {
                for state in AhaKeyTaskDisplayState.allCases {
                    let current = currentOLED.taskAsset(set: set, state: state)
                    let baseline = baselineOLED.taskAsset(set: set, state: state)
                    if current != baseline {
                        changes.append(TaskGIFChange(
                            slot: KeyboardTaskPictureSlot(
                                mode: mode.rawValue,
                                set: set,
                                state: state.rawValue
                            ),
                            asset: current
                        ))
                    }
                }
            }
        }
        return changes
    }

    private func syncTaskGIFChanges(_ changes: [TaskGIFChange]) async throws {
        guard !changes.isEmpty else { return }

        var deviceStates = try await bleManager.readAllTaskPictureStates()
        for change in changes {
            let mode = UInt8(change.slot.mode)
            let set = UInt8(change.slot.set)
            let state = UInt8(change.slot.state)

            guard let path = change.asset.localAssetPath else {
                try await bleManager.clearTaskPicture(mode: mode, set: set, state: state)
                if let index = deviceStates.firstIndex(where: {
                    $0.mode == change.slot.mode && $0.set == change.slot.set && $0.state == change.slot.state
                }) {
                    let existing = deviceStates[index]
                    deviceStates[index] = AhaKeyTaskPictureState(
                        mode: existing.mode,
                        set: existing.set,
                        state: existing.state,
                        startIndex: 0,
                        picLength: 0,
                        frameInterval: 0,
                        allModeMaxPic: existing.allModeMaxPic,
                        activeSet: existing.activeSet
                    )
                }
                continue
            }

            let assetURL = URL(fileURLWithPath: path)
            try OLEDFrameEncoder.validateGIFSourceFileSize(at: assetURL)
            let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)
            let startIndex = try resolveTaskOLEDUploadStartIndex(
                for: change.slot,
                frameCount: frames.count,
                states: deviceStates
            )
            try await bleManager.uploadTaskOLEDFrames(
                frames,
                fps: change.asset.framesPerSecond,
                mode: mode,
                set: set,
                state: state,
                startIndex: UInt16(startIndex)
            )

            let interval = max(1, 1000 / max(1, change.asset.framesPerSecond))
            let newState = AhaKeyTaskPictureState(
                mode: change.slot.mode,
                set: change.slot.set,
                state: change.slot.state,
                startIndex: startIndex,
                picLength: frames.count,
                frameInterval: interval,
                allModeMaxPic: deviceStates.first?.allModeMaxPic ?? AhaKeyCommand.oledMaxFrames,
                activeSet: bleManager.activeTaskPictureSets[change.slot.mode] ?? 0
            )
            if let index = deviceStates.firstIndex(where: {
                $0.mode == change.slot.mode && $0.set == change.slot.set && $0.state == change.slot.state
            }) {
                deviceStates[index] = newState
            } else {
                deviceStates.append(newState)
            }
        }
    }

    private func resolveTaskOLEDUploadStartIndex(
        for target: KeyboardTaskPictureSlot,
        frameCount: Int,
        states: [AhaKeyTaskPictureState]
    ) throws -> Int {
        let maxCapacity = states.first?.allModeMaxPic ?? AhaKeyCommand.oledMaxFrames
        guard frameCount <= maxCapacity else {
            throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
        }

        let targetState = states.first {
            $0.mode == target.mode && $0.set == target.set && $0.state == target.state
        }
        let occupiedRegions = mergedPictureRegions(
            states
                .filter {
                    !($0.mode == target.mode && $0.set == target.set && $0.state == target.state)
                        && $0.picLength > 0
                }
                .map { (start: $0.startIndex, end: $0.startIndex + $0.picLength) }
        )

        if let targetState,
           targetState.picLength > 0,
           canPlacePictureRange(
               start: targetState.startIndex,
               count: frameCount,
               occupiedRegions: occupiedRegions,
               maxCapacity: maxCapacity
           )
        {
            return targetState.startIndex
        }

        if let freeStart = findFreePictureSpace(
            occupiedRegions: occupiedRegions,
            neededCount: frameCount,
            maxCapacity: maxCapacity
        ) {
            return freeStart
        }

        throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
    }

    private func mergedPictureRegions(
        _ regions: [(start: Int, end: Int)]
    ) -> [(start: Int, end: Int)] {
        let sorted = regions.sorted { $0.start < $1.start }
        var merged: [(start: Int, end: Int)] = []
        for region in sorted {
            guard region.end > region.start else { continue }
            if let last = merged.last, region.start <= last.end {
                merged[merged.count - 1] = (start: last.start, end: max(last.end, region.end))
            } else {
                merged.append(region)
            }
        }
        return merged
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

        return commands
    }

    /// 首次连接键盘后自动把 bundle 默认 GIF 推到没有上传过的 mode slot。
    /// 触发时机：bleManager.keyboardPictureStates 三个 mode 都查回来之后
    /// （由 .onChange(of: bleManager.keyboardPictureStates) 调度）。
    /// 守卫：
    /// - 只上传 picLength==0（slot 完全空）的 mode；非 0 视为用户已自定义或固件出厂图
    /// - 只在 draft 的 localAssetPath 仍指向 bundle 默认（用户没手动换过）时上传
    /// - 每次连接只跑一次（oledAutoSyncDoneForConnection 标志位由 .onChange(isConnected) 重置）
    private func autoSyncDefaultOLEDsIfNeeded() async {
        guard bleManager.isConnected else { return }
        // 三个 mode 全部 0x83 查询回来才动手，避免半截判断把已上传 slot 当成空
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
        var states: [AhaKeyPictureState] = []
        for mode in AhaKeyModeSlot.allCases {
            states.append(try await bleManager.readPictureState(mode: UInt8(mode.rawValue)))
        }

        let maxCapacity = states.first?.allModeMaxPic ?? AhaKeyCommand.oledMaxFrames
        guard frameCount <= maxCapacity else {
            throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
        }

        let currentState = states.first(where: { $0.mode == targetMode.rawValue })
        let occupiedRegions = states
            .filter { $0.mode != targetMode.rawValue && $0.picLength > 0 }
            .map { (start: $0.startIndex, end: $0.startIndex + $0.picLength) }
            .sorted { $0.start < $1.start }

        if let currentState,
           currentState.picLength > 0,
           canPlacePictureRange(
               start: currentState.startIndex,
               count: frameCount,
               occupiedRegions: occupiedRegions,
               maxCapacity: maxCapacity
           )
        {
            return currentState.startIndex
        }

        if let freeStart = findFreePictureSpace(
            occupiedRegions: occupiedRegions,
            neededCount: frameCount,
            maxCapacity: maxCapacity
        ) {
            return freeStart
        }

        throw OLEDUploadError.noAvailablePictureSlot(needed: frameCount, max: maxCapacity)
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

    private func infoPill(title: String, subtitle: String, accent: Color) -> some View {
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
        .frame(width: 86, alignment: .leading)
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
                permissionRow(title: "输入监控", granted: voiceRelay.inputMonitoringGranted, detail: "允许 AhaKey Studio 在后台监听实体语音键。")
                permissionRow(title: "辅助功能", granted: voiceRelay.accessibilityGranted, detail: "允许 AhaKey Studio 把语音键转换成苹果原生转写或 Fn/Globe。")
                permissionRow(title: "麦克风", granted: nativeSpeech.microphoneGranted, detail: "允许 AhaKey Studio 使用苹果原生语音采集。")
                permissionRow(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted, detail: "允许 AhaKey Studio 使用苹果原生语音识别。")
                permissionRow(title: "Siri", granted: nativeSpeech.siriEnabled, detail: "在「系统设置 > Siri 与聚焦」里开启 Siri，供 macOS 原生语音能力使用。")
                permissionRow(title: "听写", granted: nativeSpeech.dictationEnabled, detail: "在「系统设置 > 键盘 > 听写」里开启听写，保证系统语音组件完整可用。")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("授权步骤")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("1. 点「现在申请权限」，按系统弹窗允许蓝牙、麦克风和语音转写。")
                Text("2. 自动打开系统设置后，按上方橙色项目依次为 AhaKey Studio 打开蓝牙、输入监控、辅助功能。")
                Text("3. 若使用默认 macOS 原生语音，在「Siri 与聚焦」开启 Siri，在「键盘 > 听写」开启听写。")
                Text("4. 回到这里点「我已完成，重新检查」；若输入监控或辅助功能刚开启，建议点「退出并重新打开」。")
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

private struct VoicePresetPicker: View {
    let selectedPreset: VoicePreset
    let onSelect: (VoicePreset) -> Void

    private let visiblePresets = VoicePreset.visibleCases
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(visiblePresets) { preset in
                Button {
                    if preset.availableInV1 {
                        onSelect(preset)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(preset.title)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            if !preset.availableInV1 {
                                Text("开发中")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(preset.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(cardFill(for: preset))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cardStroke(for: preset), lineWidth: preset == selectedPreset ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!preset.availableInV1)
            }
        }
    }

    private func cardFill(for preset: VoicePreset) -> Color {
        if preset == selectedPreset {
            return Color.accentColor.opacity(0.16)
        }
        if !preset.availableInV1 {
            return Color(nsColor: .controlBackgroundColor).opacity(0.65)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func cardStroke(for preset: VoicePreset) -> Color {
        if preset == selectedPreset {
            return .accentColor
        }
        return Color.black.opacity(0.08)
    }
}

private struct ShortcutBindingEditor: View {
    @Binding var shortcut: ShortcutBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ShortcutModifier.allCases) { modifier in
                    Toggle(isOn: modifierBinding(modifier)) {
                        Text(modifier.symbol)
                            .font(.system(.headline, design: .rounded))
                    }
                    .toggleStyle(.button)
                    .help(modifier.title)
                }
                if !shortcut.modifiers.isEmpty {
                    Button("清除修饰键") {
                        var next = shortcut
                        next.modifiers = []
                        shortcut = next
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Picker("主键", selection: primaryKeyBinding) {
                Text("未设置").tag(UInt8(0))
                ForEach(HIDUsage.allOptions, id: \.code) { option in
                    Text(option.name).tag(option.code)
                }
            }
            .pickerStyle(.menu)

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

    private var primaryKeyBinding: Binding<UInt8> {
        Binding(
            get: { shortcut.keyCode },
            set: { newCode in
                var next = shortcut
                next.keyCode = newCode
                shortcut = next
            }
        )
    }
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
    var oledAssetPath: String? = nil
    var oledFramesPerSecond: Int? = nil
    let selectedPart: AhaKeyStudioPart
    let lightBarPreview: LightBarPreviewState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>
    let onSelect: (AhaKeyStudioPart) -> Void
    let onModeSwitch: () -> Void
    var onKeySimulate: ((AhaKeyKeyRole) -> Void)? = nil
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

    /// 1:1 还原固件 update_claude_ws2812() 的灯效/颜色决策（CH582m main.c:458-500）。
    /// 仅 mode_data==0 时固件会按 claude_state 切灯效；其他 mode 固件提前 return，
    /// 灯条停在上一次设定的状态，所以我们这里返回 OFF 作为"没有运行时灯效"的真实表达。
    private func firmwareLEDState(ideState: IDEState?, modeData: Int, switchState: Int) -> (LightEffectStyle, Color) {
        guard modeData == 0, let s = ideState else {
            return (.off, Self.firmwareRed)
        }
        var effect: LightEffectStyle
        var color: Color = Self.firmwareRed
        switch s {
        case .sessionStart, .stop:
            effect = .middleLight
        case .postToolUse, .userPromptSubmit:
            effect = .singleMove
        case .permissionRequest:
            effect = .breathing
        case .preToolUse:
            effect = .singleMove
            color = Self.firmwareBlue
        case .sessionEnd:
            effect = .off
        case .notification, .taskCompleted:
            // 固件 switch 未处理这两个 state，灯条保持上一次状态（这里以 OFF 表示无新效果）
            return (.off, Self.firmwareRed)
        }
        if switchState == 0 { // auto: 固件覆盖部分 state 为彩虹效果
            switch s {
            case .postToolUse, .userPromptSubmit:
                effect = .rainbowMove
            case .permissionRequest, .preToolUse:
                effect = .rainbowWave
            default:
                break
            }
        }
        return (effect, color)
    }

    private func ledBarButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.lightBar
        // 略向上、宽度往里收：让选中态阴影（radius 10pt）跟键盘内描边、按键灰底、OLED 都有 ≥ 5 个基线单位的余量
        let rect = frame(13.0, 4.5, 53.5, 8.6, width: width, height: height)
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
            let previewIDE = lightBarPreview.ideState
            (effect, baseColor) = firmwareLEDState(ideState: previewIDE, modeData: modeData, switchState: switchState)
        }
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.12) {
                Text("灯条")
                    .font(.system(size: max(rect.height * 0.18, 10), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .center)

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let colors = ledColors(effect: effect, time: context.date.timeIntervalSince1970, count: 10, baseColor: baseColor)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.12))
                        HStack(spacing: rect.width * 0.026) {
                            ForEach(0..<10, id: \.self) { index in
                                Capsule()
                                    .fill(colors[index])
                                    .frame(width: rect.width * 0.072, height: rect.height * 0.26)
                                    .shadow(color: colors[index].opacity(0.65), radius: 2.5)
                            }
                        }
                        .padding(.horizontal, rect.width * 0.04)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: rect.height * 0.48)
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
        let rect = frame(71.2, 7.7, 24.2, 13.4, width: width, height: height)
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

    /// 真实 OLED 是 160×80（2:1）。在 slot 中央用一个 2:1 的"屏幕区"渲染内容，
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
        if let gifPath = oledAssetPath ?? modeDraft.oled.localAssetPath {
            // .id(gifPath) 强制 SwiftUI 在路径切换时销毁并重建视图，
            // 否则旧路径的 @State frames/currentFrame/timer 会与新路径错位，
            // 导致 Mode 切换瞬间画布渲染上一档 GIF 的某一帧（claude / cursor 互窜）。
            AnimatedGIFView(path: gifPath, fps: oledFramesPerSecond ?? modeDraft.oled.framesPerSecond)
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
                            Text("Mode 0")
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
            onKeySimulate?(role)
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

                    Image(systemName: role.systemImage)
                        .font(.system(size: rect.height * 0.24, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.88))
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
            // - 已 patch 固件：agent 通过 0x91 BLE 命令真改键盘 sw_state，灯效也会跟着变
            // - 老固件：只在 agent 软覆盖层生效（hook 自动批准走新值），键盘灯效不会变
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
    if !voiceRelay.inputMonitoringGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]) { return }
    }
    if !voiceRelay.accessibilityGranted {
        if openFirstAvailableSystemSettingsURL(["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]) { return }
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

private struct CloudAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var account = CloudAccountManager.shared
    @StateObject private var optimizer = AhaTypeTextOptimizer.shared
    @FocusState private var focusedLoginField: LoginField?

    private enum LoginField {
        case phone
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("云端账号 · AhaType")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if account.isLoggedIn {
                        profileSection
                    } else {
                        loginSection
                    }

                    Divider()

                    ahaTypeSection
                }
                .padding(18)
            }
        }
        .alert("云端账号", isPresented: Binding(
            get: { account.alertMessage != nil },
            set: { if !$0 { account.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { account.alertMessage = nil }
        } message: {
            Text(account.alertMessage ?? "")
        }
        .onAppear {
            activateAhaKeyWindowForTextInput()
            optimizer.refreshFromDisk()
            if account.isLoggedIn {
                account.refreshProfile()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    activateAhaKeyWindowForTextInput()
                    focusedLoginField = .phone
                }
            }
        }
    }

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录后可使用 AhaType 云端大模型整理。")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("手机号", text: $account.phone)
                .textFieldStyle(.roundedBorder)
                .focused($focusedLoginField, equals: .phone)
                .onTapGesture {
                    activateAhaKeyWindowForTextInput()
                    focusedLoginField = .phone
                }
                .onSubmit { focusedLoginField = .password }

            SecureField("密码", text: $account.password)
                .textFieldStyle(.roundedBorder)
                .focused($focusedLoginField, equals: .password)
                .onTapGesture {
                    activateAhaKeyWindowForTextInput()
                    focusedLoginField = .password
                }
                .onSubmit { account.login() }

            Toggle("记住密码", isOn: $account.rememberPassword)

            HStack(spacing: 10) {
                Button("登录") { account.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.isBusy)
                Button("注册") { account.register() }
                    .buttonStyle(.bordered)
                    .disabled(account.isBusy)
            }

            Text(account.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(account.profileSummary)
                .font(.callout)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                quotaRow(title: "每日", value: account.quotaText("daily"))
                quotaRow(title: "每周", value: account.quotaText("weekly"))
                quotaRow(title: "每月", value: account.quotaText("monthly"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            HStack(spacing: 10) {
                Button("刷新") { account.refreshProfile() }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.isBusy)
                Button("切换账号") {
                    account.prepareForRelogin()
                    focusedLoginField = .phone
                }
                .buttonStyle(.bordered)
                .disabled(account.isBusy)
                Button("退出登录") { account.logout() }
                    .buttonStyle(.bordered)
                    .disabled(account.isBusy)
            }

            rechargeSection

            HStack(spacing: 10) {
                TextField("免费券兑换码", text: $account.couponCode)
                    .textFieldStyle(.roundedBorder)
                Button("兑换") { account.redeemCoupon() }
                    .buttonStyle(.bordered)
                    .disabled(account.isBusy)
            }

            Text(account.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rechargeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("充值订阅")
                .font(.callout.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(CloudRechargePlan.allCases) { plan in
                    Button {
                        account.createWechatOrder(plan: plan)
                    } label: {
                        VStack(spacing: 3) {
                            Text(plan.title)
                                .font(.caption.weight(.semibold))
                            Text(account.priceText(for: plan))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(plan.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(account.isBusy)
                }
            }

            if let order = account.paymentOrder {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        if let image = makeQRCodeImage(from: order.paymentURL) {
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 132, height: 132)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(order.plan.title) · \(order.amountText)")
                                .font(.caption.weight(.semibold))
                            Text("微信扫码完成支付，支付成功后会自动刷新额度。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("订单：\(order.outTradeNo)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                            Text("状态：\(order.status)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("复制支付链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(order.paymentURL, forType: .string)
                        }
                        .buttonStyle(.bordered)

                        Button("刷新到账") {
                            account.refreshProfile()
                        }
                        .buttonStyle(.bordered)
                        .disabled(account.isBusy)

                        Button("关闭订单") {
                            account.clearPaymentOrder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    private var ahaTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { optimizer.isEnabled },
                set: { optimizer.setEnabled($0) }
            )) {
                Text("启用 AhaType 云端整理")
                    .font(.callout.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text("开启后，macOS 原生语音转写完成后会先请求云端整理，再粘贴整理后的文本。未登录、过期或网络失败时会自动回退原始转写。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(optimizer.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(optimizer.lastQuotaSummary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func quotaRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func makeQRCodeImage(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
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
    case modes = "三个 Mode"
    case canvas = "画布与按键"
    case toggleSwitch = "虚拟拨杆"
    case oled = "OLED 屏幕"
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
                • 主 App（你正在用的）— 看配置、改键位、上传 OLED、查诊断
                • Agent 守护进程 — 后台常驻；监听 IDE 的 Hook（Claude / Cursor / Codex / Kimi），并在 BLE 上向键盘转发当前 AI 状态
                • 键盘固件 — 收到 BLE 状态后驱动灯条颜色、OLED 显示、按键映射
                """
            )

            HelpSection(
                title: "BLE 占用是一道单行道",
                body: """
                同一时刻只有一个进程能持有键盘的 BLE 连接：
                • 默认 Agent 占用 → Hook 状态实时上键盘、自动批准链可用
                • 你在画布点「修改」时 → 主 App 临时接管，能上传 OLED、改键位、读图片元信息
                • 点「返回并保存」或「取消编辑」 → 主 App 释放，Agent 自动接回
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
                title: "三个 Mode",
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

            HelpSection(title: "六大热区", body: "灯条、OLED 屏幕、Key1（语音）、Key2、Key3、Key4、拨杆。点哪个就在右侧 Inspector 看到那个元件的配置。")

            VStack(alignment: .leading, spacing: 10) {
                hotspotRow("rainbow", "灯条", "点亮键盘顶端 8 颗 WS2812 LED；颜色和效果跟随 IDE Hook 状态。")
                hotspotRow("play.tv", "OLED 屏幕", "0.96\" IPS 显示；可上传 GIF 动图（160×80, RGB565）。")
                hotspotRow("mic", "Key 1 / 语音键", "默认 F18，触发苹果原生转写、AhaType、微信按住说话等预设。")
                hotspotRow("checkmark.circle", "Key 2 / 通过键", "依 Mode 默认：Y / ↵ / ↵。可改成宏序列。")
                hotspotRow("xmark.circle", "Key 3 / 拒绝键", "依 Mode 默认：N / ⌫ / Esc。可改成宏序列。")
                hotspotRow("paperplane", "Key 4 / 提交键", "默认 ↵，可改任意短按 / 长按。")
                hotspotRow("switch.2", "拨杆", "auto 批准 vs manual 批准；详见「虚拟拨杆」章节。")
            }

            HelpNote("hand.point.up.left", tint: .accentColor, body: """
                点完元件 → Inspector 显示「修改」按钮。点「修改」会接管 BLE 进入编辑态；改完点「返回并保存」立即写入键盘，或点「取消编辑」放弃。
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
                    title: "BLE 0x91 set_sw_state",
                    desc: "试图修改键盘真实 sw_state → 灯效颜色逻辑跟着切。**需固件升级支持 0x91**",
                    works: false,
                    requiresPatch: true
                )
            }

            HelpNote("exclamationmark.triangle.fill", tint: .orange, body: """
                如果你**没刷新版固件**：点画布拨杆，Hook 行为会按虚拟值跑（这就够大多数 case），但键盘灯条颜色仍由坏掉的物理 GPIO 决定。要让灯效也跟着切，得给固件 command_solve.c 加 0x91 分支再 USB-ISP 烧一次（详见仓库 README 的固件章节）。
                """)

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
                title: "OLED 屏幕",
                subtitle: "0.96\" IPS · 160×80 · RGB565 · 内置 16 Mbit Flash 存帧"
            )

            HelpSection(title: "默认动图（连接即自动同步）", body: """
                Mode 0 → claude_0.gif（出厂内置）
                Mode 1 → cursor.gif
                Mode 2 → codex.gif

                首次连接键盘且发现某个 Mode 的 flash slot 为空时，主 App 会自动把对应 bundle GIF 推到键盘上。
                """)

            HelpSection(title: "替换成自己的 GIF", body: """
                1. 画布点 OLED 屏幕 → Inspector 显示「修改」
                2. 点「修改」进入编辑态（接管 BLE）
                3. 选择你的 .gif（推荐 ≤200 帧、≤2MB），可先在虚拟屏幕里预览
                4. 确认后点「返回并保存」统一写入设备
                """)

            HelpSection(title: "OLED 角标的含义", body: """
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

            HelpNote("info.circle.fill", tint: .blue, body: "切换 Mode 时 OLED 会先闪一下当前按键 description 文本（机械感效果），约 1 秒后回到该 Mode 的动图。")
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

            HelpSection(title: "颜色对照表", body: "下面是 Mode 0（Claude）下，固件按 IDE state 的实际行为：")

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
                subtitle: "Key 1 默认绑定 F18，按一次开始、按一次结束"
            )

            HelpSection(title: "几种预设的差别", body: """
                • macOS 原生转写：在地化语言识别，识别完 ⌘V 写回光标。适合任何输入框
                • Typeless：调起 Typeless App
                • 微信按住说话：按住语音键发语音，松开停
                • 豆包输入法：按住调起豆包长按语音
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
                • 辅助功能：模拟键盘按键（用于 ⌘V 写回文本、注入 F18 等）
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
                • 切到正在用的 Mode（auto 档下只有 Mode 0 灯效活跃）
                • 触发一次工具调用让 Hook 真的发 0x90 给键盘
                • 如果是手动批准档 + Mode 0：preToolUse 是蓝、其他状态是红
                """
            )

            faq(
                q: "OLED 自动同步没触发",
                a: """
                自动同步只在主 App 自占 BLE 时才查图片元信息。流程：
                1. 至少点一次「修改」让主 App 接管 BLE
                2. 三个 Mode 的 0x83 查询完成后才会触发
                3. 只对 flash 为空（picLength=0）的 Mode 生效
                4. 如果你曾经手动改过 Inspector 里的「上传 GIF」路径，自动同步会跳过那个 Mode（不覆盖你的选择）
                """
            )

            faq(
                q: "拨杆我点了，但键盘灯效没切",
                a: """
                灯效颜色是由键盘固件根据 sw_state GPIO 直接决定的。要让灯效跟着虚拟拨杆走，必须刷新版固件（含 0x91 set_sw_state 命令）。Hook 的批准行为不需要刷固件，软件覆盖即可生效。
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
