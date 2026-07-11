import SwiftUI

enum DeviceInfoChrome {
    case systemForm
    case settingsCards
}

/// 设备信息与系统控制（Agent / 我的设备共用）。
struct DeviceInfoView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    var chrome: DeviceInfoChrome = .systemForm

    @StateObject private var agentManager = AgentManager.shared
    @State private var isEditingName = false
    @State private var editableName = ""
    @State private var showAgentLog = false
    @State private var agentLogPanel = 0
    @State private var logPanelContentTick = 0
    @State private var showAgentRequiredForAgentBLE = false
    @State private var showDiagnosticsExpanded = false

    var body: some View {
        Group {
            switch chrome {
            case .systemForm:
                formBody
            case .settingsCards:
                settingsCardsBody
            }
        }
        .alert("需要先安装 Agent", isPresented: $showAgentRequiredForAgentBLE) {
            Button("好", role: .cancel) {}
        } message: {
            Text("将蓝牙交给 `ahakeyconfig-agent` 前，请先在下方完成「安装并启用」，生成 LaunchAgent。")
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
        .sheet(isPresented: $showAgentLog) {
            agentLogSheet
        }
    }

    private var formBody: some View {
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
            } header: {
                Text("拨杆档位")
            }

            // MARK: - LED 状态同步
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(agentManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("LED 跟随 IDE 状态")
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
                Text("LED 状态同步 · Hook 联动")
            } footer: {
                if !agentManager.isAgentBinaryPresentInBundle {
                    Text("发版包内未包含 ahakeyconfig-agent，无法使用守护进程。请用完整「AhaKey Studio.app」或联系开发者。")
                        .foregroundStyle(.orange)
                } else if agentManager.isInstalled, agentManager.bluetoothConnectionOwner == .ahaKeyStudio, !agentManager.isRunning {
                    Text("已由本 App 占用蓝牙：要让 Agent 接管，请将「蓝牙连接」选为 ahakeyconfig-agent。")
                        .foregroundStyle(.secondary)
                }
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
                CompatLabeledContent("连接") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(bleManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(bleManager.bleConnectionStatus)
                    }
                }
                CompatLabeledContent("设备名") {
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
                CompatLabeledContent("UUID") {
                    Text(bleManager.bleDeviceUUID)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
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
                        .onChange(of: bleManager.commLog.count) { _ in
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
    }

    // MARK: - Settings Cards

    private var settingsCardsBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deviceCard(title: "基本设置") {
                    basicSettingsCardContent
                }
                deviceCard(title: "蓝牙连接") {
                    bluetoothOwnerCardContent
                }
                deviceCard(title: "设备信息") {
                    deviceInfoCardContent
                }
                deviceCard(title: "系统 · Agent") {
                    agentSystemCardContent
                }
                DisclosureGroup(isExpanded: $showDiagnosticsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        if bleManager.isConnected {
                            Text("LED 测试")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                            ledTestGrid
                        }
                        Text("通信日志")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        communicationLogBlock
                    }
                    .padding(.top, 8)
                } label: {
                    Text("更多诊断")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                }
                .padding(14)
                .background(cardBackground)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AhakeySettingsTheme.contentBackground.ignoresSafeArea())
    }

    private func deviceCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AhakeySettingsTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AhakeySettingsTheme.divider, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var basicSettingsCardContent: some View {
        if isEditingName {
            HStack(spacing: 8) {
                TextField("最长 15 字节", text: $editableName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { submitNameChange() }
                Button("保存") { submitNameChange() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("取消") { isEditingName = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            HStack {
                Label(bleManager.deviceName ?? "AhaKey", systemImage: "keyboard")
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Spacer()
                if bleManager.isConnected {
                    Button {
                        editableName = bleManager.deviceName ?? ""
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("修改设备名称")
                }
            }
        }

        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(bleManager.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(bleManager.bleConnectionStatus)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .lineLimit(2)

            Spacer(minLength: 12)

            if !bleManager.isConnected {
                Button(bleManager.isScanning ? "扫描中…" : "连接设备") {
                    bleManager.userInitiatedConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(bleManager.isScanning || agentManager.bluetoothConnectionOwner == .agentDaemon)
                .help(agentManager.bluetoothConnectionOwner == .agentDaemon
                      ? "当前由 Agent 占用蓝牙。请先在「蓝牙连接」切到 AhaKey Studio。"
                      : "本 App 主动连接键盘。")
            } else {
                Button("查询状态") { bleManager.queryDeviceStatus() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                Button("断开", role: .destructive) { bleManager.disconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var bluetoothOwnerCardContent: some View {
        Text("同一时间只能由本 App 或 Agent 其中之一连接键盘。")
            .font(.system(size: 12))
            .foregroundStyle(AhakeySettingsTheme.secondaryText)
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
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text(owner == .ahaKeyStudio
                             ? "改键、LCD、同步、本机灯效测试"
                             : "Hook、灯条状态、拨杆查询")
                            .font(.caption2)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? AhakeySettingsTheme.accentBlue.opacity(0.18) : AhakeySettingsTheme.controlFill)
                    )
                }
                .buttonStyle(.plain)
                .disabled(disableAgent)
            }
        }
        Text("\(bleManager.isConnected ? "本 App 已连接" : "本 App 未连接") · \(agentBluetoothStatusText())")
            .font(.system(size: 12))
            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
    }

    @ViewBuilder
    private var deviceInfoCardContent: some View {
        settingsInfoRow("电量", "\(bleManager.batteryLevel)%")
        settingsInfoRow("固件", "v\(bleManager.firmwareMainVersion).\(bleManager.firmwareSubVersion)")
        settingsInfoRow("工作模式", workModeName(bleManager.workMode))
        settingsInfoRow("灯光模式", lightModeName(bleManager.lightMode))
        settingsInfoRow("信号强度", "\(bleManager.signalStrength) dBm")
        HStack {
            Text("拨杆档位")
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(bleManager.switchState == 0 ? Color.green : Color.indigo)
                    .frame(width: 8, height: 8)
                Text(switchStateLabel(bleManager.switchState))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
            }
        }
        settingsInfoRow("设备 UUID", bleManager.bleDeviceUUID)
        HStack {
            Text("特征就绪")
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            Spacer()
            HStack(spacing: 8) {
                charBadge("DATA", ready: bleManager.dataCharReady)
                charBadge("CMD", ready: bleManager.commandCharReady)
                charBadge("NOTIFY", ready: bleManager.notifyCharReady)
            }
        }
    }

    @ViewBuilder
    private var agentSystemCardContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(agentManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("LED 跟随 IDE 状态")
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text(agentBluetoothShortLabel())
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
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
                    if agentManager.isRunning { agentManager.stop() } else { agentManager.start() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(agentManager.bluetoothConnectionOwner == .ahaKeyStudio)
                Button("卸载", role: .destructive) {
                    agentManager.uninstall(bleManager: bleManager)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("安装并启用") { agentManager.install() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(agentManager.isAgentOperationInProgress)
            }
        }

        if agentManager.isInstalled {
            HStack {
                Button("查看诊断日志") { showAgentLog = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Spacer()
            }
        }

        if !agentManager.isAgentBinaryPresentInBundle {
            Text("发版包内未包含 ahakeyconfig-agent，无法使用守护进程。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var ledTestGrid: some View {
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
    }

    private var communicationLogBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(bleManager.commLog) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTime)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                                    .frame(width: 80, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(entry.isError ? .red : AhakeySettingsTheme.secondaryText)
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 150)
                .background(AhakeySettingsTheme.controlFill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: bleManager.commLog.count) { _ in
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
                Button("清空") { bleManager.clearLog() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.top, 4)
        }
    }

    private func settingsInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var agentLogSheet: some View {
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
                Text("~/.codex/config.toml").tag(4)
                Text("Codex Hook（codex-hook.log）").tag(5)
                Text("~/.kimi/config.toml").tag(6)
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
