import AhaKeyConfigShared
import SwiftUI

struct DeviceInfoView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var agentManager = AgentManager.shared
    @State private var isEditingName = false
    @State private var editableName = ""
    @State private var showAgentLog = false
    @State private var agentLogPanel = 0
    @State private var logPanelContentTick = 0
    @State private var showAgentRequiredForAgentBLE = false

    var body: some View {
        Form {
            // MARK: - 设备信息
            Section {
                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("电量", comment: ""), value: String(format: NSLocalizedString("%d%%", comment: ""), bleManager.batteryLevel))
                    Divider()
                    infoCell(NSLocalizedString("固件", comment: ""), value: String(format: NSLocalizedString("v%d.%d", comment: ""), bleManager.firmwareMainVersion, bleManager.firmwareSubVersion))
                    Divider()
                    infoCell(NSLocalizedString("设备名", comment: ""), value: bleManager.deviceName ?? "—")
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("工作模式", comment: ""), value: workModeName(bleManager.workMode))
                    Divider()
                    infoCell(NSLocalizedString("灯光", comment: ""), value: lightModeName(bleManager.lightMode))
                    Divider()
                    infoCell(NSLocalizedString("信号", comment: ""), value: String(format: NSLocalizedString("%d dBm", comment: ""), bleManager.signalStrength))
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("型号", comment: ""), value: bleManager.modelNumber == "—" ? AhaKeyDevicePresentation.modelName : bleManager.modelNumber)
                    Divider()
                    infoCell(NSLocalizedString("设备编号", comment: ""), value: bleManager.deviceIdentifier)
                    Divider()
                    infoCell(NSLocalizedString("协议模式", comment: ""), value: protocolModeLabel(bleManager.protocolMode))
                }
                .frame(height: 50)
            } header: {
                Text(NSLocalizedString("设备信息", comment: ""))
            }

            // MARK: - 蓝牙连接（App 与 Agent 二选一）
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("同一时间只能由本 App 或 Agent 其中之一连接键盘，请在此切换。", comment: ""))
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
                                         ? NSLocalizedString("改键、LCD、同步、本机灯效测试（macOS 暂不支持 USB 有线配置）", comment: "")
                                         : NSLocalizedString("Claude/Cursor/Codex/Kimi Hook、灯条状态、拨杆查询", comment: ""))
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
                    CompatLabeledContent(NSLocalizedString("当前", comment: "")) {
                        Text(bleOwnershipText())
                            .font(.callout)
                    }
                }
            } header: {
                Text(NSLocalizedString("蓝牙连接", comment: ""))
            }
            .alert(NSLocalizedString("需要先安装 Agent", comment: ""), isPresented: $showAgentRequiredForAgentBLE) {
                Button(NSLocalizedString("好", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("将蓝牙交给 `ahakeyconfig-agent` 前，请先在下方完成「安装并启用」，生成 LaunchAgent。", comment: ""))
            }

            // MARK: - 拨杆状态
            Section {
                HStack {
                    Text(NSLocalizedString("当前档位", comment: ""))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.switchState == 0 ? Color.green : Color.indigo)
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut(duration: 0.1), value: bleManager.switchState)
                        Text(switchStateLabel(bleManager.switchState))
                    }
                }
            } header: {
                Text(NSLocalizedString("拨杆档位", comment: ""))
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
                        Button(agentManager.isRunning ? NSLocalizedString("停止", comment: "") : NSLocalizedString("启动", comment: "")) {
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
                              ? NSLocalizedString("当前由本 App 占用蓝牙，Agent 应处于未加载。请先在「蓝牙连接」中选中 Agent 后再启停守护进程。", comment: "")
                              : NSLocalizedString("从 launchd 加载并启动/卸载停止 Agent 进程。", comment: ""))

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
                    HStack(spacing: 10) {
                        Button(NSLocalizedString("查看日志", comment: "")) {
                            showAgentLog.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Spacer()

                        if agentManager.claudeHooksInstalled {
                            Button(NSLocalizedString("移除 Claude Hooks", comment: "")) { agentManager.removeClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Claude Hooks", comment: "")) { agentManager.installClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.cursorHooksInstalled {
                            Button(NSLocalizedString("移除 Cursor Hooks", comment: "")) { agentManager.removeCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Cursor Hooks", comment: "")) { agentManager.installCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.codexHooksInstalled {
                            Button(NSLocalizedString("移除 Codex Hooks", comment: "")) { agentManager.removeCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Codex Hooks", comment: "")) { agentManager.installCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if agentManager.kimiHooksInstalled {
                            Button(NSLocalizedString("移除 Kimi Hooks", comment: "")) { agentManager.removeKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Kimi Hooks", comment: "")) { agentManager.installKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("LED 状态同步 · Hook 联动", comment: ""))
            } footer: {
                if !agentManager.isAgentBinaryPresentInBundle {
                    Text(NSLocalizedString("发版包内未包含 ahakeyconfig-agent，无法使用守护进程。请用完整「AhaKey Studio.app」或联系开发者。", comment: ""))
                        .foregroundStyle(.orange)
                } else if agentManager.isInstalled, agentManager.bluetoothConnectionOwner == .ahaKeyStudio, !agentManager.isRunning {
                    Text(NSLocalizedString("已由本 App 占用蓝牙：要让 Agent 接管，请将「蓝牙连接」选为 ahakeyconfig-agent。", comment: ""))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showAgentLog) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("诊断日志", comment: ""))
                            .font(.headline)
                        Spacer()
                        Button(NSLocalizedString("关闭", comment: "")) { showAgentLog = false }
                    }
                    Picker(NSLocalizedString("内容", comment: ""), selection: $agentLogPanel) {
                        Text(NSLocalizedString("ahakeyconfig-agent 主日志", comment: "")).tag(0)
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
                            .help(NSLocalizedString("写 cli-config（CLI）与 permissions.json 的 terminalAllowlist（Agent TUI「Not in allowlist」层）；分见官方文档。均先备份为 .ahakey.bak。", comment: ""))
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

            // MARK: - 实时控制当前前台 Kimi（实验）
            Section {
                Toggle(isOn: $agentManager.kimiTUIAdapterEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("实时控制当前前台 Kimi", comment: ""))
                        Text(NSLocalizedString("拨杆切换时，自动向前台 Terminal.app / iTerm2 的 Kimi tab 发送 /yolo on/off。默认关闭。", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(NSLocalizedString("实验功能", comment: ""))
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
                    Text(NSLocalizedString("LED 测试", comment: ""))
                } footer: {
                    Text(NSLocalizedString("点击按钮发送对应状态到键盘，观察 LED 变化。", comment: ""))
                }
            }

            // MARK: - BLE 连接状态
            Section {
                CompatLabeledContent(NSLocalizedString("连接", comment: "")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill((bleManager.isConnected || agentManager.isAgentBLEConnected) ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(bleManager.isConnected ? bleManager.bleConnectionStatus
                             : (agentManager.isAgentBLEConnected
                                ? bleOwnershipText()
                                : bleManager.bleConnectionStatus))
                    }
                }
                CompatLabeledContent(NSLocalizedString("设备名", comment: "")) {
                    if isEditingName {
                        HStack(spacing: 4) {
                            TextField(NSLocalizedString("最长 15 字节", comment: ""), text: $editableName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { submitNameChange() }
                            Button(NSLocalizedString("保存", comment: "")) { submitNameChange() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            Button(NSLocalizedString("取消", comment: "")) { isEditingName = false }
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
                CompatLabeledContent(NSLocalizedString("固件能力", comment: "")) {
                    Text(capabilitiesSummary(bleManager.firmwareCapabilities))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                HStack {
                    CompatLabeledContent(NSLocalizedString("特征", comment: "")) {
                        HStack(spacing: 8) {
                            charBadge("DATA", ready: bleManager.dataCharReady)
                            charBadge("CMD", ready: bleManager.commandCharReady)
                            charBadge("NOTIFY", ready: bleManager.notifyCharReady)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("BLE 连接状态", comment: ""))
            }

            // MARK: - 操作
            Section {
                HStack {
                    if !bleManager.isConnected {
                        Button(bleManager.isScanning ? NSLocalizedString("扫描中…", comment: "") : NSLocalizedString("连接设备", comment: "")) {
                            bleManager.userInitiatedConnect()
                        }
                        .buttonStyle(.bordered)
                        .disabled(bleManager.isScanning || agentManager.bluetoothConnectionOwner == .agentDaemon)
                        .help(agentManager.bluetoothConnectionOwner == .agentDaemon
                              ? NSLocalizedString("当前选择由 ahakeyconfig-agent 占用蓝牙。请先在上方「蓝牙连接」切到 AhaKey Studio，或点击顶栏「设备信息 · Agent」切换。", comment: "")
                              : NSLocalizedString("本 App 主动连接键盘。", comment: ""))
                    } else {
                        Button(NSLocalizedString("查询状态", comment: "")) {
                            bleManager.queryDeviceStatus()
                        }
                        .buttonStyle(.bordered)
                        .help(NSLocalizedString("发送 AA BB 00 CC DD 查询设备状态", comment: ""))

                        Button(NSLocalizedString("探测协议", comment: "")) {
                            bleManager.sendProbeCommands()
                        }
                        .buttonStyle(.bordered)
                        .help(NSLocalizedString("向设备发送探测命令，观察通信日志中的回调", comment: ""))

                        Spacer()

                        Button(NSLocalizedString("断开", comment: ""), role: .destructive) {
                            bleManager.disconnect()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // MARK: - 通信日志
            Section {
                // 独立 Store：日志 append 只刷新这个子视图，不波及观察 manager 的其它 View
                CommLogSection(logStore: bleManager.logStore)
            } header: {
                Text(NSLocalizedString("通信日志", comment: ""))
            }
        }
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
        // RSSI 轮询只在设备信息窗口打开时进行：打开立即读一次并恢复 5 秒轮询，关闭停止
        .onAppear { bleManager.setDiagnosticsWindowVisible(true) }
        .onDisappear { bleManager.setDiagnosticsWindowVisible(false) }

    }

    // MARK: - Components

    private func infoCell(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
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

    private func switchStateLabel(_ state: Int) -> String {
        state == 0 ? NSLocalizedString("自动批准", comment: "") : NSLocalizedString("手动批准", comment: "")
    }

    /// 蓝牙占用的用户视角表述：编辑器（本 App）与 Agent 二选一持有键盘连接。
    /// 避免"本 App 未连接 / 已断开"在 Agent 占用时被误读为故障。
    private func bleOwnershipText() -> String {
        if bleManager.isConnected { return NSLocalizedString("编辑器占用蓝牙 · Agent 空闲", comment: "") }
        if agentManager.isAgentBLEConnected { return NSLocalizedString("编辑器空闲 · Agent 占用蓝牙", comment: "") }
        return NSLocalizedString("编辑器空闲 · Agent 空闲（未连接键盘）", comment: "")
    }

    private func agentBluetoothShortLabel() -> String {
        if agentManager.isRunning && agentManager.isAgentBLEConnected { return NSLocalizedString("已连蓝牙", comment: "") }
        if agentManager.isRunning { return NSLocalizedString("BLE 未连接", comment: "") }
        if agentManager.isInstalled { return NSLocalizedString("未运行", comment: "") }
        return NSLocalizedString("未装 Agent", comment: "")
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
        case 0: return "Off"
        case 1: return "Solid"
        case 2: return "Breathing"
        default: return "\(mode)"
        }
    }

    private func protocolModeLabel(_ mode: AhaKeyProtocolMode) -> String {
        switch mode {
        case .negotiating: return NSLocalizedString("协商中…", comment: "")
        case .legacy: return NSLocalizedString("旧版兼容 (legacy)", comment: "")
        case .current: return NSLocalizedString("当前协议 (v3)", comment: "")
        case .restrictedUnknown: return NSLocalizedString("受限未知", comment: "")
        }
    }

    private func capabilitiesSummary(_ capabilities: AhaKeyFirmwareCapabilities?) -> String {
        guard let capabilities else { return "—" }
        return String(
            format: NSLocalizedString("v%d · %d 模式 · %d 套 · %d 状态 · %dB", comment: ""),
            capabilities.protocolVersion, capabilities.modeCount,
            capabilities.setCount, capabilities.stateCount, capabilities.maxPacketSize
        )
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

// MARK: - 通信日志（观察独立的 BLELogStore）

/// 通信日志区：内存诊断级日志列表 + 复制/清空 + 临时详细级（TX/RX 抓包）开关。
/// 只观察 `BLELogStore`，日志刷新不再触发整个 DeviceInfoView / 观察 manager 的 View 重绘。
private struct CommLogSection: View {
    @ObservedObject var logStore: BLELogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                Button(NSLocalizedString("复制全部", comment: "")) {
                    let text = logStore.entries.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button(NSLocalizedString("清空", comment: "")) {
                    logStore.clear()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 4)

            // 临时详细级（TX/RX 抓包）：默认关闭，开启 15 分钟自动关闭，写 ble-verbose.log
            Toggle(isOn: Binding(
                get: { logStore.isVerboseLoggingEnabled },
                set: { logStore.setVerboseLoggingEnabled($0) }
            )) {
                Text(NSLocalizedString("详细日志（TX/RX 抓包）", comment: ""))
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 6)
            if logStore.isVerboseLoggingEnabled, let expiresAt = logStore.verboseSessionExpiresAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let remainingMinutes = max(1, Int(ceil(expiresAt.timeIntervalSince(context.date) / 60)))
                    Text(String(format: NSLocalizedString("原始收发写入 ble-verbose.log，约 %d 分钟后自动关闭", comment: ""), remainingMinutes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(NSLocalizedString("开启后原始收发写入 ble-verbose.log（5MB×3 轮转），15 分钟自动关闭", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
