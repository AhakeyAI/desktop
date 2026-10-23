# CURRENT_ARCHITECTURE

## 当前职责划分

### UI / View

- `App`: 主窗口组装、托盘、应用生命周期、语音 manager 初始化。
- `TopBar`: 顶部状态、连接、BLE driver、AhaType、语音服务、配置模式、更多菜单、设备信息/Hook 管理弹窗。
- `CanvasPane` + `CanvasController`: 键盘预览、模式选择、热点选择、灯效/OLED/拨杆展示。
- `InspectorPane`: 当前选中部件的配置表单。
- `StatusBar`: sync/status 底栏。
- `DeviceMaintenancePane`, `StandbySettingsPane`, `ScreenAnimationDialog`, `SupportPane`, `BluetoothPairingGuide`: 弹窗/维护/辅助 UI。

### Controller / Workflow

- `StudioController` 是应用总线，持有:
  - `DeviceStatus`
  - `StudioState`
  - `AgentManager`
  - `VoiceRelayPlatform`
  - `BleManager`
  - `FirmwareUpdateService`
  - `HookDispatchServer`
  - `TaskActivityService`
  - `ApprovalService`
  - `WorkModeSynchronizer`
  - `StatusRefreshScheduler`
- 它负责把用户操作转成设备命令或本地状态变化。

### Device State

- UI 可观察状态:
  - `DeviceStatus`。
  - `StudioState`。
  - `AgentManager`。
- 传输层缓存状态:
  - `BleManager.cachedStatus`。
  - `acceptedPhysicalStatus` / `PhysicalStatusFreshness` 用于审批 freshness。
- 模式同步:
  - `WorkModeSynchronizer` 管理 UI 选择和设备报告之间的 stale/confirmed 关系。

### BLE / USB

- `BleManager` 统一管理 transport:
  - USB: `UsbHidTransport`。
  - BLE: TCP socket to bridge，默认 `127.0.0.1:9000`。
- `BleTcpPacket` 定义 bridge 外层 packet。
- `BleBridgeProcessOwner` 和 `BleDriverLocator` 管理 BLE driver 进程/路径。
- `UsbHidTransport` 用 JNA 调 Windows HID API。

### Protocol

- `AhaKeyProtocol`: frame encode、命令常量、payload builder、状态帧 parser。
- `AhaKeyResponseParser`: command response/capabilities/config/OLED/mode/voice response parser。
- `BleTcpPacket`: bridge packet encode/decode。

### Persistence / Settings

- `StudioStore`: 保存/加载 `StudioState.PersistedDraft`。
- `ConfigStore`, `FirstRunState`, `GifSelectionHistory`, `ScreenAnimationAssetStore`。
- Java Preferences:
  - `StudioController` 保存 task display mode。
- `~/.ahakey/preferences.properties`:
  - 语言偏好。
- `model_config.properties`:
  - 本地语音模型配置。

### Logging

- SLF4J + Logback。
- UI 里还有设备信息弹窗的运行日志 `TextArea`。

### Update

- `AppUpdateCoordinator`, `StableReleaseClient`, `AssetDownloader`, `WindowsUpdateInstaller`, `RemoteClientConfigService`。
- `FirmwareUpdateNotifier` 在应用 ready 后/连接时检查。

### Diagnostics / Maintenance

- `DeviceMaintenancePane`。
- `FirmwareUpdateDiagnostics`。
- WCHISP runtime contract/provider/runner/flasher。
- Release validation PowerShell scripts。

### Native / JNI / JNA

- JNA:
  - Windows HID。
  - Windows keyboard input/hook。
- Sherpa:
  - `LibraryLoader` 加载 native libraries。
- WCHISP:
  - 外部 exe/dll。

## 重点问题回答

### 1. UI 是否直接调用 BLE / USB？

部分直接，部分通过 Controller。

- 主配置 UI 基本通过 `StudioController`。
  - 例: TopBar connect -> `controller.userConnect()`。
  - Inspector 灯效/亮度/OLED -> `StudioController`。
- 但 UI 也会读取底层服务:
  - TopBar 调 `controller.getBleManager()` 传给 update/firmware notifier。
  - DeviceMaintenancePane 直接使用 `controller.getFirmwareUpdateService()` 和 `controller.getBleManager()`。
  - ScreenAnimationDialog 通过 `controller` 进入 OLED 上传/读取。
- UI 不直接操作 `UsbHidTransport`，也不直接写 BLE socket。

### 2. Protocol frame encode/decode 在哪里？

- Encode:
  - `AhaKeyProtocol.buildFrame(cmd, data)`。
  - 所有设备命令 builder 均返回 `AA BB [cmd] [payload] CC DD`。
- Decode:
  - `AhaKeyProtocol.isValidFrame()`。
  - `AhaKeyProtocol.parseDeviceStatus()`。
  - `AhaKeyResponseParser.parseCommandResponse()`。
  - 其他 response parser 在 `AhaKeyResponseParser`。
- Transport extraction:
  - BLE bridge: `BleManager.startReader()` 先读 `[type][len]`，body 交 `dispatchPacket()`。
  - USB HID: `UsbHidTransport.FrameExtractor` 从 64-byte reports 拼出 AhaKey frame。

### 3. Device state 谁拥有？

- UI 层观察 `StudioController.deviceStatus`。
- 传输层维护 `BleManager.cachedStatus`，每次解析物理状态后回调给 controller。
- `StudioController.applyBleStatus()` 把 `BleManager` 返回的状态复制到 UI `DeviceStatus`。
- 因此状态所有权是“双层”:
  - transport truth/cache 在 `BleManager`；
  - UI truth 在 `StudioController.DeviceStatus`。

### 4. 是否存在全局 mutable state？

存在。

- `LanguageManager.getInstance()`。
- `ModelConfig.getInstance()`。
- `WindowsVoiceRelayService.getInstance()`。
- `ApplicationLifecycle` static exit handler。
- `SingleInstanceChecker` static lock/server resources。
- `BleBridgeProcessOwner` static owned process lifecycle。
- `ScreenAnimationDialog` static `ScreenAnimationAssetStore`。
- Java Preferences / filesystem state。

### 5. 用户操作从 Button 到 Device 的真实调用链

示例: 保存所有配置。

1. TopBar `configModeButton.onAction`。
2. `StudioController.handleConfigurationModeButton()`。
3. `finishEditingConfiguration()`。
4. `syncAllModes(true)`。
5. `bleManager.selectPreferredTransport()`。
6. `bleManager.requireStabilizedDeviceContract()` -> `CMD_QUERY_CAPABILITIES 0x9F`。
7. `DeviceSyncService.commandsForModes(studioState, modes...)`。
8. `DeviceSyncService.writeSequentially()`。
9. 每条命令 `ble.sendCommandExpecting(frame, frame[2])`。
10. `BleManager.sendCommand()`。
11. `UsbHidTransport.sendCommand()` 或 `writePacket(WRITE_COMMAND, frame)`。
12. 设备返回 notify。
13. `BleManager.onBleNotify()` -> `pendingNotifyFrame` -> `waitForResponse()` 解锁。

示例: 切换模式。

1. Canvas mode Toggle。
2. `StudioController.selectKeyboardMode(mode)`。
3. `WorkModeSynchronizer.selectUserMode()`。
4. connected 时调用 `bleManager.setWorkMode(modeIndex)`。
5. `AhaKeyProtocol.setWorkMode()` -> `CMD_SET_WORK_MODE 0x92`。
6. 等 ACK。
7. 设备异步/查询返回 `CMD_MODE_SYNC 0x9B` 或 status。
8. `BleManager` mode listener -> `StudioController.applyReportedWorkMode()`。

示例: OLED 上传。

1. Inspector/ScreenAnimationDialog 选择资产。
2. `StudioController.uploadCurrentOledToDevice()` 或 dialog job。
3. `OledUploadService.validateUploadPlan()`。
4. `ble.writeLargeData(address, frames)`。
5. 每 4K block:
   - `CMD_PREPARE_WRITE 0x80`
   - `WRITE_DATA` chunks
   - `CMD_WRITE_RESULT 0x81`
6. 完成后:
   - `CMD_UPDATE_PIC 0x82` 或 `CMD_SET_AI_OLED_CONFIG 0x93`
   - `CMD_SAVE_CONFIG 0x04`
   - 回读验证。

### 6. Device Event 返回后如何更新 UI？

- BLE/USB frame 进入 `BleManager.dispatchPacket()`。
- `BLE_NOTIFY` 进入 `onBleNotify()`。
- 如果是 status frame:
  - `AhaKeyProtocol.parseDeviceStatus()`。
  - 更新 `cachedStatus`。
  - `callback.onConnected()` 如由 disconnected -> connected。
  - `callback.onStatusReceived(status)`。
  - `StudioController` 在 `Platform.runLater()` 中 `applyBleStatus()`。
  - JavaFX binding 自动刷新 TopBar/Canvas/Inspector/StatusBar。
- 如果是 `CMD_MODE_SYNC 0x9B`:
  - `parseModeSync()`。
  - 更新 cached workMode。
  - 调 mode listener。
  - controller 更新 work mode synchronizer。
- 如果是命令 response:
  - 唤醒 pending request，不一定直接更新 UI；调用方在成功/失败 callback 设置 syncStatus。

### 7. 有没有重复 Device / Protocol logic？

事实存在若干重复/重叠:

- 设备状态缓存存在 `BleManager.cachedStatus` 和 `StudioController.deviceStatus` 两份。
- 工作模式同步同时受 `Status`、`CMD_MODE_SYNC`、`WorkModeSynchronizer`、UI selected mode 影响。
- `ble_bridge.py` 和 Java `BleTcpPacket` / `BleManager` 有 bridge packet 逻辑重叠，但 Python 文件可能是参考/旧实现。
- HID code 构造逻辑分散在:
  - `InspectorPane` UI 解析；
  - `HIDUsage`；
  - `AhaKeyProtocol.hidCodesForShortcut()`；
  - `DeviceSyncService`。
- OLED/GIF capacity 有 fallback 常量和设备 `0x9C` layout 回读两套来源。

## Preserve 候选

- `AhaKeyProtocol` / `AhaKeyResponseParser` 把 frame 编码和多数 parser 集中在一个包内，值得保留为协议基准。
- `BleManager` 的 transaction lock、session token、response wait 和 stale receiver 防护有实际价值。
- `PhysicalStatusFreshness`/审批 freshness 体现了安全边界，值得保留。
- `WorkModeSynchronizer` 避免 UI 模式被旧设备回报覆盖，值得保留。
- `DeviceSyncService.commandsForModes()` 把草稿到命令列表集中化，适合作为 Harness 断言目标。
- WCHISP runtime contract/provider/runner 测试较多，发布安全意识较强。

## UNKNOWN

- BLE driver exe 内部是否完全遵守 `BleTcpPacket` 当前 Java 契约，当前仓库无法证明。
- 固件对每个 status/error code 的完整定义，当前只能根据 Java 映射记录。
