import SwiftUI

struct AhaKeyAgentStatusPane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var agentManager = AgentManager.shared
    @State private var showAdvanced = false

    private var isLinkageReady: Bool {
        agentManager.isInstalled
            && agentManager.isRunning
            && agentManager.bluetoothConnectionOwner == .agentDaemon
    }

    private var hasAnyHook: Bool {
        agentManager.claudeHooksInstalled
            || agentManager.cursorHooksInstalled
            || agentManager.codexHooksInstalled
            || agentManager.kimiHooksInstalled
    }

    private var readinessDetail: String {
        if isLinkageReady {
            if hasAnyHook {
                return "守护进程运行中，蓝牙由 Agent 占用，Hook 已就绪。"
            }
            return "守护与蓝牙已就绪。建议安装 Cursor Hook，IDE 才能驱动灯条。"
        }
        var missing: [String] = []
        if !agentManager.isInstalled { missing.append("未安装守护进程") }
        else if !agentManager.isRunning { missing.append("守护进程未运行") }
        if agentManager.bluetoothConnectionOwner != .agentDaemon {
            missing.append("蓝牙未交给 Agent")
        }
        return missing.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("联动")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("先启用联动，再日常用助手对话；改键请到硬件设备。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            readinessCard
            bluetoothCard
            hooksOverviewCard

            AhaKeySettingsDisclosureSection(
                title: "高级设置",
                subtitle: "守护进程细节、其它 Hook、Mode 与诊断",
                isExpanded: $showAdvanced
            ) {
                daemonDetailCard
                otherHooksCard
                modeSummaryCard
                diagnosticsCard
            }
        }
        .onAppear { agentManager.refresh() }
    }

    private var readinessCard: some View {
        AhakeySettingsCard(sectionTitle: "联动就绪") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isLinkageReady ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(isLinkageReady ? "已就绪" : "未就绪")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                    }

                    Text(readinessDetail)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if !isLinkageReady {
                    Button {
                        enableLinkage()
                    } label: {
                        HStack(spacing: 6) {
                            Text("一键启用联动")
                            if agentManager.isAgentOperationInProgress {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(agentManager.isAgentOperationInProgress || !agentManager.isAgentBinaryPresentInBundle)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var bluetoothCard: some View {
        AhakeySettingsCard(sectionTitle: "蓝牙占用") {
            VStack(alignment: .leading, spacing: 10) {
                Text("日常写代码选 Agent；改键前切回 Studio。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Picker("", selection: Binding(
                    get: { agentManager.bluetoothConnectionOwner },
                    set: { agentManager.setBluetoothConnectionOwner($0, bleManager: bleManager) }
                )) {
                    ForEach(BluetoothConnectionOwner.allCases) { owner in
                        Text(owner.title).tag(owner)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var hooksOverviewCard: some View {
        AhakeySettingsCard(sectionTitle: "IDE Hooks") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        hookBadge("Claude", installed: agentManager.claudeHooksInstalled)
                        hookBadge("Cursor", installed: agentManager.cursorHooksInstalled)
                        hookBadge("Codex", installed: agentManager.codexHooksInstalled)
                        hookBadge("Kimi", installed: agentManager.kimiHooksInstalled)
                    }
                    Text("最常用 Cursor；其它 IDE 见高级设置")
                        .font(.system(size: 11))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                }

                Spacer(minLength: 12)

                Button(agentManager.cursorHooksInstalled ? "重装 Cursor Hook" : "安装 Cursor Hook") {
                    agentManager.installCursorHooksOnly()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(agentManager.isAgentOperationInProgress)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var daemonDetailCard: some View {
        AhakeySettingsCard(sectionTitle: "守护进程") {
            statusRow("安装", value: agentManager.isInstalled ? "已安装" : "未安装", ok: agentManager.isInstalled)
            AhakeySettingsCardDivider()
            statusRow("运行", value: agentManager.isRunning ? "运行中" : "未运行", ok: agentManager.isRunning)
            AhakeySettingsCardDivider()
            statusRow("Agent 蓝牙", value: agentManager.isAgentBLEConnected ? "已连接键盘" : "未连接", ok: agentManager.isAgentBLEConnected)

            HStack(spacing: 10) {
                if agentManager.isInstalled {
                    Button(agentManager.isRunning ? "停止" : "启动") {
                        if agentManager.isRunning {
                            agentManager.stop()
                        } else {
                            agentManager.start()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(agentManager.isAgentOperationInProgress)
                    Button("卸载", role: .destructive) {
                        agentManager.uninstall(bleManager: bleManager)
                    }
                    .buttonStyle(.bordered)
                    .disabled(agentManager.isAgentOperationInProgress)
                } else {
                    Button("安装并启用") {
                        agentManager.install()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(agentManager.isAgentOperationInProgress || !agentManager.isAgentBinaryPresentInBundle)
                }
                if agentManager.isAgentOperationInProgress {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var otherHooksCard: some View {
        AhakeySettingsCard(sectionTitle: "其它 IDE Hooks") {
            HStack(spacing: 8) {
                Button(agentManager.claudeHooksInstalled ? "重装 Claude" : "安装 Claude") {
                    agentManager.installClaudeHooksOnly()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(agentManager.codexHooksInstalled ? "重装 Codex" : "安装 Codex") {
                    agentManager.installCodexHooksOnly()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(agentManager.kimiHooksInstalled ? "重装 Kimi" : "安装 Kimi") {
                    agentManager.installKimiHooksOnly()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
            .disabled(agentManager.isAgentOperationInProgress)
        }
    }

    private var modeSummaryCard: some View {
        AhakeySettingsCard(sectionTitle: "Mode · 批准") {
            statusRow("工作模式", value: "Mode \(bleManager.workMode)", ok: true)
            AhakeySettingsCardDivider()
            statusRow(
                "拨杆",
                value: bleManager.switchState == 0 ? "自动批准" : "手动批准",
                ok: bleManager.switchState == 0
            )
            Button {
                StudioNavigationRouter.shared.selectSettingsTab(.hardware)
                NotificationCenter.default.post(
                    name: .ahaKeyStudioSelectPart,
                    object: nil,
                    userInfo: [StudioNavigationUserInfoKey.part: AhaKeyStudioPart.toggleSwitch.rawValue]
                )
            } label: {
                rowLabel("在硬件中查看拨杆", detail: "只读上报；物理拨动才改变档位")
            }
            .buttonStyle(.plain)
        }
    }

    private var diagnosticsCard: some View {
        AhakeySettingsCard(sectionTitle: "诊断入口") {
            Button {
                StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
            } label: {
                rowLabel("打开我的设备", detail: "改名、电量、系统控制与完整诊断")
            }
            .buttonStyle(.plain)
            AhakeySettingsCardDivider()
            Button {
                agentManager.refresh()
                _ = agentManager.readLog()
                StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
            } label: {
                rowLabel("刷新并打开设备详情", detail: "在设备页「系统 · Agent」查看诊断日志")
            }
            .buttonStyle(.plain)
        }
    }

    private func enableLinkage() {
        agentManager.refresh()
        if !agentManager.isInstalled {
            agentManager.install()
            return
        }
        agentManager.setBluetoothConnectionOwner(.agentDaemon, bleManager: bleManager)
        if !agentManager.isRunning {
            agentManager.start()
        }
    }

    private func statusRow(_ title: String, value: String, ok: Bool) -> some View {
        HStack {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private func hookBadge(_ title: String, installed: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(installed ? Color.green : AhakeySettingsTheme.tertiaryText)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
    }

    private func rowLabel(_ title: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text(detail)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }
}
