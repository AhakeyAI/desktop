# CURRENT_UI_MAP

## 总体 UI 形态

当前软件是单主窗口 JavaFX 应用，窗口标题 `AhaKey Studio`，默认约 `1280 x 820`，最小 `1024 x 640`。主布局:

- 顶部: `TopBar`
- 中间: 横向可滚动工作区，左侧 `CanvasPane`，右侧 `InspectorPane`
- 底部: `StatusBar`
- 附加窗口/弹窗: 设备信息与 Hook 管理、屏幕动画、固件维护、关于/更新、OLED 上传进度、审批确认、告警、托盘菜单。

## 一级导航

没有传统多页侧边栏。真实一级入口由主屏控件承担:

- 顶部操作区:
  - 连接/断开设备
  - BLE 驱动
  - AhaType 开关
  - 语音服务启动/停止
  - 编辑配置/保存配置
  - 更多菜单
- 左侧键盘预览:
  - 模式选择: 4 个 `ModeSlot`
  - 可点击部件热点: K1/K2/K3/K4、灯条、OLED、拨杆
- 右侧 Inspector:
  - 根据当前选中部件显示二级配置模块。
- 设备信息弹窗:
  - 设备状态、待机设置、设备维护、配对指南、支持服务、Hook 管理、日志。

## 顶部 TopBar

用户进入软件后首先看到:

- 标题 `AhaKey Studio`。
- 状态 pill:
  - 连接状态: connected/scanning/disconnected。
  - 设备名或 waiting device。
  - 电量: 未连接为占位，USB 为 `USB 供电`，BLE 为百分比或读取中。
  - 拨杆状态: 自动/手动审批语义。
- `连接设备` / `断开连接` 按钮:
  - 未连接点击调用 `StudioController.userConnect()`。
  - 已连接点击调用 `StudioController.userDisconnect()`。
- `BLE 驱动` 按钮:
  - 普通点击启动/提示 BLE driver。
  - 长按触发关闭 BLE driver 进程逻辑。
- `AhaType` Toggle:
  - 绑定 `StudioState.ahaTypeEnabled`。
- 语音控件:
  - 启动/停止语音服务按钮。
  - 状态灯: stopped / starting / ready / processing / error。
  - 状态文本和识别预览。
- 配置状态:
  - 当前是键盘控制还是编辑配置。
- `编辑配置` / `保存配置` 按钮:
  - 进入编辑时可能自动连接。
  - 保存时同步所有 dirty 模式。
- 更多菜单:
  - 恢复当前模式默认配置。
  - 重连。
  - 清除 OLED 预览。
  - 屏幕动画。
  - 设备信息。
  - 版本信息/检查更新。
  - 语言切换。
  - 退出。
  - cloud account 菜单项只在 model enabled 时加入，但当前代码未看到 action。

## CanvasPane / 键盘预览

左侧区域包含:

- 模式标题和 4 个模式切换按钮。
- `CanvasLayout.fxml` 加载的键盘可视化。
- `CanvasController` 绑定:
  - 当前选中部件高亮。
  - 按键 caption。
  - OLED 预览图。
  - 拨杆 thumb。
  - 灯条预览动画。
  - 任务灯状态文本。

点击不同热点会修改 `StudioState.selectedPart`，右侧 Inspector 随之重建。

## InspectorPane 二级模块

Inspector 根据选中部件切换内容。非编辑模式下 body 被 disable。

### K1 / Voice Key

显示“双语音键：短按/长按”配置:

- 短按动作 Combo。
- 长按动作 Combo。
- 自定义快捷键编辑器。
- 本地模型不可用时显示 AhaKey 本地语音不可用提示。
- 行为是 Desktop-local voice route，不写固件快捷键。

### 普通按键 K2/K3/K4

显示:

- 按键绑定:
  - 类型选择: 快捷键 / 宏。
  - 快捷键编辑器: HID 修饰键和基础键组合。
  - 宏编辑器: DOWN_KEY / UP_KEY / DELAY step，支持新增、上下移动、删除。
- 按键描述:
  - 文本框，写入本地草稿，保存时作为描述命令写设备。
- 模拟按键:
  - 单键快捷键可通过 Windows voice relay 模拟。
  - 宏暂不执行模拟。

### LIGHT_BAR

显示:

- 任务灯效模式:
  - 单任务 / 多任务。
  - 调用 `TaskActivityService.setMultiMode()`，需要设备确认。
- 灯光亮度:
  - Spinner 1-100。
  - 测试按钮调用 `sendLightBrightnessToDevice()`。
- 当前模式 AI 灯效:
  - 遍历 `IDEState`。
  - 每个状态选择 `LightEffectStyle`。
  - 测试按钮调用 `previewLightEffectOnDevice()`。
  - 保存灯效配置调用 `syncCurrentModeLightConfig()`。
  - 屏幕动画设置按钮打开 `ScreenAnimationDialog`。

### OLED

显示:

- OLED 预览图。
- 当前本地资源路径或 none。
- `配置屏幕动画` 按钮打开 `ScreenAnimationDialog`。
- 上传进度绑定。
- 屏幕文字:
  - 主标题。
  - 副标题。

### TOGGLE_SWITCH

显示:

- 自动审批 / 手动审批 Toggle。
- 调用 `StudioController.updateSwitchState(0/1)`。
- 未连接时提示先连接设备。

## 设备信息 / Developer + Maintenance 弹窗

从更多菜单或首次 Hook onboarding 进入 `showDeviceInfoDialog()`。该弹窗是长滚动单页，包含:

- 设备信息卡:
  - 设备名、连接状态、电量、工作模式、拨杆、传输、Hook server 端口等。
- `StandbySettingsPane`:
  - 待机时间读取/设置，依赖设备连接。
- `DeviceMaintenancePane`:
  - 固件更新。
  - 恢复出厂设置。
  - WCHISP/设备检测/诊断相关流程。
- `BluetoothPairingGuide`:
  - 蓝牙配对指导。
- `SupportPane`:
  - 支持服务二维码/联系入口。
- Hook 管理卡:
  - Claude / Cursor / Codex / Kimi。
  - 安装状态、配置状态、enabled/trusted、server online、最近活动。
  - 安装/卸载按钮。
- 日志卡。
- 弹窗底部:
  - 连接、断开、清日志、关闭。

这些内容混合用户功能、维护功能和 developer/diagnostic 功能。

## 屏幕动画弹窗

`ScreenAnimationDialog` 是 OLED/GIF 管理入口:

- 可按模式和 asset/profile 配置屏幕动画。
- 支持默认 GIF 库、本地 GIF/PNG/JPG、清除、上传、刷新设备摘要。
- 写入规则最终走 `OledUploadService`，且动画修改明确要求 USB。

## 状态表现

- 未连接:
  - TopBar 显示 disconnected/waiting device。
  - 电量显示占位。
  - Inspector 中测试/同步类按钮常被 disabled 或点击后提示先连接。
  - 保存配置时仅保存本地草稿，必要时触发连接。
- Scanning:
  - TopBar 连接状态显示 scanning。
- 已连接:
  - 状态 pill 显示设备名、传输和电量。
  - Inspector 允许设备写入/测试。
- Loading:
  - 语音服务有 starting/stopping/processing 状态灯。
  - OLED 上传有 modal progress。
  - Hook 检测初始为 checking，并后台刷新。
  - 固件维护有分步 UI 和 progress。
- Error:
  - `studioState.syncStatus` 显示错误信息。
  - 多处 Alert warning/error。
  - 语音状态灯 error。
- Disconnected/Recovery:
  - BLE/USB 断开回调更新 DeviceStatus。
  - `BleManager` 有 transport recovery 与 USB-to-BLE fallback。
  - UI 主要通过状态文本/连接状态表现恢复过程。

## 单页长滚动 / 功能堆叠

存在:

- 主工作区横向滚动，TopBar 也用横向 scroll 包裹。
- 设备信息弹窗是长滚动，堆叠设备、维护、支持、Hook、日志。
- Inspector 是右侧 ScrollPane，不同部件内容重建。

## 用户功能 vs Developer 功能

用户功能:

- 连接设备。
- 编辑/保存按键配置。
- 配置语音键 Desktop 行为。
- 调整灯效/亮度/任务显示模式。
- 配置 OLED/屏幕动画。
- 设置拨杆审批语义。
- 语音输入/AhaType。
- 固件更新。
- 语言切换、版本检查、托盘。

Developer / Diagnostic / Maintenance:

- BLE driver 管理。
- Hook 安装/卸载/检测日志。
- 设备信息弹窗里的日志、runtime 状态。
- WCHISP 环境诊断、固件烧录细节。
- release/update 诊断。

## UNKNOWN

- 当前未运行 UI 截图验证，控件真实视觉顺序以代码构建顺序为准。
- `VoiceInputPanel.fxml` 当前是否仍被主 UI 使用: 未在主窗口组装路径中看到直接加载，标 UNKNOWN/legacy candidate。
