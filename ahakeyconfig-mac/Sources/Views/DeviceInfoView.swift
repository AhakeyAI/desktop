import SwiftUI
import AhaKeyConfigShared

struct DeviceInfoView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject private var diagnosticsStore: BLEDeviceDiagnosticsStore
    @ObservedObject private var logStore: BLELogStore

    init(bleManager: AhaKeyBLEManager) {
        self.bleManager = bleManager
        self.logStore = bleManager.logStore
        self.diagnosticsStore = bleManager.diagnosticsStore
    }

    @StateObject private var agentManager = AgentManager.shared
    @State private var isEditingName = false
    @State private var editableName = ""
    @State private var showAgentLog = false
    @State private var agentLogPanel = 0
    @State private var logPanelContentTick = 0
    @State private var showAgentRequiredForAgentBLE = false
    @State private var isReadingFirmwareCatalog = false
    @State private var firmwareCatalogError: String?
    @State private var configurationReadError: String?

    var body: some View {
        Form {
            // MARK: - 设备信息
            Section {
                HStack(spacing: 0) {
                    infoCell("电量", value: bleManager.batteryLevelForDisplay.map { "\($0)%" } ?? "未知")
                    Divider()
                    infoCell("固件", value: bleManager.isConnected ? "v\(bleManager.firmwareMainVersion).\(bleManager.firmwareSubVersion)" : "未读取")
                    Divider()
                    infoCell("设备名", value: bleManager.deviceName ?? "—")
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell("工作模式", value: bleManager.workModeForDisplay.map(workModeName) ?? "未知")
                    Divider()
                    infoCell("灯光", value: bleManager.lightModeForDisplay.map(lightModeName) ?? "未知")
                    Divider()
                    infoCell("信号", value: bleManager.isConnected ? "\(diagnosticsStore.snapshot.signalStrength) dBm" : "未读取")
                }
                .frame(height: 50)
            } header: {
                Text(NSLocalizedString("设备信息", comment: ""))
            }

            // MARK: - 蓝牙连接（App 与 Agent 二选一）
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("同一时间只能由本 App 或 Agent 其中之一连接键盘，请在此切换。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(BluetoothConnectionOwner.allCases) { owner in
                            let selected = agentManager.bluetoothConnectionOwner == owner
                            let disableAgent = owner == .agentDaemon && !agentManager.isInstalled
                            Button {
                                if owner == .agentDaemon && !agentManager.isInstalled {
                                    showAgentRequiredForAgentBLE = true
                                } else {
                                    agentManager.setBluetoothConnectionOwner(owner, bleManager: bleManager)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(owner.title)
                                        .fontWeight(selected ? .semibold : .regular)
                                    Text(owner == .ahaKeyStudio
                                         ? "改键、LCD、同步、本机灯效测试（macOS 暂不支持 USB 有线配置）"
                                         : "Claude/Cursor/Codex/Kimi Hook、灯条状态、拨杆查询")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(disableAgent)
                        }
                    }
                    CompatLabeledContent("当前") {
                        HStack(spacing: 6) {
                            Text(bleManager.isConnected ? "本 App 已连接蓝牙" : "本 App 未连接")
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(agentBluetoothStatusText())
                        }
                        .font(.callout)
                    }
                }
            } header: {
                Text("蓝牙连接")
            }
            .alert("需要先安装 Agent", isPresented: $showAgentRequiredForAgentBLE) {
                Button("好", role: .cancel) {}
            } message: {
                Text("将蓝牙交给 `ahakeyconfig-agent` 前，请先在下方完成「安装并启用」，生成 LaunchAgent。")
            }

            // MARK: - 拨杆状态
            Section {
                HStack {
                    Text("拨杆档位")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.switchStateForDisplay == 0 ? Color.green : Color.indigo)
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut(duration: 0.1), value: bleManager.switchState)
                        Text(switchStateLabel(bleManager.switchStateForDisplay))
                    }
                }
            } header: {
                Text("拨杆档位")
            } footer: {
                Text("仅在实体自动档且出厂自动绑定已确认时自动批准；其他情况使用原生审批。")
            }

            // MARK: - LED 状态同步
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(agentManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(NSLocalizedString("LED 跟随 IDE 状态", comment: ""))
                            Text(agentBluetoothShortLabel())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            hookBadge("Claude", installed: agentManager.claudeHooksInstalled)
                            hookBadge("Cursor", installed: agentManager.cursorHooksInstalled)
                            hookBadge("Codex", installed: agentManager.codexHooksInstalled)
                            hookBadge("Kimi", installed: agentManager.kimiHooksInstalled)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    if agentManager.isInstalled {
                        Button(agentManager.isRunning ? "停止" : "启动") {
                            if agentManager.isRunning {
                                agentManager.stop()
                            } else {
                                agentManager.start()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(agentManager.bluetoothConnectionOwner == .ahaKeyStudio)
                        .help(agentManager.bluetoothConnectionOwner == .ahaKeyStudio
                              ? "当前由本 App 占用蓝牙，Agent 应处于未加载。请先在「蓝牙连接」中选中 Agent 后再启停守护进程。"
                              : "从 launchd 加载并启动/卸载停止 Agent 进程。")

                        Button(NSLocalizedString("卸载", comment: ""), role: .destructive) {
                            agentManager.uninstall(bleManager: bleManager)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        HStack(spacing: 8) {
                            if agentManager.isAgentOperationInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button(NSLocalizedString("安装并启用", comment: "")) {
                                agentManager.install()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(agentManager.isAgentOperationInProgress)
                        }
                    }
                }

                if agentManager.isInstalled {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)],
                              alignment: .leading, spacing: 10) {
                        Button(NSLocalizedString("查看日志", comment: "")) {
                            showAgentLog.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        if agentManager.claudeHooksInstalled {
                            Button("移除 Claude Hooks") { agentManager.removeClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button("安装 Claude Hooks") { agentManager.installClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.cursorHooksInstalled {
                            Button("移除 Cursor Hooks") { agentManager.removeCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button("安装 Cursor Hooks") { agentManager.installCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.codexHooksInstalled {
                            Button("移除 Codex Hooks") { agentManager.removeCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button("安装 Codex Hooks") { agentManager.installCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.kimiHooksInstalled {
                            Button("移除 Kimi Hooks") { agentManager.removeKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button("安装 Kimi Hooks") { agentManager.installKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("LED 状态同步 · Hook 联动", comment: ""))
            } footer: {
                if !agentManager.isAgentBinaryPresentInBundle {
                    Text("发版包内未包含 ahakeyconfig-agent，无法使用守护进程。请用完整「AhaKey Studio.app」或联系开发者。")
                        .foregroundStyle(.orange)
                } else if agentManager.isInstalled, agentManager.bluetoothConnectionOwner == .ahaKeyStudio, !agentManager.isRunning {
                    Text("已由本 App 占用蓝牙：要让 Agent 接管，请将「蓝牙连接」选为 ahakeyconfig-agent。")
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showAgentLog) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("诊断日志", comment: ""))
                            .font(.headline)
                        Spacer()
                        Button("关闭") { showAgentLog = false }
                    }
                    Picker("内容", selection: $agentLogPanel) {
                        Text("ahakeyconfig-agent 主日志").tag(0)
                        Text(NSLocalizedString("工具批准（permission-request.log）", comment: "")).tag(1)
                        Text("~/.cursor/hooks.json").tag(2)
                        Text("~/.cursor/cli-config.json").tag(3)
                        Text("~/.codex/config.toml").tag(4)
                        Text("Codex Hook（codex-hook.log）").tag(5)
                        Text("~/.kimi/config.toml").tag(6)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    HStack {
                        Button(NSLocalizedString("刷新本页", comment: "")) {
                            logPanelContentTick += 1
                            agentManager.refresh()
                        }
                        if agentLogPanel == 3 {
                            Button(NSLocalizedString("合并 CLI + IDE 终端白名单", comment: "")) {
                                let a = agentManager.mergeUserCursorCliConfigForShellAutoApprove()
                                let b = agentManager.mergeUserCursorPermissionsJsonForAgentTUI()
                                agentManager.agentUserAlert = a + "\n\n——\n\n" + b
                            }
                            .help("写 cli-config（CLI）与 permissions.json 的 terminalAllowlist（Agent TUI「Not in allowlist」层）；分见官方文档。均先备份为 .ahakey.bak。")
                        }
                        Spacer()
                    }
                    .font(.caption)
                    ScrollView {
                        logPanelContent
                            .id(logPanelContentTick)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .frame(width: 540, height: 380)
            }

            // MARK: - LED 测试
            if bleManager.isConnected {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(Array(IDEState.allCases.enumerated()), id: \.offset) { _, state in
                            Button {
                                bleManager.updateIDEState(state)
                            } label: {
                                Text(state.label)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("LED 测试")
                } footer: {
                    Text("点击按钮发送对应状态到键盘，观察 LED 变化。")
                }
            }

            // MARK: - BLE 连接状态
            Section {
                CompatLabeledContent(NSLocalizedString("连接", comment: "")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(bleManager.bleConnectionStatus)
                    }
                }
                CompatLabeledContent(NSLocalizedString("设备名", comment: "")) {
                    if isEditingName {
                        HStack(spacing: 4) {
                            TextField("最长 15 字节", text: $editableName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { submitNameChange() }
                            Button("写入键盘") { submitNameChange() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button("取消") { isEditingName = false }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(bleManager.deviceName ?? "—")
                                .textSelection(.enabled)
                            if bleManager.isConnected {
                                Button {
                                    editableName = bleManager.deviceName ?? ""
                                    isEditingName = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                CompatLabeledContent("UUID") {
                    Text(bleManager.bleDeviceUUID)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                CompatLabeledContent("固件协议") {
                    Text(firmwareProfileLabel())
                        .textSelection(.enabled)
                }
                if let firmwareCatalogError {
                    Text(firmwareCatalogError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    CompatLabeledContent("特征") {
                        HStack(spacing: 8) {
                            charBadge("DATA", ready: bleManager.dataCharReady)
                            charBadge("CMD", ready: bleManager.commandCharReady)
                            charBadge("NOTIFY", ready: bleManager.notifyCharReady)
                        }
                    }
                }
            } header: {
                Text("BLE 连接状态")
            }

            StandbySettingsView(bleManager: bleManager).disabled(isReadingFirmwareCatalog)
            SideSwitchSettingsView(bleManager: bleManager).disabled(isReadingFirmwareCatalog)
            OrdinaryKeySettingsView(bleManager: bleManager).disabled(isReadingFirmwareCatalog)
            VoiceHandoffSettingsView(bleManager: bleManager).disabled(isReadingFirmwareCatalog)
            configurationReadbackSection

            // MARK: - 操作
            Section {
                HStack {
                    if !bleManager.isConnected {
                        Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                            bleManager.userInitiatedConnect()
                        }
                        .buttonStyle(.bordered)
                        .disabled(bleManager.isScanning || agentManager.bluetoothConnectionOwner == .agentDaemon)
                        .help(agentManager.bluetoothConnectionOwner == .agentDaemon
                              ? "当前选择由 ahakeyconfig-agent 占用蓝牙。请先在上方「蓝牙连接」切到 AhaKey Studio，或点击顶栏「设备信息 · Agent」切换。"
                              : "本 App 主动连接键盘。")
                    } else {
                        Button("查询状态") {
                            bleManager.queryDeviceStatus()
                        }
                        .buttonStyle(.bordered)
                        .help("发送 AA BB 00 CC DD 查询设备状态")

                        Button(isReadingFirmwareCatalog ? "读取中…" : "读取固件能力") {
                            isReadingFirmwareCatalog = true
                            firmwareCatalogError = nil
                            Task { @MainActor in
                                defer { isReadingFirmwareCatalog = false }
                                do {
                                    _ = try await bleManager.readFirmwareCapabilityProfile()
                                } catch {
                                    firmwareCatalogError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isReadingFirmwareCatalog || bleManager.isConfigurationOperationInProgress)
                        .help("只读查询固件目录；未知固件不会开放新配置写入")

                        Button("探测协议") {
                            bleManager.sendProbeCommands()
                        }
                        .buttonStyle(.bordered)
                        .help("向设备发送探测命令，观察通信日志中的回调")

                        Spacer()

                        Button("断开", role: .destructive) {
                            bleManager.disconnect()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // MARK: - 通信日志
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("详细通信日志（15 分钟后自动关闭）", isOn: Binding(
                        get: { logStore.isVerboseLoggingEnabled },
                        set: { logStore.setVerboseLoggingEnabled($0) }
                    ))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(logStore.entries) { entry in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.formattedTime)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(entry.message)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(entry.isError ? .red : .secondary)
                                            .textSelection(.enabled)
                                    }
                                    .id(entry.id)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 150)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: logStore.entries.count) { _ in
                            if let last = logStore.entries.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("复制全部") {
                            let text = logStore.entries.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        Button("清空") {
                            bleManager.clearLog()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text(NSLocalizedString("通信日志", comment: ""))
            }
        }
        .formStyle(.grouped)
        .onAppear { bleManager.setDiagnosticsWindowVisible(true) }
        .onDisappear { bleManager.setDiagnosticsWindowVisible(false) }
        // 「设备信息」在 sheet 中展示时，父视图的 `.alert` 往往不会置顶显示，导致 Hooks 安装/报错像「无反应」。在此重复绑定以确保可见。
        .alert("Agent", isPresented: Binding(
            get: { agentManager.agentUserAlert != nil },
            set: { if !$0 { agentManager.agentUserAlert = nil } }
        )) {
            Button(NSLocalizedString("好", comment: ""), role: .cancel) {
                agentManager.agentUserAlert = nil
            }
        } message: {
            Text(agentManager.agentUserAlert ?? "")
        }

    }

    // MARK: - Components

    private func infoCell(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func hookBadge(_ label: String, installed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(installed ? .green : .secondary)
            Text("\(label) Hooks")
                .foregroundStyle(installed ? .primary : .secondary)
        }
    }

    private func charBadge(_ label: String, ready: Bool) -> some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ready ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .foregroundStyle(ready ? Color.green : Color.secondary)
    }

    private func firmwareProfileLabel() -> String {
        guard let profile = bleManager.firmwareCapabilityProfile else { return "未读取" }
        switch profile.identity {
        case .knownWS2Catalog:
            return "WS2 CP4D · 只读探测"
        case .legacy:
            return "旧版协议"
        case .unknown(let key):
            return key.map { "未知目录：\($0)" } ?? "未知"
        }
    }

    private var configurationReadbackSection: some View {
        Section {
            Button(bleManager.isReadingConfigurationSnapshot ? "正在读取键盘配置…" : "读取键盘配置（只读）") {
                configurationReadError = nil
                Task { @MainActor in
                    do { try await bleManager.readDeviceConfigurationSnapshot() }
                    catch { configurationReadError = error.localizedDescription }
                }
            }
            .disabled(!bleManager.isConnected || isReadingFirmwareCatalog || bleManager.isConfigurationOperationInProgress)
            Text("展示键盘保存值，不覆盖本地草稿。语音平台预设可能改变 Voice 键的实际输出。")
                .font(.caption).foregroundStyle(.secondary)
            if let configurationReadError { Text(configurationReadError).foregroundStyle(.orange) }
            CompatLabeledContent("待机") {
                Text(bleManager.configurationSnapshot.standbyMinutes.map { $0 == 0 ? "不自动待机" : "\($0) 分钟" } ?? settingReadStatus(.standby))
            }
            CompatLabeledContent("语音引导") {
                Text(bleManager.configurationSnapshot.voiceOnboardingState.map { value in
                    ["未选择", "已选 Windows", "已选 Mac", "桌面接管", "已跳过"][Int(value)]
                } ?? settingReadStatus(.voice))
            }
            if let side = bleManager.configurationSnapshot.sideSwitch {
                ForEach(side.positions.indices, id: \.self) { index in
                    CompatLabeledContent("拨杆位置 \(index + 1) 绑定") {
                        let position = side.positions[index]
                        Text("\(["出厂自动", "出厂手动", "禁用", "自定义"][Int(position.bindType)]) \(position.action.hexString)")
                            .textSelection(.enabled)
                    }
                }
            } else {
                CompatLabeledContent("拨杆绑定") { Text(settingReadStatus(.sideSwitch)) }
            }
            ForEach(0..<16, id: \.self) { index in
                let mode = UInt8(index / 4), key = UInt8(index % 4)
                CompatLabeledContent("Mode \(mode + 1) · Key \(key + 1)") {
                    Text(keyReadbackText(mode: mode, index: key))
                        .font(.caption).textSelection(.enabled)
                }
            }
        } header: { Text("键盘配置 · 只读") }
    }

    private func settingReadStatus(_ field: DeviceConfigurationSnapshot.Field) -> String {
        bleManager.configurationSnapshot.failures[field].map { "读取失败：\($0)" } ?? "未读取"
    }

    private func keyReadbackText(mode: UInt8, index: UInt8) -> String {
        guard let result = bleManager.configurationSnapshot.keys[.key(mode: mode, index: index)] else {
            return settingReadStatus(.key(mode: mode, index: index))
        }
        switch result {
        case .value(let value):
            let description = String(data: value.description, encoding: .utf8) ?? "描述 HEX：\(value.description.hexString)"
            let label = value.isKnownEditableAction ? "已读回" : "未知动作 · 只读"
            return "\(label) · \(description) · 类型 \(String(format: "%02X", value.actionType)) · \(value.action.hexString)"
        case .tooLarge: return "动作过长，无法完整读回 · 只读"
        case .rejected(let status): return "设备拒绝（\(status)）"
        case .malformed: return "无效回包"
        }
    }

    private func switchStateLabel(_ state: Int?) -> String {
        switch state { case 0: return "自动档"; case 1: return "手动档"; default: return "未知" }
    }

    private func agentBluetoothStatusText() -> String {
        if agentManager.isRunning && agentManager.isAgentBLEConnected { return "Agent 已连接蓝牙" }
        if agentManager.isRunning { return "Agent 运行中（BLE 未连接）" }
        if agentManager.isInstalled { return "Agent 未运行" }
        return "Agent 未安装"
    }

    private func agentBluetoothShortLabel() -> String {
        if agentManager.isRunning && agentManager.isAgentBLEConnected { return "已连蓝牙" }
        if agentManager.isRunning { return "BLE 未连接" }
        if agentManager.isInstalled { return "未运行" }
        return "未装 Agent"
    }

    private func workModeName(_ mode: Int) -> String {
        switch mode {
        case 0: return "Mode 1 / Claude"
        case 1: return "Mode 2 / Cursor"
        case 2: return "Mode 3 / Codex"
        case 3: return "Mode 4 / custom"
        default: return "Mode \(mode)"
        }
    }

    private func lightModeName(_ mode: Int) -> String {
        switch mode {
        case 0: return "关闭"
        case 1: return "常亮"
        case 2: return "呼吸"
        default: return "\(mode)"
        }
    }

    @ViewBuilder
    private var logPanelContent: some View {
        switch agentLogPanel {
        case 0:
            Text(agentManager.readLog())
        case 1:
            Text(agentManager.readPermissionRequestLog())
        case 2:
            Text(agentManager.readUserCursorHooksJsonForDisplay())
        case 3:
            Text(agentManager.readUserCursorCliConfigForDisplay())
        case 4:
            Text(agentManager.readUserCodexConfigForDisplay())
        case 5:
            Text(agentManager.readCodexHookLog())
        case 6:
            Text(agentManager.readUserKimiConfigForDisplay())
        default:
            Text("")
        }
    }

    private func submitNameChange() {
        let name = editableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        bleManager.changeDeviceName(name)
        isEditingName = false
    }
}
