# FEATURE_INTERFACE_MATRIX

| 用户功能 | UI 入口 | Java workflow | Device API | Protocol command/event | Transport | Firmware responsibility |
|---|---|---|---|---|---|---|
| 连接设备 | TopBar `连接设备` | `StudioController.userConnect()` -> `BleManager.connect()` | `queryStatus()` after connect | `0x00 QUERY_STATUS` | USB HID first, fallback BLE TCP bridge | 返回状态帧和 readiness flags |
| 断开设备 | TopBar `断开连接` / 更多菜单重连 | `userDisconnect()` -> `BleManager.disconnect()` | close USB/TCP | none | USB/BLE | UNKNOWN |
| 切换键盘模式 | CanvasPane 模式 toggle | `selectKeyboardMode()` -> `WorkModeSynchronizer` | `BleManager.setWorkMode()` | `0x92 SET_WORK_MODE`, event/read `0x9B MODE_SYNC`, status `0x00` | USB/BLE | 切换工作模式并回报当前模式 |
| 进入编辑配置 | TopBar `编辑配置` | `enterEditingConfiguration()` | maybe auto connect | none | local + optional connect | UNKNOWN |
| 保存配置 | TopBar `保存配置` | `finishEditingConfiguration()` -> `syncAllModes()` -> `DeviceSyncService.writeSequentially()` | `sendCommandExpecting()` | `0x73`, `0x84`, `0x85`, `0x97`, `0x04` | USB/BLE, OLED excluded | 写入 key/light/voice config 并持久化 |
| 修改普通按键快捷键 | Inspector K2/K3/K4 快捷键编辑器 | `StudioState` dirty -> save | `DeviceSyncService.commandsForModes()` | `0x73 SUB_SHORTCUT` | USB/BLE | 保存 mode/keyIndex HID codes |
| 修改普通按键宏 | Inspector K2/K3/K4 宏编辑器 | `StudioState` dirty -> save | `DeviceSyncService.commandsForModes()` | `0x73 SUB_MACRO` | USB/BLE | 保存 macro sequence |
| 修改按键描述 | Inspector 文本框 | `StudioState.updateKeyDescription()` -> save | `DeviceSyncService.commandsForModes()` | `0x73 SUB_DESCRIPTION` | USB/BLE | 保存 ASCII 描述 |
| 模拟按键 | Inspector `模拟按键` | `VoiceRelayPlatform.simulateKeyByHid()` | Windows SendInput | none | local Windows | 无固件参与 |
| K1 短按/长按动作 | Inspector K1 voice group | `StudioState.setVoiceShort/LongAction()` -> `refreshVoiceRoutes()` | `VoiceRelayPlatform.configureVoiceActions()` | Desktop local; save may verify `0x97` | local + optional USB/BLE for config | F18/voice key事件与配置支持，具体行为多在 Desktop |
| 启动本地语音 | TopBar 语音按钮 | `TopBar.startVoiceService()` -> `VoiceInputManager.startVoiceInput()` | `SpeechService` + `KeyboardInjector` | none | local microphone/keyboard injection | 无固件参与 |
| 物理语音键长按录音 | AhaKey 物理按键 | Windows hook -> `WindowsVoiceRelayService` -> `VoiceInputManager.start/stopRecording()` | local voice manager | firmware emits key/HID event; Desktop route gated by `0x9F` version | device HID + local | 提供 F18/voice key 输入与能力版本 |
| AhaType 开关 | TopBar `AhaType` toggle | `StudioState.toggleAhaType()` | local text processing | none | local | 无固件参与 |
| 调整灯条亮度 | Inspector LIGHT_BAR spinner + 测试 | `sendLightBrightnessToDevice()` | `BleManager.setLightBrightness()` | `0x85 SET_LIGHT_BRIGHTNESS` | USB/BLE | 设置亮度 |
| 测试灯效 | Inspector LIGHT_BAR 每状态测试 | `previewLightEffectOnDevice()` | `BleManager.setLightEffect()` | `0x91 SET_LIGHT_EFFECT` | USB/BLE | 临时显示灯效 |
| 保存 AI 灯效配置 | Inspector `保存灯效配置` / 保存全部 | `syncCurrentModeLightConfig()` or sync all | `BleManager.setAiLightConfig()` | `0x84 SET_AI_LIGHT_CONFIG`, `0x85`, `0x04` | USB/BLE | 保存每模式 IDEState -> effect mapping |
| 单/多任务灯效 | Inspector LIGHT_BAR toggle | `TaskActivityService.setMultiMode()` | `BleManager.setTaskDisplayMode()` | `0x98 TASK_LIGHT_MODE`, then `0x04` | USB/BLE | 切换任务显示模式 |
| Hook 任务状态显示 | Claude/Cursor/Codex/Kimi hook | `HookDispatchServer` -> `TaskActivityService.accept()` | `updateTaskSlot()`, heartbeat | `0x99 TASK_SLOT_UPDATE`, `0x9A TASK_HEARTBEAT` | USB/BLE | 显示任务槽状态/前台标记 |
| 设置拨杆审批语义 | Inspector TOGGLE_SWITCH | `updateSwitchState(0/1)` | `BleManager.updateState()` | `0x90 UPDATE_STATE` | USB/BLE | 改变自动/手动审批状态并回报 switchState |
| 自动审批判断 | Hook/Kimi 请求 | `ApprovalService.refresh()` | `queryStatusAndWait()` | `0x00 QUERY_STATUS` | USB/BLE | 返回 fresh switch state |
| 手动审批 | Hook/Kimi 请求 | `StudioController.showApprovalDialog()` | none until approval result | none | local UI | 无固件参与 |
| OLED 默认图/GIF 上传 | Inspector OLED / ScreenAnimationDialog | `uploadCurrentOledToDevice()` -> `OledUploadService` | `writeLargeData()`, `sendCommandExpecting()` | `0x9C`, `0x80`, data, `0x81`, `0x82`, `0x04`, verify `0x83` | USB only for screen animation writes | 写外部 Flash，更新图片索引并持久化 |
| AI OLED asset 配置 | ScreenAnimationDialog | `OledUploadService` | read/set AI OLED | `0x94 READ_AI_OLED_CONFIG`, `0x93 SET_AI_OLED_CONFIG` | USB for write, read via current transport | 管理状态动画分区 |
| 清除 OLED 预览 | 更多菜单 | `studioState.clearOledPreview()` | local only | none | local | 无固件参与 |
| 待机时间读取/设置 | 设备信息弹窗 `StandbySettingsPane` | pane -> `BleManager.read/setSaveAndVerifyStandbyTimeoutMinutes()` | standby API | `0x95 STANDBY_TIMEOUT`, `0x04 SAVE_CONFIG` | USB/BLE | 保存待机时间 |
| 恢复出厂设置 | DeviceMaintenancePane | reset card -> `BleManager.factoryReset()` | factory reset API | `0x96 FACTORY_RESET` with `A5 5A` | USB/BLE | 清空/恢复设备配置 |
| 固件升级 | DeviceMaintenancePane | `FirmwareUpdateService` -> `WindowsWchIspFlasher` | WCHISP external tool | Not AhaKey app protocol during flashing; post verify `0x9F`/status | WCH ISP USB + post-boot USB/BLE | ISP bootloader 写固件，应用固件回报版本能力 |
| App 更新 | 版本信息/ready check | `AppUpdateCoordinator` | HTTP release/download, installer | none | network/Windows installer | 无固件参与 |
| BLE driver 管理 | TopBar `BLE 驱动` | `BleDriverLocator` + `BleBridgeProcessOwner` | external exe | BLE-TCP packet to Java after driver runs | local process + BLE | bridge 与设备 GATT 通信 |
| Hook 安装/卸载 | 设备信息弹窗 Hook cards | `HookInstaller.install/uninstall/inspectInstallation()` | file/config edits outside device | none | local filesystem | 无固件参与 |

## 关键链路样例

### 修改按键并保存

`InspectorPane` 修改 K2 -> `StudioState.markDirty()` -> TopBar 保存 -> `StudioController.syncAllModes()` -> `DeviceSyncService.commandsForModes()` -> `AhaKeyProtocol.setKeyMapping()` -> `BleManager.sendCommandExpecting()` -> USB/BLE -> firmware ACK。

### Hook 任务变更到灯条

AI Hook HTTP 请求 -> `HookDispatchServer` -> `TaskActivityService.accept()` -> slot allocation -> `BleManager.updateTaskSlot()` -> `AhaKeyProtocol.updateTaskSlot()` -> firmware 更新任务灯。

### OLED 上传

选择 GIF/图片 -> `OLEDFrameEncoder` 预检/编码 -> `OledUploadService.validateUploadPlan()` -> `0x9C` layout -> `writeLargeData()` 分块 -> `0x82/0x93` 设置索引 -> `0x04` 保存 -> `0x83/0x94` 验证。

## UNKNOWN

- Firmware 内部如何存储 key/macro/description/light/OLED 数据，当前仓库不可见。
- BLE driver exe 与 firmware GATT notify/write 的完整映射不可见。
