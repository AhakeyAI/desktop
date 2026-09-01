import AhaKeyConfigShared
import SwiftUI

struct DeviceInfoView: View {
    @ObservedObject var runtimeStore: AhaKeyStudioRuntimeClient
    @StateObject private var runtimeServiceManager = RuntimeServiceManager.shared
    @State private var showRuntimeLog = false
    @State private var runtimeLogPanel = 0
    @State private var logPanelContentTick = 0

    var body: some View {
        Form {
            // MARK: - 设备信息
            Section {
                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("电量", comment: ""), value: String(format: NSLocalizedString("%d%%", comment: ""), runtimeStore.batteryLevel))
                    Divider()
                    infoCell(NSLocalizedString("固件", comment: ""), value: runtimeStore.firmwareVersion ?? "—")
                    Divider()
                    infoCell(NSLocalizedString("设备名", comment: ""), value: runtimeStore.deviceName ?? "—")
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("工作模式", comment: ""), value: workModeName(runtimeStore.workMode))
                    Divider()
                    infoCell(NSLocalizedString("灯光", comment: ""), value: lightModeName(runtimeStore.lightMode))
                    Divider()
                    infoCell(NSLocalizedString("协议模式", comment: ""), value: runtimeStore.isConnected ? protocolModeLabel(runtimeStore.protocolMode) : "—")
                }
                .frame(height: 50)

                HStack(spacing: 0) {
                    infoCell(NSLocalizedString("型号", comment: ""), value: AhaKeyDevicePresentation.modelName)
                    Divider()
                    infoCell(NSLocalizedString("设备编号", comment: ""), value: runtimeStore.deviceKey ?? "—")
                    Divider()
                    infoCell(NSLocalizedString("配置通道", comment: ""), value: runtimeStore.isConnected ? runtimeStore.configurationTransportLabel : "—")
                }
                .frame(height: 50)
            } header: {
                Text(NSLocalizedString("设备信息", comment: ""))
            }

            // MARK: - 拨杆状态
            Section {
                HStack {
                    Text(NSLocalizedString("当前档位", comment: ""))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(liveSwitchState.map { $0 == 0 ? Color.green : Color.indigo } ?? Color.gray.opacity(0.4))
                            .frame(width: 10, height: 10)
                            .animation(.easeInOut(duration: 0.1), value: liveSwitchState)
                        Text(liveSwitchState.map(switchStateLabel) ?? "—")
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
                                .fill(runtimeServiceManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(NSLocalizedString("LED 跟随 IDE 状态", comment: ""))
                            Text(agentBluetoothShortLabel())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            hookBadge("Claude", installed: runtimeServiceManager.claudeHooksInstalled)
                            hookBadge("Cursor", installed: runtimeServiceManager.cursorHooksInstalled)
                            hookBadge("Codex", installed: runtimeServiceManager.codexHooksInstalled)
                            hookBadge("Kimi", installed: runtimeServiceManager.kimiHooksInstalled)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    if runtimeServiceManager.isInstalled {
                        Button(runtimeServiceManager.isRunning ? NSLocalizedString("停止", comment: "") : NSLocalizedString("启动", comment: "")) {
                            if runtimeServiceManager.isRunning {
                                runtimeServiceManager.stop()
                            } else {
                                runtimeServiceManager.start()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(NSLocalizedString("启动或停止 AhaKey Runtime 后台服务。", comment: ""))

                        Button(NSLocalizedString("卸载", comment: ""), role: .destructive) {
                            runtimeServiceManager.uninstall()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        HStack(spacing: 8) {
                            if runtimeServiceManager.isRuntimeOperationInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Button(NSLocalizedString("安装并启用", comment: "")) {
                                runtimeServiceManager.install()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(runtimeServiceManager.isRuntimeOperationInProgress)
                        }
                    }
                }

                if runtimeServiceManager.isInstalled {
                    HStack(spacing: 10) {
                        Button(NSLocalizedString("查看日志", comment: "")) {
                            showRuntimeLog.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Spacer()

                        if runtimeServiceManager.claudeHooksInstalled {
                            Button(NSLocalizedString("移除 Claude Hooks", comment: "")) { runtimeServiceManager.removeClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Claude Hooks", comment: "")) { runtimeServiceManager.installClaudeHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if runtimeServiceManager.cursorHooksInstalled {
                            Button(NSLocalizedString("移除 Cursor Hooks", comment: "")) { runtimeServiceManager.removeCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Cursor Hooks", comment: "")) { runtimeServiceManager.installCursorHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if runtimeServiceManager.codexHooksInstalled {
                            Button(NSLocalizedString("移除 Codex Hooks", comment: "")) { runtimeServiceManager.removeCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Codex Hooks", comment: "")) { runtimeServiceManager.installCodexHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                        if runtimeServiceManager.kimiHooksInstalled {
                            Button(NSLocalizedString("移除 Kimi Hooks", comment: "")) { runtimeServiceManager.removeKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        } else {
                            Button(NSLocalizedString("安装 Kimi Hooks", comment: "")) { runtimeServiceManager.installKimiHooksOnly() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("LED 状态同步 · Hook 联动", comment: ""))
            } footer: {
                if !runtimeServiceManager.isRuntimeBinaryPresentInBundle {
                    Text(NSLocalizedString("发版包内未包含后台服务可执行文件，无法使用 AhaKey Runtime。请用完整「AhaKey Studio.app」或联系开发者。", comment: ""))
                        .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showRuntimeLog) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("诊断日志", comment: ""))
                            .font(.headline)
                        Spacer()
                        Button(NSLocalizedString("关闭", comment: "")) { showRuntimeLog = false }
                    }
                    Picker(NSLocalizedString("内容", comment: ""), selection: $runtimeLogPanel) {
                        Text(NSLocalizedString("AhaKey Runtime 主日志（兼容标识：ahakeyconfig-agent）", comment: "")).tag(0)
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
                            runtimeServiceManager.refresh()
                        }
                        if runtimeLogPanel == 3 {
                            Button(NSLocalizedString("合并 CLI + IDE 终端白名单", comment: "")) {
                                let a = runtimeServiceManager.mergeUserCursorCliConfigForShellAutoApprove()
                                let b = runtimeServiceManager.mergeUserCursorPermissionsJsonForAgentTUI()
                                runtimeServiceManager.runtimeUserAlert = a + "\n\n——\n\n" + b
                            }
                            .help(NSLocalizedString("写 cli-config（CLI）与 permissions.json 的 terminalAllowlist（Cursor TUI「Not in allowlist」层）；分见官方文档。均先备份为 .ahakey.bak。", comment: ""))
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
                Toggle(isOn: $runtimeServiceManager.kimiTUIAdapterEnabled) {
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

            // MARK: - 配置连接状态
            Section {
                CompatLabeledContent(NSLocalizedString("配置通道", comment: "")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(runtimeStore.isUSBConfigurationActive ? Color.green : Color.blue)
                            .frame(width: 8, height: 8)
                        Text(runtimeStore.configurationTransportLabel)
                    }
                }
                CompatLabeledContent(NSLocalizedString("连接", comment: "")) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill((runtimeStore.isConnected || runtimeServiceManager.isRuntimeBLEConnected) ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(connectionStatusText())
                    }
                }
                CompatLabeledContent(NSLocalizedString("设备名", comment: "")) {
                    Text(runtimeStore.deviceName ?? "—")
                        .textSelection(.enabled)
                }
            } header: {
                Text(NSLocalizedString("配置连接状态", comment: ""))
            }

            // MARK: - 通信日志
            Section {
                // 独立 Store：日志 append 只刷新这个子视图，不波及观察 store 的其它 View
                CommLogSection(logStore: runtimeStore.logStore)
            } header: {
                Text(NSLocalizedString("通信日志", comment: ""))
            }
        }
        // 「设备信息」在 sheet 中展示时，父视图的 `.alert` 往往不会置顶显示，导致 Hooks 安装/报错像「无反应」。在此重复绑定以确保可见。
        .alert(NSLocalizedString("AhaKey Runtime", comment: ""), isPresented: Binding(
            get: { runtimeServiceManager.runtimeUserAlert != nil },
            set: { if !$0 { runtimeServiceManager.runtimeUserAlert = nil } }
        )) {
            Button(NSLocalizedString("好", comment: ""), role: .cancel) {
                runtimeServiceManager.runtimeUserAlert = nil
            }
        } message: {
            Text(runtimeServiceManager.runtimeUserAlert ?? "")
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

    private func switchStateLabel(_ state: Int) -> String {
        state == 0 ? NSLocalizedString("自动批准", comment: "") : NSLocalizedString("手动批准", comment: "")
    }

    private var liveSwitchState: Int? {
        LiveKeyboardSwitchStateResolver.resolve(
            optimisticOverride: runtimeStore.optimisticSwitchOverride,
            appIsConnected: runtimeStore.isConnected,
            appState: runtimeStore.currentConnectionSwitchState,
            agentState: runtimeStore.agentSwitchState
        )
    }

    /// 连接状态的用户视角表述：Runtime 在线 + Agent 连接组合。
    private func connectionStatusText() -> String {
        if runtimeStore.isConnected { return NSLocalizedString("已连接键盘（Runtime 在线）", comment: "") }
        if runtimeStore.isOnline { return NSLocalizedString("Runtime 在线 · 未连接键盘", comment: "") }
        return NSLocalizedString("Runtime 离线（未连接）", comment: "")
    }

    private func agentBluetoothShortLabel() -> String {
        if runtimeServiceManager.isRunning && runtimeServiceManager.isRuntimeBLEConnected { return NSLocalizedString("已连蓝牙", comment: "") }
        if runtimeServiceManager.isRunning { return NSLocalizedString("BLE 未连接", comment: "") }
        if runtimeServiceManager.isInstalled { return NSLocalizedString("未运行", comment: "") }
        return NSLocalizedString("未装后台服务", comment: "")
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
        case .legacyBaseOnly: return NSLocalizedString("旧版基础功能 (无任务 GIF)", comment: "")
        case .current: return NSLocalizedString("当前协议 (v3)", comment: "")
        case .restrictedUnknown: return NSLocalizedString("受限未知", comment: "")
        }
    }

    @ViewBuilder
    private var logPanelContent: some View {
        switch runtimeLogPanel {
        case 0:
            Text(runtimeServiceManager.readLog())
        case 1:
            Text(runtimeServiceManager.readPermissionRequestLog())
        case 2:
            Text(runtimeServiceManager.readUserCursorHooksJsonForDisplay())
        case 3:
            Text(runtimeServiceManager.readUserCursorCliConfigForDisplay())
        case 4:
            Text(runtimeServiceManager.readUserCodexConfigForDisplay())
        case 5:
            Text(runtimeServiceManager.readCodexHookLog())
        case 6:
            Text(runtimeServiceManager.readUserKimiConfigForDisplay())
        default:
            Text("")
        }
    }
}

// MARK: - 通信日志（观察独立的 BLELogStore）

/// 通信日志区：内存诊断级日志列表 + 复制/清空 + 临时详细级（TX/RX 抓包）开关。
/// 只观察 `BLELogStore`，日志刷新不再触发整个 DeviceInfoView / 观察 store 的 View 重绘。
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
