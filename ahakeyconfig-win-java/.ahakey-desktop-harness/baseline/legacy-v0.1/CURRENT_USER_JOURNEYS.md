# CURRENT_USER_JOURNEYS

## 首次启动

1. 用户启动应用。
2. `App.start()` 调用 `SingleInstanceChecker.acquireOrActivate()`。
3. 如果已有实例，新实例向已有实例发送 show-window 请求并退出。
4. 当前实例加载语言偏好: `~/.ahakey/preferences.properties` 中 `AhaKeySelectedLanguage`。
5. 创建 `StudioController`:
   - 从 `StudioStore.loadOrDefault()` 加载本地草稿。
   - 创建 `BleManager`。
   - 创建固件更新服务。
   - 启动 Windows voice relay。
   - 启动 Hook dispatch server。
   - 创建 Kimi bridge，但等连接后按传输类型启动。
6. 若 `model.enabled=true`，初始化 `VoiceInputManager` 和 Sherpa 语音能力；失败时 fail closed，不阻止主 UI。
7. 初始化系统托盘。
8. 显示主窗口。
9. TopBar ready 后触发:
   - App update coordinator ready。
   - firmware update notifier check when connected。
   - 首次 Hook onboarding: Windows 且未安装 Hook 时提示打开 Hook 管理。

## 未连接设备

- TopBar 显示 disconnected / waiting device。
- 电量为占位。
- Inspector 仍可编辑本地草稿，但 body 只有进入编辑配置后可编辑。
- 测试灯效/亮度、上传 OLED 等设备动作会 disabled 或提示先连接。
- 保存配置时:
  - 若设备未连接且不是模拟模式，显示本地保存/请连接后写入；
  - 若不是手动断开，可能自动调用 `userConnect()`。

## 找到 AhaKey

当前代码里的发现路径有两条:

- USB:
  - `BleManager.openPreferredTransport()` 先 `tryConnectUsb()`。
  - `UsbHidTransport` 枚举 HID 设备路径，匹配 `VID_413C&PID_2107`。
  - 打开 read/write handle 后读取协议帧。
- BLE:
  - USB 不可用时连接 TCP bridge `127.0.0.1:9000`。
  - Java 向 bridge 查询 BLE status/device info。
  - bridge 连接目标设备和 GATT 细节由外部 driver 负责；本仓库 `ble_bridge.py` 参考中目标特征 `00007343-0000-1000-8000-00805f9b34fb`。

## 连接

1. 用户点击 `连接设备`。
2. `TopBar` 调用 `StudioController.userConnect()`。
3. `StudioController` 设置 scanning，并调用 `bleManager.connect()`。
4. `BleManager`:
   - 如果已有 transport active，只刷新状态。
   - 否则启动 `device-connect` 线程。
   - 关闭旧 TCP。
   - 优先尝试 USB HID。
   - USB 失败后连接 BLE bridge TCP。
5. 成功连接后，状态不是立即“设备可配置”；必须收到真实协议状态帧或 readiness 信息。
6. `StudioController` 启动状态轮询，查询 `0x00` 状态。
7. 连接回调更新 `DeviceStatus`，UI 切到 connected。

## 已连接

- DeviceStatus 持有:
  - connected/scanning。
  - battery。
  - deviceName。
  - transport。
  - workMode。
  - switchState。
  - readiness flags。
- 状态轮询每 1-2 秒查询 `queryStatus()`。
- USB 连接且非 BLE bridge session 时启动 `KimiAhaKeyBridge`。
- 连接后会异步查询 `0x9F` capabilities 作为 raw F18 route gate。

## 配置设备

1. 用户点击 `编辑配置`。
2. `StudioController.enterEditingConfiguration()`:
   - Bluetooth owner 设为 `AHAKEY_STUDIO`。
   - 刷新 voice routes。
   - 未连接且非手动断开时自动连接。
3. 用户在 Canvas 选择模式/部件，在 Inspector 修改本地草稿。
4. `StudioState` revision 变化会:
   - 持久化到本地。
   - 刷新 voice routes。
5. 用户点击 `保存配置`。
6. `StudioController.finishEditingConfiguration()`:
   - 无 dirty changes 则直接 `returnToKeyboardControl()`。
   - 已连接则 `syncAllModes(true)`。
7. `syncAllModes()`:
   - 选择 preferred transport。
   - 要求 `requireStabilizedDeviceContract()`。
   - 捕获 dirty snapshot。
   - `DeviceSyncService.commandsForModes()` 生成命令。
   - `DeviceSyncService.writeSequentially()` 串行发送并等待 ACK。
   - 成功后清 dirty，更新 `lastSyncedRevision`，可交还控制权。

## 按键 / Binding

- K1:
  - 当前作为语音键/桌面动作路由。
  - 短按/长按动作保存在 `StudioState`，刷新 `VoiceRelayPlatform`。
  - 代码注释明确动作不写入固件快捷键。
  - 保存配置时会生成 `CMD_VOICE_KEY_CONFIG 0x97`，用于 voice key config/threshold 对齐。
- K2/K3/K4:
  - 快捷键模式保存 HID codes。
  - 宏模式保存 macro steps。
  - 描述文本本地可编辑，保存时写入描述命令。
  - 保存命令走 `CMD_UPDATE_CUSTOM_KEY 0x73`，payload 子类型:
    - `SUB_SHORTCUT 0x73`
    - `SUB_MACRO 0x74`
    - `SUB_DESCRIPTION 0x75`

## Voice / AI 相关功能

- TopBar:
  - 启动/停止本地语音服务。
  - 语音服务由 `VoiceInputManager` + `SpeechService` + Sherpa-ONNX 驱动。
  - 识别结果通过 `KeyboardInjector` 注入文本。
- Windows physical voice key:
  - `WindowsVoiceRelayService` 接收低级键盘事件。
  - `VoiceButtonStateMachine` 区分短按/长按。
  - Long press 可触发 AhaKey local voice recording。
  - raw F18 routing 受 firmware version/capability gate 控制。
- AI hooks:
  - `HookDispatchServer` 接收 Claude/Cursor/Codex/Kimi hook events。
  - `TaskActivityService` 将任务状态映射到设备任务灯槽。
  - `ApprovalService` 根据设备拨杆状态判断是否可自动审批。
  - 手动审批弹窗 15 秒超时 fail closed。

## Firmware / Device 状态

- 设备状态来自 `CMD_QUERY_STATUS 0x00`。
- 设备能力来自 `CMD_QUERY_CAPABILITIES 0x9F`。
- 固件更新 UI 位于设备信息弹窗的 `DeviceMaintenancePane`。
- 固件更新走 `FirmwareUpdateService` -> `FirmwareFlasher` / `WindowsWchIspFlasher` / WCHISP runtime。
- 更新后 `FirmwarePostVerifier` 查询设备版本/能力确认。

## Disconnect / Reconnect

- 用户点击断开:
  - `StudioController.userDisconnect()` 设置手动断开，释放模拟按键，调用 `bleManager.disconnect()`。
  - `BleManager` 标记 disconnected，关闭 USB/TCP，唤醒等待响应线程，回调 disconnected。
- 更多菜单重连:
  - 先 `userDisconnect()` 再 `userConnect()`。
- USB 意外断开:
  - `UsbHidTransport` reader 检测 read stopped，回调。
  - `BleManager.handleUsbDisconnected()` 尝试保留 BLE bridge，并启动 fallback。
- BLE reader 异常:
  - 报错并 disconnect。
- 物理状态响应丢失:
  - `BleManager` 有 transport recovery rebuild。

## USB / BLE 模式

- Desktop 不是 UI 上显式切换 USB/BLE；传输选择由 `BleManager` 自动决定。
- 优先 USB HID。
- USB 不可用时走 BLE bridge TCP。
- OLED/GIF 屏幕动画写入要求 USB。
- BLE mode 下 bridge 端口 9000 被 BLE driver 占用，Kimi Java bridge 不启动。

## Error / Recovery

- 连接失败:
  - `callback.onError()` 写入 `studioState.syncStatus`。
- 命令失败:
  - `waitForResponse()` 检查 response status，非 0 转换为设备错误文本。
- 命令 timeout:
  - `RESPONSE_TIMEOUT_MS = 15000`。
- 大数据写入:
  - 每 4K block 最多 `OLED_BLOCK_MAX_ATTEMPTS = 3`。
- 手动审批:
  - 并发请求 fail closed。
  - 15 秒超时 fail closed。
- 语音服务初始化失败:
  - 记录日志，UI 标记 unavailable，主应用继续。

## 软件关闭 / 再次打开

- 点击窗口关闭:
  - 如果系统托盘可用，隐藏到托盘，不退出。
  - 托盘左键显示窗口，托盘菜单 Exit 真正退出。
- 退出:
  - 关闭语音服务。
  - `controller.shutdown()`:
    - 释放模拟键。
    - 停止 voice relay。
    - 停止状态轮询。
    - 停止 Hook server。
    - 停止 Kimi bridge。
    - 关闭 firmware update service。
    - shutdown BLE manager。
  - 停止 owned BLE bridge process。
- 再次打开:
  - 单实例 checker 会激活已有窗口。
  - 若真正退出后再打开，会重新加载本地草稿、语言偏好、配置。

## UNKNOWN

- BLE driver exe 的实际扫描目标名称、GATT 服务 UUID 和重连策略在当前 Java 仓库内不完整。
- `cloudAccount` 菜单项未看到 action，真实用户路径 UNKNOWN。
