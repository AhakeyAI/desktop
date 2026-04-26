import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AhaKeyStudioView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var voiceRelay = VoiceRelayService.shared
    @StateObject private var nativeSpeech = NativeSpeechTranscriptionService.shared
    @StateObject private var agentManager = AgentManager.shared

    @State private var studioDraft: AhaKeyStudioDraft
    @State private var lastSyncedDraft: AhaKeyStudioDraft
    @State private var selectedMode: AhaKeyModeSlot
    @State private var selectedPart: AhaKeyStudioPart
    @State private var lightBarPreview: LightBarPreviewState
    @State private var lastSyncDate: Date?
    @State private var syncStatusMessage = "修改会先保存在本地，连接设备后再同步。"
    @State private var isSyncing = false
    @State private var showsOLEDPlaybackPreview = false
    @State private var showsDeviceInfo = false

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
        .frame(minWidth: 1280, minHeight: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            agentManager.applyStoredBluetoothPreferenceOnLaunch(bleManager: bleManager)
            voiceRelay.start()
            nativeSpeech.start()
            voiceRelay.updateRoutes(from: studioDraft)
            SwitchStateNotifier.shared.bind(to: bleManager)
        }
        .onChange(of: studioDraft) { _, newValue in
            AhaKeyStudioStore.save(newValue)
            voiceRelay.updateRoutes(from: newValue)
        }
        // 键盘物理档位变化（BLE 查询/通知上报）→ 自动切到对应 Mode 标签，
        // 这样 OLED 预览、快捷键草稿、发出去的 updateState 三者一致。
        .onChange(of: bleManager.workMode) { _, newValue in
            if let slot = AhaKeyModeSlot(rawValue: newValue), slot != selectedMode {
                selectedMode = slot
            }
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
        .sheet(isPresented: $showsOLEDPlaybackPreview) {
            OLEDMotionPreviewSheet(
                modeTitle: selectedMode.title,
                assetPath: currentModeDraft.oled.localAssetPath
            )
        }
        .sheet(isPresented: $voiceRelay.showsPermissionOnboarding) {
            VoicePermissionOnboardingSheet(
                voiceRelay: voiceRelay,
                nativeSpeech: nativeSpeech
            )
        }
        .sheet(isPresented: $showsDeviceInfo) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("设备信息 · Agent")
                        .font(.headline)
                    Spacer()
                    Button("关闭") { showsDeviceInfo = false }
                }
                .padding(16)
                Divider()
                DeviceInfoView(bleManager: bleManager)
            }
            .frame(width: 720, height: 720)
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("AhaKey Studio")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }

            HStack(spacing: 10) {
                infoPill(
                    title: bleManager.isConnected ? "已连接" : (bleManager.isScanning ? "扫描中" : "未连接"),
                    subtitle: bleManager.deviceName ?? "等待设备",
                    accent: bleManager.isConnected ? .green : .orange
                )
                infoPill(
                    title: "电量",
                    subtitle: bleManager.isConnected ? "\(bleManager.batteryLevel)%" : "—",
                    accent: .blue
                )
                infoPill(
                    title: "拨杆",
                    subtitle: currentSwitchTitle,
                    accent: currentSwitchTitle == "自动批准" ? .mint : .indigo
                )
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Picker("模式", selection: $selectedMode) {
                    ForEach(AhaKeyModeSlot.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Text(selectedMode.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 280, alignment: .leading)
            }

            if !bleManager.isConnected {
                if agentManager.bluetoothConnectionOwner == .agentDaemon {
                    Text("蓝牙由 Agent 占用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("在「更多 → 设备信息 · Agent」里将「蓝牙连接」切到 AhaKey Studio 后，本 App 才能连接。")
                } else {
                    Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                        bleManager.userInitiatedConnect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(bleManager.isScanning)
                }
            }

            Button(primarySyncButtonTitle) {
                triggerPrimarySyncAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!bleManager.isConnected || isSyncing)

            Menu {
                Button("恢复当前模式默认值") {
                    restoreCurrentModeDefaults()
                }
                Button("重新连接设备") {
                    bleManager.disconnect()
                    bleManager.userInitiatedConnect()
                }
                Button("清空 OLED 预览") {
                    clearCurrentOLED()
                }
                Divider()
                Button("设备信息 · Agent…") {
                    showsDeviceInfo = true
                }
                Divider()
                Button("隐藏到后台") {
                    NSApp.keyWindow?.close()
                }
                Button("退出 AhaKey Studio") {
                    NSApp.terminate(nil)
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var canvasPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(selectedMode.title) · \(selectedMode.subtitle)")
                    .font(.system(size: 17, weight: .semibold))
                Text("点按灯条、屏幕、四个按键或拨杆即可进入对应配置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            AhaKeyKeyboardCanvasView(
                modeDraft: currentModeDraft,
                selectedPart: selectedPart,
                lightBarPreview: lightBarPreview,
                switchTitle: currentSwitchTitle,
                dirtyParts: dirtyPartsForCurrentMode(),
                onSelect: { selectedPart = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                manualCallout(
                    title: "主流程",
                    detail: "短按开机设备 -> 连接蓝牙 vibe code -> 选模式 -> 点部件 -> 修改 -> 同步到键盘"
                )
                manualCallout(
                    title: "模式切换",
                    detail: "短按设备按键切换模式，OLED 会先显示描述约 1 秒，再回到该模式动图"
                )
                manualCallout(
                    title: "当前选中",
                    detail: "\(selectedPart.title) · \(selectedPart.subtitle)"
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorHeader

                switch selectedPart {
                case .key1, .key2, .key3, .key4:
                    keyInspector
                case .oledDisplay:
                    oledInspector
                case .lightBar:
                    lightBarInspector
                case .toggleSwitch:
                    switchInspector
                }
            }
            .padding(24)
        }
        .frame(width: 390)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
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
            }
            Text(selectedPart.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var keyInspector: some View {
        let key = currentSelectedKey
        return VStack(alignment: .leading, spacing: 16) {
            if key.role == .voice {
                GroupBox("语音软件") {
                    VStack(alignment: .leading, spacing: 12) {
                        VoicePresetPicker(
                            selectedPreset: key.voicePreset ?? .custom,
                            onSelect: applyVoicePreset
                        )

                        if (key.voicePreset ?? .custom) == .macOSNative {
                            Text("只要 AhaKey Studio 在后台运行，Mode 0 出厂语音键发出的 F18 就会被直接接管到苹果原生转写。现在不再依赖系统听写快捷键。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
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
                                voiceRelay.refreshPermissions(requestIfNeeded: true)
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

                if (key.voicePreset ?? .custom) == .macOSNative {
                    GroupBox("苹果原生转写") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(nativeSpeech.isRecording ? Color.red : (nativeSpeech.microphoneGranted && nativeSpeech.speechRecognitionGranted ? Color.green : Color.orange))
                                    .frame(width: 10, height: 10)
                                Text(nativeSpeech.isRecording ? "录音转写中" : "等待语音键触发")
                                    .font(.callout.weight(.semibold))
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                permissionBadge(title: "麦克风", granted: nativeSpeech.microphoneGranted)
                                permissionBadge(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted)
                            }

                            Text(nativeSpeech.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(nativeSpeech.lastPermissionCheckSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !nativeSpeech.transcriptPreview.isEmpty {
                                Text("实时识别：\(nativeSpeech.transcriptPreview)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !nativeSpeech.lastCommittedText.isEmpty {
                                Text("最近写入：\(nativeSpeech.lastCommittedText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button(nativeSpeech.isRecording ? "结束并写入" : "开始录音") {
                                    nativeSpeech.toggleRecordingFromVoiceKey()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("重新检查权限") {
                                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                                }
                                .buttonStyle(.bordered)

                                RestartToApplyPermissionsButton()

                                if !nativeSpeech.microphoneGranted || !nativeSpeech.speechRecognitionGranted {
                                    Button("打开系统设置") {
                                        openNativeSpeechPrivacySettings()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox("当前出厂固件直接体验") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 保持 AhaKey Studio 在后台运行。")
                        Text("2. 在系统设置里为 AhaKey Studio 打开“输入监控”“辅助功能”“麦克风”“语音转写”。若已打开仍显示未授权，先完全退出本应用再开一次。")
                        Text("3. 确认设备当前在 Mode 0。")
                        Text("4. 不用同步设备，直接按实体语音键即可开始苹果原生转写；再按一次会结束并把文字写回当前光标。")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
            GroupBox("按键职责") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(key.role.manualText)
                        .font(.callout)
                    Text("当前会把快捷键和按键描述一起写入键盘。切换模式时，设备会先显示描述，再回到该模式的 OLED 动图。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }

            GroupBox("将写入键盘的按键绑定") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(key.displaySummary)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
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
                    .disabled(key.role == .voice && (key.voicePreset ?? .custom) != .custom)

                    if key.usesMacro {
                        macroEditor(for: key)
                    } else {
                        ShortcutBindingEditor(
                            binding: key.shortcut,
                            onModifierToggle: updateShortcutModifier(_:enabled:),
                            onKeyCodeChange: updateShortcutKeyCode(_:)
                        )
                    }

                    if key.role == .voice {
                        Text(voicePresetDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if key.role == .voice && (key.voicePreset ?? .custom) != .custom {
                        Text("语音键预设会固定使用单键绑定；如需录制宏，请先把预设改为“自定义快捷键”。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("按键描述") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("例如 Record / Accept / Reject / Enter", text: selectedKeyDescriptionBinding)
                        .textFieldStyle(.roundedBorder)
                    if currentSelectedKey.description.containsNonASCII {
                        Text("设备 OLED 只稳定支持 ASCII。中文、emoji 和全角字符会在写入时被自动过滤，避免乱码。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("设备实际写入：\(currentSelectedKeySanitizedDescription.isEmpty ? "空白" : currentSelectedKeySanitizedDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("同步到键盘后，短按实体键切换模式时，OLED 会先短暂显示这里的描述，然后回到该模式的动图。")
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

            GroupBox("如何使用") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 在左侧点中这个实体按键。")
                    Text("2. 如果是语音键，先选软件预设；其他键按需选“单键 / 组合键”或“宏”。")
                    Text("3. 填好按键描述后点击顶部“同步到键盘”。")
                    Text("4. 在设备侧短按按键切换模式时，会先看到描述，再回到该模式动图。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                Text("空宏。点下方“添加步骤”开始录制。")
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
            GroupBox("当前模式的 OLED 动图") {
                VStack(alignment: .leading, spacing: 14) {
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
                            VStack(spacing: 10) {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text("当前仅支持动图")
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("文字、token、模型状态显示开发中")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("选择动图") {
                            selectOLEDGIF()
                        }
                        .buttonStyle(.bordered)

                        Button("预览动图") {
                            showsOLEDPlaybackPreview = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentModeDraft.oled.localAssetPath == nil)

                        Button(bleManager.isUploadingOLED ? "上传中…" : "上传到 \(selectedMode.title)") {
                            uploadCurrentOLEDToDevice()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected || bleManager.isUploadingOLED || currentModeDraft.oled.localAssetPath == nil)

                        Button("清空") {
                            clearCurrentOLED()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("当前目标：\(selectedMode.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: oledFramesPerSecondBinding, in: 5 ... 20) {
                        Text("播放速度 \(currentModeDraft.oled.framesPerSecond) FPS")
                    }

                    if let progress = bleManager.oledUploadProgress, bleManager.isUploadingOLED {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progress.fractionCompleted)
                            Text("已写入 \(progress.completedFrames)/\(progress.totalFrames) 帧，分块 \(progress.completedChunks)/\(progress.totalChunks)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("硬性限制：GIF 源文件 ≤ 2 MB。建议 5–20 FPS、最多 74 帧；将自动缩放到 160×80（RGB565）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(currentModeDraft.oled.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("显示逻辑") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("切换到当前模式时，OLED 会先显示该模式的按键描述，约 1 秒后回到该模式动图。")
                    Text("后续会继续增加文字状态、token 用量、模型环境等信息显示能力。")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("灯条由键盘固件根据 Hook 上报的 IDE 状态点亮，本软件不能改写。下表为各业务场景对应的典型 Hook 状态与出厂灯效说明；画布与「预览到设备」均按此表展示。")
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
                        Spacer()
                        Button("预览到设备") {
                            previewCurrentLightEffectOnDevice()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected || currentDevicePreviewIDEState == nil)
                    }

                    Text("当前画布预览：\(currentLightEffect.title)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(currentLightPreviewHint)
                        .font(.caption)
                        .foregroundStyle(currentDevicePreviewIDEState == nil ? .orange : .secondary)
                    if bleManager.isConnected && bleManager.workMode != 0 {
                        Text("ℹ️ 出厂固件只在物理 Mode 0（1、2 灯）下完整映射了 state → 灯效；当前键盘在 Mode \(bleManager.workMode)，点预览多半看不到效果，把拨杆切到 Mode 0 再试。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

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
                    Text("若需让某套灯效出现，请用下方「预览到设备」向固件发送一次对应可达的 IDE 状态试灯；或在 Agent 连上键盘后，通过实际触发 Hook 观察。")
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
                    Text("拨杆是物理档位，不是按下瞬态。0 档显示“自动批准”，1 档显示“手动批准”。这里只读取键盘上报的位置，不模拟物理拨动。")
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
                        Text("Claude：PermissionRequest 时返回 allow。Cursor：preToolUse（以及你自建的 beforeShell beforeMCP 钩子）stdout 会返回 permission=allow。若 agent 未连键盘或本 App 占着 BLE，会退成交回确认。须 Agent 在跑、Hook 已装。涉及 shell/删文件等高危时建议用手动档。需要逐条确认时请把拨杆切到“手动批准”。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("如何理解这个部件") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自动批准：Claude 用 PermissionRequest；Cursor 用 preToolUse 等并返回 JSON permission。均需 Agent + Hooks，且设备蓝牙由 Agent 连接。")
                    Text("手动批准：会交回用户/终端确认。若 Cursor 仍弹窗，请看 diagnostics 里 ide=cursor 与 diagnostic 字段。")
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
                         ? "Agent 与 Hook 已就位时，拨杆会参与 Claude 的 PermissionRequest 与 Cursor 的 preToolUse 等批准链。"
                         : "拨杆在 IDE 中生效需先安装 Agent 与 Hook，并把蓝牙交给 Agent；否则仅为状态显示。")
                        .font(.callout)
                }

                if hasAnyMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        agentChecklistRow(label: "LaunchAgent 已安装", ok: agentManager.isInstalled)
                        agentChecklistRow(label: "Agent 已连接蓝牙", ok: agentManager.isRunning)
                        agentChecklistRow(label: "Claude / Cursor Hook 已配置", ok: agentManager.hooksInstalled)
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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var currentModeDraft: AhaKeyModeDraft {
        studioDraft.draft(for: selectedMode)
    }

    private var currentSelectedKey: AhaKeyKeyDraft {
        let role = selectedPart.keyRole ?? .voice
        return currentModeDraft.key(for: role)
    }

    private var currentSwitchTitle: String {
        bleManager.switchState == 0 ? "自动批准" : "手动批准"
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
        AhaKeyLightBarDraft.hardwareEffect(for: lightBarPreview)
    }

    private var currentDevicePreviewIDEState: IDEState? {
        currentLightEffect.previewIDEState(forSwitchState: bleManager.switchState)
    }

    private var currentLightPreviewHint: String {
        currentLightEffect.previewHint(forSwitchState: bleManager.switchState)
    }

    private var primarySyncButtonTitle: String {
        if isSyncing {
            return "同步中…"
        }
        return hasUnsyncedChanges ? "同步到键盘" : "重新发送当前模式"
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

    private var oledFramesPerSecondBinding: Binding<Int> {
        Binding(
            get: { currentModeDraft.oled.framesPerSecond },
            set: { newValue in
                updateCurrentMode { mode in
                    mode.oled.framesPerSecond = min(20, max(5, newValue))
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
            mode.oled.localAssetPath = nil
            mode.oled.statusLine = AhaKeyOLEDDraft.default(for: selectedMode).statusLine
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

    private func updateShortcutModifier(_ modifier: ShortcutModifier, enabled: Bool) {
        updateSelectedKey { key in
            key.shortcut.setModifier(modifier, enabled: enabled)
        }
    }

    private func updateShortcutKeyCode(_ keyCode: UInt8) {
        updateSelectedKey { key in
            key.shortcut.keyCode = keyCode
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
                mode.oled.localAssetPath = url.path
                mode.oled.statusLine = "已选 \(max(frameCount, 1)) 帧 GIF 预览；切换模式时会先显示描述，再回到当前模式动图。"
            }
            syncStatusMessage = "已更新 \(selectedMode.title) 的 OLED 预览，连接后可直接上传到设备。"
        }
    }

    private func triggerPrimarySyncAction() {
        if hasUnsyncedChanges {
            syncAllModesToDevice()
        } else {
            resendCurrentModeToDevice()
        }
    }

    private func syncAllModesToDevice() {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，当前只保存本地草稿。"
            return
        }

        var commands = commandsForModes(AhaKeyModeSlot.allCases)
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存全部配置到设备"))

        isSyncing = true
        bleManager.writeCommandsSequentially(commands)
        lastSyncedDraft = studioDraft
        lastSyncDate = Date()
        syncStatusMessage = "已发送 \(commands.count) 条写入命令，设备会依次处理。"

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.isSyncing = false
        }
    }

    private func resendCurrentModeToDevice() {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，当前只保存本地草稿。"
            return
        }

        var commands = commandsForModes([selectedMode])
        commands.append((data: AhaKeyCommand.saveConfig(), label: "保存 \(selectedMode.title) 当前配置"))

        isSyncing = true
        bleManager.writeCommandsSequentially(commands)
        lastSyncDate = Date()
        syncStatusMessage = "已重新发送 \(selectedMode.title) 当前模式。"

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            self.isSyncing = false
        }
    }

    private func commandsForModes(_ modes: [AhaKeyModeSlot]) -> [(data: Data, label: String)] {
        var commands: [(data: Data, label: String)] = []

        for mode in modes {
            let draft = studioDraft.draft(for: mode)
            for role in AhaKeyKeyRole.allCases {
                let key = draft.key(for: role)
                let keyIndex = UInt8(role.rawValue)

                if key.usesMacro {
                    // 固件宏：action/param 字节流。49 步内都合法（98 字节上限）。
                    commands.append((
                        data: AhaKeyCommand.setKeyMacro(
                            mode: UInt8(mode.rawValue),
                            keyIndex: keyIndex,
                            macroData: key.macro.flattenedBytes
                        ),
                        label: "写入 \(mode.title) \(key.title) 宏: \(key.macro.displaySummary)"
                    ))
                } else if !key.shortcut.hidCodes.isEmpty {
                    commands.append((
                        data: AhaKeyCommand.setKeyMapping(
                            mode: UInt8(mode.rawValue),
                            keyIndex: keyIndex,
                            hidCodes: key.shortcut.hidCodes
                        ),
                        label: "写入 \(mode.title) \(key.title) 快捷键: \(key.shortcut.displayLabel)"
                    ))
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

    private func uploadCurrentOLEDToDevice() {
        guard bleManager.isConnected else {
            syncStatusMessage = "设备未连接，先连上键盘再上传 OLED 动图。"
            return
        }
        guard let assetPath = currentModeDraft.oled.localAssetPath else {
            syncStatusMessage = "先为 \(selectedMode.title) 选择一个 GIF，再上传到设备。"
            return
        }

        let targetMode = selectedMode
        let targetFPS = currentModeDraft.oled.framesPerSecond
        let assetURL = URL(fileURLWithPath: assetPath)

        updateMode(targetMode) { mode in
            mode.oled.statusLine = "正在上传动图到 \(targetMode.title)…"
        }
        syncStatusMessage = "开始上传 \(targetMode.title) 的 OLED 动图。"

        Task { @MainActor in
            do {
                let frames = try OLEDFrameEncoder.frames(fromGIFAt: assetURL)
                let startIndex = try await resolveOLEDUploadStartIndex(for: targetMode, frameCount: frames.count)
                try await bleManager.uploadOLEDFrames(
                    frames,
                    fps: targetFPS,
                    mode: UInt8(targetMode.rawValue),
                    startIndex: UInt16(startIndex)
                )
                updateMode(targetMode) { mode in
                    mode.oled.statusLine = "已上传 \(frames.count) 帧到设备，槽位起点 \(startIndex)；切换模式时会先显示描述，再回到当前模式动图。"
                }
                syncStatusMessage = "\(targetMode.title) OLED 动图已上传完成。"
            } catch {
                updateMode(targetMode) { mode in
                    mode.oled.statusLine = "上传失败：\(error.localizedDescription)"
                }
                syncStatusMessage = "\(targetMode.title) OLED 上传失败：\(error.localizedDescription)"
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

    private func previewCurrentLightEffectOnDevice() {
        guard let ideState = currentDevicePreviewIDEState else {
            syncStatusMessage = currentLightPreviewHint
            return
        }
        bleManager.updateIDEState(ideState)
        if bleManager.workMode == 0 {
            syncStatusMessage = "已把 \(currentLightEffect.title) 的可达预览发送到设备（Mode 0）。"
        } else {
            syncStatusMessage = "已发送 \(ideState.label) 到设备。注意：键盘当前在 Mode \(bleManager.workMode)，出厂固件可能没有在此档位映射此 state，把拨杆切到 Mode 0 可看到完整效果。"
        }
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
            }
        }
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
}

private struct VoicePermissionOnboardingSheet: View {
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
            Text("开启语音快捷键权限")
                .font(.system(size: 24, weight: .semibold))

            Text("为了让 AhaKey 的语音键在后台直接接管语音，第一次使用时需要给 AhaKey Studio 打开系统权限。macOS 原生语音还会额外用到苹果自己的麦克风和语音转写能力。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(title: "输入监控", granted: voiceRelay.inputMonitoringGranted, detail: "允许 AhaKey Studio 在后台监听实体语音键。")
                permissionRow(title: "辅助功能", granted: voiceRelay.accessibilityGranted, detail: "允许 AhaKey Studio 把语音键转换成苹果原生转写或 Fn/Globe。")
                permissionRow(title: "麦克风", granted: nativeSpeech.microphoneGranted, detail: "允许 AhaKey Studio 使用苹果原生语音采集。")
                permissionRow(title: "语音转写", granted: nativeSpeech.speechRecognitionGranted, detail: "允许 AhaKey Studio 使用苹果原生语音识别。")
            }

            Text("操作建议：先点“现在申请权限”，按系统弹窗完成授权；如果你已经在系统设置里改好了，再回到这里点“我已完成，重新检查”。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("若系统里已勾选允许，本应用仍显示未开启：请完全退出 AhaKey Studio 并再启动一次。输入监控、辅助功能等常按进程生效，只点「重新检查」或从后台切回，有时读到的仍是旧状态，重启后即可与系统设置一致。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("外发 / DMG：确保「隐私与安全性」里勾选的是当前这份 AhaKey（路径或隔离属性不同会当成另一个 App）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(voiceRelay.lastPermissionCheckSummary)
                Text(nativeSpeech.lastPermissionCheckSummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("现在申请权限") {
                    voiceRelay.refreshPermissions(requestIfNeeded: true)
                    nativeSpeech.refreshPermissions(requestIfNeeded: true)
                }
                .buttonStyle(.borderedProminent)

                Button("我已完成，重新检查") {
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                }
                .buttonStyle(.bordered)

                RestartToApplyPermissionsButton(title: "退出并重新打开")

                if !nativeSpeech.microphoneGranted || !nativeSpeech.speechRecognitionGranted {
                    Button("打开系统设置") {
                        openNativeSpeechPrivacySettingsURL()
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

            if voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted {
                Text("基础权限已经齐了。关闭这个弹窗后，AhaKey Studio 会继续在后台监听语音键；如果你使用 macOS 原生语音，麦克风和语音转写也建议一起打开。")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onChange(of: voiceRelay.inputMonitoringGranted) { _, _ in
            closeIfReady()
        }
        .onChange(of: voiceRelay.accessibilityGranted) { _, _ in
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
        guard voiceRelay.inputMonitoringGranted && voiceRelay.accessibilityGranted else { return }
        voiceRelay.dismissPermissionOnboarding()
        dismiss()
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

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(VoicePreset.allCases) { preset in
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
    let binding: ShortcutBinding
    let onModifierToggle: (ShortcutModifier, Bool) -> Void
    let onKeyCodeChange: (UInt8) -> Void

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
            }

            Picker("主键", selection: primaryKeyBinding) {
                Text("未设置").tag(UInt8(0))
                ForEach(HIDUsage.allOptions, id: \.code) { option in
                    Text(option.name).tag(option.code)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func modifierBinding(_ modifier: ShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { binding.modifiers.contains(modifier) },
            set: { onModifierToggle(modifier, $0) }
        )
    }

    private var primaryKeyBinding: Binding<UInt8> {
        Binding(
            get: { binding.keyCode },
            set: onKeyCodeChange
        )
    }
}

private struct AhaKeyKeyboardCanvasView: View {
    let modeDraft: AhaKeyModeDraft
    let selectedPart: AhaKeyStudioPart
    let lightBarPreview: LightBarPreviewState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>
    let onSelect: (AhaKeyStudioPart) -> Void

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

            ForEach([CGPoint(x: 8, y: 8), CGPoint(x: 101, y: 8), CGPoint(x: 8, y: 46), CGPoint(x: 101, y: 46)], id: \.self) { point in
                Circle()
                    .stroke(Color.black.opacity(0.14), lineWidth: 1.2)
                    .background(Circle().fill(Color.white.opacity(0.4)))
                    .frame(width: scaled(4.8, in: width), height: scaled(4.8, in: width))
                    .position(position(point.x, point.y, width: width, height: height))
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .frame(width: scaled(4.2, in: width), height: scaled(12, in: width))
                .position(position(3.8, 28, width: width, height: height))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: scaled(70, in: width), height: scaled(24, in: width))
                .position(position(43.8, 37.3, width: width, height: height))

            ledBarButton(width: width, height: height)
            oledButton(width: width, height: height)
            keyButton(for: .voice, width: width, height: height)
            keyButton(for: .approve, width: width, height: height)
            keyButton(for: .reject, width: width, height: height)
            keyButton(for: .submit, width: width, height: height)
            switchButton(width: width, height: height)
        }
    }

    private func ledBarButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.lightBar
        let rect = frame(12.3, 5.0, 55.6, 9.8, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.12) {
                Text("灯条")
                    .font(.system(size: max(rect.height * 0.18, 10), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .center)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                    HStack(spacing: rect.width * 0.085) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(ledColor(for: index))
                                .frame(width: rect.width * 0.12, height: rect.height * 0.22)
                        }
                    }
                    .padding(.horizontal, rect.width * 0.08)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: rect.height * 0.48)
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
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                LinearGradient(
                    colors: [Color.black.opacity(0.2), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    if modeDraft.oled.localAssetPath == nil {
                        if modeDraft.mode == .mode0 {
                            HStack(spacing: 6) {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: rect.height * 0.24, weight: .semibold))
                                    .foregroundStyle(Color.orange.opacity(0.92))
                                Text("Mode 0")
                                    .font(.system(size: rect.height * 0.18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Text("默认动图")
                                .font(.system(size: rect.height * 0.18))
                                .foregroundStyle(.white.opacity(0.55))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.system(size: rect.height * 0.22, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                                Text("未上传")
                                    .font(.system(size: rect.height * 0.18, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            Text("等待自定义")
                                .font(.system(size: rect.height * 0.18))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        Text("OLED")
                            .font(.system(size: rect.height * 0.22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("已选预览")
                            .font(.system(size: rect.height * 0.18))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(rect.width * 0.08)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(HotspotChrome(part: part, selectedPart: selectedPart, dirtyParts: dirtyParts))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
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
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func switchButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.toggleSwitch
        let rect = frame(87.8, 35.6, 6.8, 10.6, width: width, height: height)
        return Button {
            onSelect(part)
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
        .buttonStyle(.plain)
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

    private func ledColor(for index: Int) -> Color {
        switch AhaKeyLightBarDraft.hardwareEffect(for: lightBarPreview) {
        case .middleLight:
            [Color.red.opacity(0.28), Color.red.opacity(0.86), Color.red.opacity(0.86), Color.red.opacity(0.28)][index]
        case .singleMove:
            [Color.cyan, Color.blue.opacity(0.65), Color.cyan, Color.blue.opacity(0.65)][index]
        case .breathing:
            [Color.orange.opacity(0.65), Color.yellow.opacity(0.82), Color.orange.opacity(0.65), Color.yellow.opacity(0.82)][index]
        case .rainbowMove:
            [Color.orange, Color.yellow, Color.green, Color.blue][index]
        case .rainbowWave:
            [Color.pink, Color.orange, Color.green, Color.blue][index]
        case .rainbowWaveSlow:
            [Color.purple, Color.pink, Color.teal, Color.blue.opacity(0.8)][index]
        case .off:
            [Color.gray.opacity(0.18), Color.gray.opacity(0.18), Color.gray.opacity(0.18), Color.gray.opacity(0.18)][index]
        }
    }

    private func openNativeSpeechPrivacySettings() {
        openNativeSpeechPrivacySettingsURL()
    }
}

private func openNativeSpeechPrivacySettingsURL() {
    let candidates = [
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        "x-apple.systempreferences:com.apple.preference.security?Privacy"
    ]

    for candidate in candidates {
        if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
            break
        }
    }
}

/// 退出后由 `open -n` 再拉起同一份 .app。逻辑内联在本文件，避免单独 Swift 文件未加入 Xcode target 时报找不到符号。
private func relaunchApplicationForPermissionRefresh() {
    let bundlePath = Bundle.main.bundlePath
    DispatchQueue.global(qos: .userInitiated).async {
        Thread.sleep(forTimeInterval: 0.35)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundlePath]
        try? process.run()
    }
    NSApp.terminate(nil)
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

private struct HotspotChrome: ViewModifier {
    let part: AhaKeyStudioPart
    let selectedPart: AhaKeyStudioPart
    let dirtyParts: Set<AhaKeyStudioPart>

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selectedPart == part ? Color.accentColor : Color.black.opacity(0.05), lineWidth: selectedPart == part ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if dirtyParts.contains(part) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            .shadow(color: selectedPart == part ? Color.accentColor.opacity(0.18) : .clear, radius: 10)
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
                    ContentUnavailableView("还没有选择动图", systemImage: "film.stack")
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
                .onChange(of: path) { _, _ in
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
