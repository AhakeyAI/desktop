import SwiftUI
import AhaKeyConfigShared

struct DeviceInfoView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @ObservedObject var inspectorSession: StudioInspectorSession
    @ObservedObject private var diagnosticsStore: BLEDeviceDiagnosticsStore

    init(bleManager: AhaKeyBLEManager, inspectorSession: StudioInspectorSession) {
        self.inspectorSession = inspectorSession
        self.bleManager = bleManager
        self.diagnosticsStore = bleManager.diagnosticsStore
    }

    @StateObject private var agentManager = AgentManager.shared
    @State private var isEditingName = false
    @State private var editableName = ""
    @State private var nameError: String?
    @State private var nameReceipt: String?
    @State private var isSubmittingName = false
    @State private var nameTask: Task<Void, Never>?
    @AppStorage("deviceInfo.selectedHookClients") private var selectedHookClientKeys = ""
    @State private var showsHookPicker = false
    @State private var hookSearch = ""
    @State private var pendingHookRemoval: StudioHookClient?
    @State private var expandedHookClient: StudioHookClient?
    @State private var hookVerifications: [StudioHookClient: AgentManager.HookVerification] = [:]
    @State private var detectedHarnesses: Set<String> = []
    @State private var showsAdvancedTools = false
    @State private var advancedTool = AdvancedTool.ble
    @State private var hookLogSource = HookLogSource.installation
    @State private var hookLogText = ""

    private enum AdvancedTool: Hashable { case ble, configuration, communication, hookLog }
    private enum HookLogSource: Hashable { case installation, agent, approval, codex, cursorHooks, cursorCLI, codexConfig, kimi }
    @State private var showAgentRequiredForAgentBLE = false
    @State private var firmwareCatalogReadingConnection: DeviceInfoFirmwareReadback.Connection?
    private var isReadingFirmwareCatalog: Bool { firmwareCatalogReadingConnection != nil }
    @State private var firmwareCatalogError: String?
    @State private var configurationReadError: String?
    @State private var agentRSSI: Int?

    private var readsAgentRSSI: Bool {
        !bleManager.isConnected && agentManager.bluetoothConnectionOwner == .agentDaemon &&
            agentManager.isAgentBLEConnected
    }

    private var agentRSSITarget: String? {
        readsAgentRSSI ? (bleManager.deviceUUIDForDisplay ?? "") : nil
    }

    private var signalLabel: String {
        let value = bleManager.isConnected ? diagnosticsStore.snapshot.signalStrength : (readsAgentRSSI ? agentRSSI : nil)
        return value.flatMap { (-127 ... -1).contains($0) ? "\($0) dBm" : nil } ?? NSLocalizedString("未读取", comment: "")
    }

    var body: some View {
        Form {
            Section { deviceSummary }
            connectionSection
            hookSection
            advancedSection
        }
        .formStyle(.grouped)
        .disabled(isSubmittingName)
        .onAppear { bleManager.setDiagnosticsWindowVisible(true) }
        .task(id: agentRSSITarget) {
            agentRSSI = nil
            guard let target = agentRSSITarget else { return }
            while !Task.isCancelled {
                let value = await agentManager.readConnectedKeyboardRSSI()
                guard !Task.isCancelled, agentRSSITarget == target else { return }
                agentRSSI = value
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .task(id: bleManager.deviceInfoFirmwareReadbackState.connection) {
            let connection = bleManager.deviceInfoFirmwareReadbackState.connection
            guard connection.connected, firmwareCatalogReadingConnection != connection,
                  !bleManager.deviceInfoFirmwareReadbackState.profileKnown else { return }
            firmwareCatalogReadingConnection = connection
            firmwareCatalogError = nil
            defer {
                if firmwareCatalogReadingConnection == connection { firmwareCatalogReadingConnection = nil }
            }
            do {
                _ = try await DeviceInfoFirmwareReadback.run(connection: connection,
                    state: { bleManager.deviceInfoFirmwareReadbackState },
                    read: { _ = try await bleManager.readFirmwareCapabilityProfile() })
            } catch is CancellationError {
                // Closing the sheet or moving to another connection revokes this probe.
            } catch {
                guard bleManager.deviceInfoFirmwareReadbackState.connection == connection else { return }
                firmwareCatalogError = error.localizedDescription
            }
        }
        .onDisappear {
            nameTask?.cancel()
            bleManager.setDiagnosticsWindowVisible(false)
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

    }

    // MARK: - Components

    private var deviceSummary: some View {
        let hardware = FirmwareIdentityDisplay.hardwareRevision(catalogKey: bleManager.firmwareCatalogKeyForDisplay)
        let firmware = bleManager.firmwareVersionForDisplay.map {
            String(format: NSLocalizedString("固件 %@", comment: ""), $0)
        }
        let workMode = bleManager.workModeForDisplay.map(workModeName)
        let identity = [hardware, firmware, workMode].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(bleManager.deviceNameForDisplay ?? NSLocalizedString("未读取设备名", comment: ""))
                    .font(.headline)
                if !identity.isEmpty {
                    Text(identity).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(bleManager.batteryLevelForDisplay.map { String(format: NSLocalizedString("电量 %d%%", comment: ""), $0) }
                     ?? NSLocalizedString("电量未读取", comment: ""))
                    .monospacedDigit()
                Text(signalLabel).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private var currentConnectionOwner: BluetoothConnectionOwner {
        bleManager.isConnected ? .ahaKeyStudio : agentManager.bluetoothConnectionOwner
    }

    private var connectionIsActive: Bool {
        currentConnectionOwner == .ahaKeyStudio ? bleManager.isConnected : agentManager.isAgentBLEConnected
    }

    private var connectionStatus: String {
        if connectionIsActive { return NSLocalizedString("已连接", comment: "") }
        if currentConnectionOwner == .ahaKeyStudio && bleManager.isScanning {
            return NSLocalizedString("扫描中…", comment: "")
        }
        if currentConnectionOwner == .agentDaemon && !agentManager.isInstalled {
            return NSLocalizedString("后台服务未安装", comment: "")
        }
        return NSLocalizedString("未连接", comment: "")
    }

    private func connectionTitle(_ owner: BluetoothConnectionOwner) -> LocalizedStringKey {
        owner == .ahaKeyStudio ? "Studio 直连" : "后台联动"
    }

    private func connectionPurpose(_ owner: BluetoothConnectionOwner) -> LocalizedStringKey {
        owner == .ahaKeyStudio
            ? "配置键盘。用于改按键、调灯和上传屏幕画面。"
            : "日常使用。同步任务状态，支持的工具可用拨杆审批。"
    }

    private var connectionSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionTitle(currentConnectionOwner)).fontWeight(.semibold)
                    Text(connectionPurpose(currentConnectionOwner))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if agentManager.agentIsSystemDisabled && currentConnectionOwner == .agentDaemon {
                        Text("后台服务已被系统停用。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                Menu("切换方式") {
                    connectionChoice(.ahaKeyStudio, subtitle: "改按键、调灯、上传画面")
                    connectionChoice(.agentDaemon, subtitle: agentManager.agentIsSystemDisabled &&
                        agentManager.bluetoothConnectionOwner == .agentDaemon
                        ? "启用后台服务" : "同步任务状态、拨杆审批")
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(agentManager.isAgentOperationInProgress)
            }
            .padding(.vertical, 3)
        } header: {
            HStack(spacing: 8) {
                Text("蓝牙连接")
                statusIndicator(connectionStatus, active: connectionIsActive)
            }
        }
        .alert("需要安装后台服务", isPresented: $showAgentRequiredForAgentBLE) {
            Button("取消", role: .cancel) {}
            Button("安装并切换") { selectConnection(.agentDaemon, prepareService: true) }
        } message: {
            Text("后台联动需要 Studio 的本机后台服务。")
        }
    }

    private func connectionChoice(_ owner: BluetoothConnectionOwner, subtitle: LocalizedStringKey) -> some View {
        let alreadyConnected = owner == .ahaKeyStudio
            ? bleManager.isConnected || bleManager.isScanning
            : agentManager.isRunning && !agentManager.agentIsSystemDisabled
        return Button {
            selectConnection(owner)
        } label: {
            Label {
                Text(connectionTitle(owner)) + Text(" · ") + Text(subtitle)
            } icon: {
                if currentConnectionOwner == owner { Image(systemName: "checkmark") }
            }
        }
        .disabled(currentConnectionOwner == owner && agentManager.bluetoothConnectionOwner == owner && alreadyConnected)
    }

    private func selectConnection(_ owner: BluetoothConnectionOwner, prepareService: Bool = false) {
        if owner == .agentDaemon && !agentManager.isInstalled {
            guard prepareService else { showAgentRequiredForAgentBLE = true; return }
            guard agentManager.prepareBackgroundService() else { return }
        }
        guard agentManager.bluetoothConnectionOwner == owner else {
            agentManager.setBluetoothConnectionOwner(owner, bleManager: bleManager)
            return
        }
        switch owner {
        case .ahaKeyStudio:
            bleManager.userInitiatedConnect()
        case .agentDaemon:
            if agentManager.agentIsSystemDisabled {
                agentManager.enableAgentAndRetry(bleManager: bleManager)
            } else {
                agentManager.start()
            }
        }
    }

    private func statusIndicator(_ label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var savedHookClients: Set<String> {
        Set(selectedHookClientKeys.split(separator: ",").map(String.init))
    }

    private var visibleHookClients: [StudioHookClient] {
        StudioHookClient.allCases.filter {
            savedHookClients.contains($0.rawValue) || agentManager.hasHookConfiguration($0)
        }
    }

    private func setHookClient(_ client: StudioHookClient, visible: Bool) {
        var selection = savedHookClients
        if visible { selection.insert(client.rawValue) }
        else { selection.remove(client.rawValue) }
        selectedHookClientKeys = selection.sorted().joined(separator: ",")
    }

    private var hookSection: some View {
        Section {
            if visibleHookClients.isEmpty {
                Text("点「添加」选择要同步的工具。").foregroundStyle(.secondary)
            }
            ForEach(visibleHookClients) { client in hookClientRow(client) }
        } header: {
            HStack(spacing: 8) {
                Text("状态钩子")
                statusIndicator(
                    NSLocalizedString(agentManager.isRunning ? "后台运行中" : "后台未运行", comment: ""),
                    active: agentManager.isRunning
                )
                Spacer()
                Button {
                    hookSearch = ""
                    detectedHarnesses = StudioHarnessCatalog.detect()
                    showsHookPicker.toggle()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .popover(isPresented: $showsHookPicker, arrowEdge: .top) { hookPicker }
            }
        } footer: {
            if !agentManager.isAgentBinaryPresentInBundle {
                Text("应用包缺少 Agent，请重新安装完整的 AhaKey Studio。").foregroundStyle(.orange)
            }
        }
        .onAppear { detectedHarnesses = StudioHarnessCatalog.detect() }
        .confirmationDialog("卸载状态钩子？", isPresented: Binding(
            get: { pendingHookRemoval != nil },
            set: { if !$0 { pendingHookRemoval = nil } }
        ), titleVisibility: .visible, presenting: pendingHookRemoval) { client in
            Button("卸载", role: .destructive) {
                setHookClient(client, visible: true)
                agentManager.removeHook(client)
            }
            Button("取消", role: .cancel) {}
        } message: { client in
            Text("卸载后，Studio 将停止同步 \(client.name) 的任务状态。")
        }
        .task(id: visibleHookClients) {
            while !Task.isCancelled {
                if agentManager.codexHooksInstalled { agentManager.refreshCodexHookInstallationStatus() }
                let checks = Dictionary(uniqueKeysWithValues: visibleHookClients.compactMap { client in
                    agentManager.hookVerification(client).map { (client, $0) }
                })
                if hookVerifications != checks { hookVerifications = checks }
                do { try await Task.sleep(for: .seconds(3)) }
                catch { return }
            }
        }
    }

    private var hookPicker: some View {
        let query = hookSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let supported = StudioHookClient.allCases.filter {
            !visibleHookClients.contains($0) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }.sorted {
            detectedHarnesses.contains($0.name) && !detectedHarnesses.contains($1.name)
        }
        let catalog = query.isEmpty ? StudioHarnessCatalog.featured : StudioHarnessCatalog.featured + StudioHarnessCatalog.other
        let pending = catalog.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return VStack(alignment: .leading, spacing: 8) {
            TextField("搜索工具", text: $hookSearch)
                .textFieldStyle(.roundedBorder)
            if supported.isEmpty && pending.isEmpty {
                Text("没有匹配的工具").font(.caption).foregroundStyle(.secondary).padding(.vertical, 9)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(supported) { client in
                            Button {
                                setHookClient(client, visible: true)
                                showsHookPicker = false
                            } label: {
                                toolOption(client.name, note: detectedHarnesses.contains(client.name)
                                    ? NSLocalizedString("已检测到", comment: "") : NSLocalizedString("未检测到", comment: ""),
                                           trailing: "添加", iconAsset: client.rawValue)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(pending) { entry in
                            toolOption(
                                entry.name, note: NSLocalizedString(entry.integrationNote ?? "待适配", comment: ""),
                                trailing: "待适配", iconAsset: entry.iconAsset
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(supported.count + pending.count) * 43, 270))
            }
        }
        .padding(10)
        .frame(width: 340)
    }

    private func toolOption(
        _ name: String, note: String, trailing: LocalizedStringKey, iconAsset: String?
    ) -> some View {
        HStack(spacing: 8) {
            StudioStatusHookIcon(assetName: iconAsset)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }

    private func hookClientRow(_ client: StudioHookClient) -> some View {
        let configured = agentManager.hasHookConfiguration(client)
        let detected = detectedHarnesses.contains(client.name)
        let operationPending = agentManager.isAgentOperationInProgress
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                StudioStatusHookIcon(assetName: client.rawValue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name).fontWeight(.medium)
                    if let note = client.detection.integrationNote {
                        Text(NSLocalizedString(note, comment: "")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if configured {
                    hookStatus(client)
                    Button("卸载") { pendingHookRemoval = client }
                        .disabled(operationPending)
                } else {
                    Text(detected ? "待安装" : "未检测到")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("移除") { setHookClient(client, visible: false) }.buttonStyle(.link)
                    Button("安装") { agentManager.installHook(client) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!detected || !agentManager.isAgentBinaryPresentInBundle || operationPending)
                }
            }
            .controlSize(.small)
            if configured && expandedHookClient == client {
                VStack(alignment: .leading, spacing: 6) {
                    let verification = hookVerifications[client]
                    StudioHookVerificationView(
                        verification: verification,
                        configurationPaths: agentManager.hookConfigurationPaths(client),
                        needsCodexRestart: client == .codex && agentManager.codexHookInstallationStatus?.restartRequired == true
                    )
                    if verification?.configurationChecked != true || verification?.entryChecked != true {
                        Button("修复 Hook") { agentManager.installHook(client) }
                            .buttonStyle(.link)
                            .disabled(!agentManager.isAgentBinaryPresentInBundle || operationPending)
                    } else if verification?.eventReceived == true && verification?.hosts.isEmpty == true {
                        Button("更新 Hook") { agentManager.installHook(client) }
                            .buttonStyle(.link)
                            .disabled(!agentManager.isAgentBinaryPresentInBundle || operationPending)
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 2)
    }

    private func hookStatus(_ client: StudioHookClient) -> some View {
        let verified = hookVerifications[client]?.eventReceived == true
        return Button {
            expandedHookClient = expandedHookClient == client ? nil : client
        } label: {
            Label(verified ? "已验证" : "等待验证",
                  systemImage: expandedHookClient == client ? "chevron.down" : "chevron.right")
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("高级调试工具", isExpanded: $showsAdvancedTools) {
                if showsAdvancedTools {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("调试工具", selection: $advancedTool) {
                            Text("BLE 连接详情").tag(AdvancedTool.ble)
                            Text("配置读取").tag(AdvancedTool.configuration)
                            Text("通信日志").tag(AdvancedTool.communication)
                            Text("Hook 日志").tag(AdvancedTool.hookLog)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        switch advancedTool {
                        case .ble: bleConnectionDetails
                        case .configuration: configurationReadback
                        case .communication: DeviceCommunicationLogView(logStore: bleManager.logStore)
                        case .hookLog: hookLogPanel
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private var bleConnectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompatLabeledContent("连接") {
                Text(connectionTitle(currentConnectionOwner)) + Text(" · ") + Text(connectionStatus)
            }
            CompatLabeledContent("设备名") {
                deviceNameEditor
            }
            CompatLabeledContent("UUID") {
                Text(bleManager.deviceUUIDForDisplay ?? "—")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            CompatLabeledContent("固件协议") {
                Text(firmwareProfileLabel())
                    .textSelection(.enabled)
            }
            CompatLabeledContent("信号") { Text(signalLabel).monospacedDigit() }
            if let firmwareCatalogError {
                Text(firmwareCatalogError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            CompatLabeledContent("GATT 特征") {
                if bleManager.isConnected {
                    HStack(spacing: 8) {
                        charBadge("DATA", ready: bleManager.dataCharReady)
                        charBadge("CMD", ready: bleManager.commandCharReady)
                        charBadge("NOTIFY", ready: bleManager.notifyCharReady)
                    }
                } else {
                    Text("由 Studio 直连后读取").foregroundStyle(.secondary)
                }
            }
            if bleManager.isConnected {
                HStack {
                    Button("查询状态") {
                        bleManager.queryDeviceStatus()
                    }
                    .buttonStyle(.bordered)
                    .help("发送 AA BB 00 CC DD 查询设备状态")

                    Button(isReadingFirmwareCatalog ? "读取中…" : "读取固件能力") {
                        let connection = bleManager.deviceInfoFirmwareReadbackState.connection
                        firmwareCatalogReadingConnection = connection
                        firmwareCatalogError = nil
                        Task { @MainActor in
                            defer {
                                if firmwareCatalogReadingConnection == connection { firmwareCatalogReadingConnection = nil }
                            }
                            do {
                                _ = try await bleManager.readFirmwareCapabilityProfile()
                            } catch {
                                guard bleManager.deviceInfoFirmwareReadbackState.connection == connection else { return }
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

                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var deviceNameEditor: some View {
        if isEditingName && bleManager.isConnected {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    TextField("最长 15 字节", text: $editableName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit { submitNameChange() }
                        .onChange(of: editableName) { _ in nameError = nil }
                    Button(isSubmittingName ? "处理中…" : "写入键盘") { submitNameChange() }
                        .disabled(isSubmittingName || inspectorSession.isBusy)
                        .buttonStyle(.borderedProminent)
                    Button("取消") {
                        nameError = nil
                        isEditingName = false
                    }
                }
                .controlSize(.small)
                if let nameError { Text(nameError).font(.caption).foregroundStyle(.red) }
            }
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bleManager.deviceNameForDisplay ?? "—").textSelection(.enabled)
                    if bleManager.isConnected {
                        Button {
                            editableName = bleManager.deviceName ?? ""
                            nameError = nil
                            nameReceipt = nil
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("修改设备名")
                    }
                }
                if let nameReceipt { Text(nameReceipt).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var hookLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("日志来源", selection: $hookLogSource) {
                    Text("Hook 安装与卸载").tag(HookLogSource.installation)
                    Text("ahakeyconfig-agent 主日志").tag(HookLogSource.agent)
                    Text("Codex Hook（codex-hook.log）").tag(HookLogSource.codex)
                    Text("工具批准（permission-request.log）").tag(HookLogSource.approval)
                    Text("~/.cursor/hooks.json").tag(HookLogSource.cursorHooks)
                    Text("~/.cursor/cli-config.json").tag(HookLogSource.cursorCLI)
                    Text("~/.codex/config.toml").tag(HookLogSource.codexConfig)
                    Text((agentManager.userKimiConfigFilePath as NSString).abbreviatingWithTildeInPath).tag(HookLogSource.kimi)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Button("刷新", action: refreshHookLog).buttonStyle(.link)
                Spacer(minLength: 0)
            }
            if hookLogSource == .kimi { StudioKimiInstanceInspectionView() }
            ScrollView {
                Text(hookLogText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 176)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .onAppear(perform: refreshHookLog)
        .onChange(of: hookLogSource) { _ in refreshHookLog() }
        .onChange(of: agentManager.hookOperationLog) { _ in
            if hookLogSource == .installation { refreshHookLog() }
        }
    }

    private func refreshHookLog() {
        switch hookLogSource {
        case .installation:
            hookLogText = agentManager.hookOperationLog.isEmpty ? agentManager.readLog() : agentManager.hookOperationLog
        case .agent: hookLogText = agentManager.readLog()
        case .approval: hookLogText = agentManager.readPermissionRequestLog()
        case .codex: hookLogText = agentManager.readCodexHookLog()
        case .cursorHooks: hookLogText = agentManager.readUserCursorHooksJsonForDisplay()
        case .cursorCLI: hookLogText = agentManager.readUserCursorCliConfigForDisplay()
        case .codexConfig: hookLogText = agentManager.readUserCodexConfigForDisplay()
        case .kimi: hookLogText = agentManager.readUserKimiConfigForDisplay()
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
        if !bleManager.isConnected { return bleManager.firmwareCatalogKeyForDisplay ?? "未读取" }
        guard let profile = bleManager.firmwareCapabilityProfile else { return "未读取" }
        switch profile.identity {
        case .knownWS2Catalog:
            return "WS2 CP4D · 只读探测"
        case .verifiedCatalog(let key, _):
            return key
        case .legacy:
            return "旧版协议"
        case .unknown(let key):
            return key.map { "未知目录：\($0)" } ?? "未知"
        }
    }

    private var configurationReadback: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
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

    private func workModeName(_ mode: Int) -> String {
        switch mode {
        case 0: return "Mode 1 / Claude"
        case 1: return "Mode 2 / Cursor"
        case 2: return "Mode 3 / Codex"
        case 3: return "Mode 4 / custom"
        default: return "Mode \(mode)"
        }
    }

    private func submitNameChange() {
        guard !isSubmittingName, !inspectorSession.isBusy else { return }
        switch AhaKeyCommand.validateDeviceName(editableName) {
        case .failure(.empty):
            nameError = NSLocalizedString("设备名称不能为空，已保留原名称", comment: "")
        case .failure(.invalidCharacters):
            nameError = NSLocalizedString("设备名称不能包含换行或控制字符，已保留原名称", comment: "")
        case .failure(.tooLong(let byteCount)):
            nameError = String(format: NSLocalizedString("设备名称最长 %d 字节（当前 %d 字节），已保留原名称", comment: ""),
                AhaKeyCommand.deviceNameMaxBytes, byteCount)
        case .success(let name):
            isSubmittingName = true; nameError = nil; nameReceipt = nil
            let expectedDevice = bleManager.bleDeviceUUID
            nameTask = Task { @MainActor in
                defer { isSubmittingName = false; nameTask = nil }
                do {
                    _ = try await inspectorSession.withConnection(expectedDeviceID: expectedDevice) { _ in
                        try await bleManager.changeDeviceName(name)
                    }
                    isEditingName = false
                    nameReceipt = NSLocalizedString("键盘已接收新名称。请正常关机再开机后核对；当前显示仍是上次发现的名称。", comment: "")
                } catch { nameError = error.localizedDescription }
            }
        }
    }
}


/// Observe BLE traffic only while the communication tab is visible.
private struct DeviceCommunicationLogView: View {
    @ObservedObject var logStore: BLELogStore

    var body: some View {
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
                Button("清空视图") {
                    logStore.clear()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.top, 4)
        }
    }
}
