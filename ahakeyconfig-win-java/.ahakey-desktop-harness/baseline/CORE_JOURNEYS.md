# 核心商品机用户旅程与回归保护

状态：候选清单，等待 Owner/团队逐条确认。产品定位已继承，但产品基线未批准。

## Owner 选择记录

2026-09-26 Owner 选择：第一轮优先梳理 A「连接设备并保存配置」。

边界：这只确定梳理顺序，不代表产品基线批准、真机验证通过、授权修复/重构/新增功能，也不放弃语音/AhaType。语音/AhaType 仍保留为后续核心旅程候选。

## 候选旅程

| ID | 用户目标/前置状态 | 当前步骤与代码依据 | Preserve / 不改项候选 | 设备/固件/连接范围 | Owner 确认来源 | 已有证据与适用性 | 未验证/历史问题 | 本项变更触发复验条件 |
|---|---|---|---|---|---|---|---|---|
| CJ-01 | 首次打开或回到主窗口，用户快速判断设备是否可用 | `App.start()` 创建 `StudioController`、`TopBar`、`CanvasPane`、`InspectorPane`、`StatusBar`；TopBar 展示连接、电量、拨杆/审批语义和主要操作 | 保留单窗口工作台，不把普通用户带进长诊断页 | 不依赖设备也应可显示主窗口；真实视觉未截图 | 待确认 | 源码确认入口和布局；JDK17 下编译通过 | 无运行截图 | 改主窗口布局、启动流程、语言/模型初始化 |
| CJ-02 | 用户连接 AhaKey，并能看懂 USB/BLE 状态 | TopBar 连接按钮调用 `StudioController.userConnect()`；`BleManager` 优先 USB HID，失败后连 `127.0.0.1:9000` BLE bridge | 保留自动 transport 选择；不要暴露无必要的 USB/BLE 细节给普通用户 | USB HID `VID_413C/PID_2107`；BLE driver/GATT 未验证 | 本轮 Owner 选择 A 后优先梳理 | 源码确认 USB/BLE fallback | BLE driver exe 行为 unknown；无真机 | 改连接、断开、BLE driver、transport 选择 |
| CJ-03 | 用户进入编辑、修改按键/灯效/OLED，并保存后回到键盘控制 | `enterEditingConfiguration()` 设置 Studio owner；Inspector 编辑本地草稿；`finishEditingConfiguration()` 调 `syncAllModes()`；`DeviceSyncService.commandsForModes()` 生成命令 | 保留“编辑/保存/交还控制权”的主流程；保留未连接时本地草稿 | 写入命令语义需固件确认；当前无 capability gate | 本轮 Owner 选择 A 后优先梳理 | 源码确认流程和命令生成 | ACK 是否代表持久化 unknown；无真机 | 改配置结构、保存按钮、命令序列、dirty/sync 状态 |
| CJ-04 | 用户使用 K1/AhaType/本地语音，物理键或按钮能产生预期输入 | `VoiceInputManager`、`SpeechService`、`WindowsVoiceRelayService`、`KeyboardInjector` 存在；当前 `model_config.properties` 未启用模型 | 保留语音失败不阻塞主 UI；保留 Windows 本地输入路径边界 | 语音模型文件和物理键路由未实测 | 后续确认 | 源码确认能力存在 | 模型资源缺口、F17/F18/Win+H 真实路由 unknown | 改语音入口、K1 语义、模型配置、键盘注入 |
| CJ-05 | 用户/支持人员排查 Hook 与 BLE driver | More 菜单打开设备信息/Hook 对话框；TopBar BLE driver 短按启动、长按 5 秒杀进程；Hook 对话框检测 Claude/Cursor/Codex/Kimi | 诊断能力应收敛为支持/高级入口，不抢主流程 | 会读取/写入用户 hook 配置，真实操作需谨慎 | 后续确认 | 源码确认入口存在 | 设备信息弹窗比旧调查缩小；无截图；Hook 安装有系统副作用 | 改 Hook 安装、BLE driver 管理、诊断入口 |

## A 旅程源码还原：连接设备并保存配置

状态：SOURCE_INFERRED_ONLY，尚未运行 UI 截图，尚未真机验证。

- 用户从哪里连接：TopBar 的「连接设备」按钮调用 `StudioController.userConnect()`。非模拟模式下，它设置 scanning，然后调用 `BleManager.connect()`。
- 用户从哪里编辑/保存：TopBar 的「编辑配置 / 保存配置」共用一个按钮，由 `configurationModeButtonTitle()` 根据是否处于编辑状态显示不同文本，点击后走 `handleConfigurationModeButton()`。
- 本地草稿和设备配置如何区分：`StudioState` 是当前编辑草稿；`StudioStore` 把草稿读写到 `~/.ahakey/studio-draft.json`。草稿保存到本地不等于设备已写入。
- 进入编辑会发生什么：`enterEditingConfiguration()` 把 owner 切到 `AHAKEY_STUDIO`，刷新语音路由；如果未连接且非模拟模式，会自动调用 `userConnect()`。
- 连接实际做什么：`BleManager.connect()` 先尝试 USB HID；若未找到或打开失败，再连接 `127.0.0.1:9000` BLE bridge。
- 点击保存/下发实际做什么：`finishEditingConfiguration()` 在有未同步修改时调用 `syncAllModes(true)`；`syncAllModes()` 选择 USB 或 BLE transport，调用 `DeviceSyncService.commandsForModes()` 为四个模式和 K1-K4 生成按键/宏/描述命令、AI 灯效命令、亮度命令，最后追加 `AhaKeyProtocol.saveConfig()`。
- 命令如何发送：`DeviceSyncService.writeSequentially()` 后台逐条调用 `BleManager.sendCommand()`，每条间隔 50ms；当前普通配置写入没有逐条等待 ACK。
- 界面根据什么显示结果：TopBar/StatusBar/Inspector 绑定 `DeviceStatus`、`StudioState.syncStatus`、`studioState.syncing`、`AgentManager.bluetoothOwner` 等状态。连接状态来自 `BleManager` 回调和 `DeviceStatus`；保存结果目前主要来自发送线程完成或异常，不等于已确认设备持久化。
- 需要 Firmware/真机证据的点：USB/BLE 真实连接、命令是否被设备正确应用、`CMD_SAVE_CONFIG` 是否代表持久化完成、ACK/错误语义、断连/重连后设备实际配置是否与草稿一致。
