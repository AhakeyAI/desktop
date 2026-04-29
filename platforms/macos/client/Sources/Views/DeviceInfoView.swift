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
                    infoCell("电量", value: "\(bleManager.batteryLevel)%")
                    Divider()
                    infoCell("固件", value: "v\(bleManager.firmwareMainVersion).\(bleManager.firmwareSubVersion)")
                    Divider()
                    infoCell("设备名", value: bleManager.deviceName ?? "—")
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell("工作模式", value: workModeName(bleManager.workMode))
                    Divider()
                    infoCell("灯光", value: lightModeName(bleManager.lightMode))
                    Divider()
                    infoCell("信号", value: "\(bleManager.signalStrength) dBm")
                }
                .frame(height: 50)
            } header: {
                Text("设备信息")
            }

            // MARK: - 蓝牙连接（App 与 Agent 二选一）
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("主程序与 `ahakeyconfig-agent` 是两个独立进程；CoreBluetooth 同时只能有一个连接键盘。请在此显式切换由谁占用蓝牙。")
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
                                         ? "改键、OLED、同步、本机灯效测试"
                                         : "Claude/Cursor Hook、灯条状态、拨杆查询")
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
                    LabeledContent("当前") {
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
            } footer: {
                Text("「Agent 已连接蓝牙」表示守护进程正在运行且已与键盘建立 BLE 连接（通过查询 socket switchState 确认）。「BLE 未连接」表示进程在跑但键盘尚未连上。选「AhaKey Studio」会改为由本 App 连接；选「Agent」会断开本 App 并启动守护进程。")
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
                            .fill(bleManager.switchState == 0 ? Color.green : Color.indigo)
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut(duration: 0.1), value: bleManager.switchState)
                        Text(switchStateLabel(bleManager.switchState))
                    }
                }
                Text(switchStateDescription(
                    bleManager.switchState,
                    agentRunning: agentManager.isRunning,
                    agentInstalled: agentManager.isInstalled,
                    hooksReady: agentManager.hooksInstalled
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("拨杆档位")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("拨杆是物理档位。0=自动批准、非0=在 Claude 里交回 `ask`；Cursor 的 preToolUse/beforeShell 等由 Hook 回 `allow`/`ask`，二者都需 Agent + Hooks 且蓝牙由 agent 持有时才按拨杆。")
                    Text("若 Cursor 仍弹出「运行 Shell」：与 Aha hook 是两套。打开本页「查看日志」→ 选「cli-config」可查看/一键合并白名单与 approvalMode。")
                }
            }

            // MARK: - LED 状态同步
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(agentManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("LED 跟随 Claude 状态")
                            Text(agentBluetoothShortLabel())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            hookBadge("Claude", installed: agentManager.claudeHooksInstalled)
                            hookBadge("Cursor", installed: agentManager.cursorHooksInstalled)
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

                        Button("卸载", role: .destructive) {
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
                            Button("安装并启用") {
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
                        Button("查看日志") {
                            showAgentLog.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Spacer()

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
                    }
                }
            } header: {
                Text("LED 状态同步 · Hook 联动")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !agentManager.isAgentBinaryPresentInBundle {
                        Text("发版包内未包含 ahakeyconfig-agent 可执行文件时，无法使用守护进程。请用完整「AhaKey Studio.app」或联系开发者。")
                            .foregroundStyle(.orange)
                    } else if agentManager.isInstalled, agentManager.bluetoothConnectionOwner == .ahaKeyStudio, !agentManager.isRunning {
                        Text("已安装 LaunchAgent 且当前由本 App 占蓝牙，因此 Agent 未加载：请先在上文将「蓝牙连接」选为「ahakeyconfig-agent」再观察运行状态，或点「安装并启用」时阅读弹窗说明。")
                            .foregroundStyle(.secondary)
                    }
                    Text("1) 键盘 LED 可随 IDE 状态变。2) 工具「自动批准」：Claude 走 PermissionRequest；Cursor 走 preToolUse（stdout 返回 permission，可在 hooks.json 自配 `beforeShellExecution` / `beforeMCPExecution` 亦支持同一二进制）。3) 诊断见 AhaKeyConfig/diagnostics/permission-request.log（ide、hookEvent、diagnostic）。")
                }
            }
            .sheet(isPresented: $showAgentLog) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("诊断日志")
                            .font(.headline)
                        Spacer()
                        Button("关闭") { showAgentLog = false }
                    }
                    Picker("内容", selection: $agentLogPanel) {
                        Text("ahakeyconfig-agent 主日志").tag(0)
                        Text("工具批准（permission-request.log）").tag(1)
                        Text("~/.cursor/hooks.json").tag(2)
                        Text("~/.cursor/cli-config.json").tag(3)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    HStack {
                        Button("刷新本页") {
                            logPanelContentTick += 1
                            agentManager.refresh()
                        }
                        if agentLogPanel == 3 {
                            Button("合并 CLI + IDE 终端白名单") {
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
                LabeledContent("连接") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(bleManager.bleConnectionStatus)
                    }
                }
                LabeledContent("设备名") {
                    if isEditingName {
                        HStack(spacing: 4) {
                            TextField("最长 15 字节", text: $editableName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { submitNameChange() }
                            Button("保存") { submitNameChange() }
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
                LabeledContent("UUID") {
                    Text(bleManager.bleDeviceUUID)
                        .monospaced()
                        .font(.caption)
                        .textSelection(.enabled)
                }
                HStack {
                    LabeledContent("特征") {
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(bleManager.commLog) { entry in
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
                        .onChange(of: bleManager.commLog.count) { _, _ in
                            if let last = bleManager.commLog.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button("复制全部") {
                            let text = bleManager.commLog.map { "[\($0.formattedTime)] \($0.message)" }.joined(separator: "\n")
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
                Text("通信日志")
            }
        }
        .formStyle(.grouped)
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
        state == 0 ? "自动批准" : "手动批准"
    }

    private func switchStateDescription(_ state: Int, agentRunning: Bool, agentInstalled: Bool, hooksReady: Bool) -> String {
        let pieces: [String]
        if state == 0 {
            pieces = [
                "自动批准：Claude 为 PermissionRequest；Cursor 为 preToolUse 等（stdout permission）。需 Agent、Hooks、蓝牙交给 Agent。",
                agentBluetoothStatusTextForDescription(agentRunning: agentRunning, agentInstalled: agentInstalled),
                hooksReady ? "Hooks 已配置" : "Hooks 未配置",
            ]
        } else {
            pieces = [
                "手动：Claude/Cursor 批准链会交回确认（Cursor 无「PermissionRequest」事件名，但 preToolUse 等可返回 ask）。",
            ]
        }
        return pieces.joined(separator: " · ")
    }

    private func agentBluetoothStatusText() -> String {
        if agentManager.isRunning && agentManager.isAgentBLEConnected { return "Agent 已连接蓝牙" }
        if agentManager.isRunning { return "Agent 运行中（BLE 未连接）" }
        if agentManager.isInstalled { return "Agent 未运行" }
        return "Agent 未安装"
    }

    private func agentBluetoothStatusTextForDescription(agentRunning: Bool, agentInstalled: Bool) -> String {
        agentBluetoothStatusText()
    }

    private func agentBluetoothShortLabel() -> String {
        if agentManager.isRunning && agentManager.isAgentBLEConnected { return "已连蓝牙" }
        if agentManager.isRunning { return "BLE 未连接" }
        if agentManager.isInstalled { return "未运行" }
        return "未装 Agent"
    }

    private func workModeName(_ mode: Int) -> String {
        switch mode {
        case 0: return "Mode 0"
        case 1: return "Mode 1"
        case 2: return "Mode 2"
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
