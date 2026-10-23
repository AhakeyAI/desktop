# CURRENT_DEBTS

本文件只记录当前事实风险，不提出重构方案。

## UI debt

### 设备信息弹窗功能堆叠

- Evidence: `TopBar.showDeviceInfoDialog()` 将设备信息、待机、维护、配对指南、支持、4 个 Hook 管理卡、日志和连接操作放在一个滚动弹窗。
- Impact: 用户功能与 developer/diagnostic 功能边界弱；后续 UI 调整容易误动维护能力。
- 是否当前阻塞: 否。

### TopBar 横向堆叠过多

- Evidence: TopBar 同一行包含标题、3 个 status pill、连接、BLE driver、AhaType、语音、配置状态、保存按钮、菜单，并用水平 ScrollPane 包裹。
- Impact: 小窗口/分屏下信息架构压力大，主要 CTA 不稳定。
- 是否当前阻塞: 否。

### 语言/文字存在乱码风险

- Evidence: 多个 Java 源文件中中文注释/字符串在当前读取输出中呈现 mojibake；资源 properties 有中英文版本。
- Impact: 若文件编码/构建环境变化，UI 文案或注释可读性可能受影响。
- 是否当前阻塞: UNKNOWN，需在实际 UI/编译环境验证。

## Information architecture debt

### 用户、维护、开发工具共用入口

- Evidence: 更多菜单 `设备信息` 同时进入 Hook 管理、WCHISP 维护、日志。
- Impact: 面向普通用户的路径和工程调试路径混合；未来 Harness 需要防止用户路径被维护项副作用影响。
- 是否当前阻塞: 否。

### 无显式 USB/BLE 模式解释

- Evidence: transport 自动选择在 `BleManager`，UI 仅显示 transport；屏幕动画写入又要求 USB。
- Impact: 用户可能不理解为什么某些动作 BLE 下不可用。
- 是否当前阻塞: 对 OLED/动画写入可能是轻度阻塞。

## Duplicated logic

### HID code 构造/解析分散

- Evidence: `InspectorPane` 内大量 HID 选择/字符串解析；`HIDUsage`; `AhaKeyProtocol.hidCodesForShortcut()`; `DeviceSyncService` 也构造 HID list。
- Impact: 新增按键或修改右/左修饰键规则时容易不一致。
- 是否当前阻塞: 否。

### 状态有两份 truth

- Evidence: `BleManager.cachedStatus` 与 `StudioController.deviceStatus` 双层状态。
- Impact: 回调时序、stale receiver、recovery 情况下需要额外同步防护。
- 是否当前阻塞: 否，已有 session token/freshness 防护。

### GIF/OLED capacity fallback 与设备 layout 并存

- Evidence: `AhaKeyProtocol` 常量、`OledUploadService` fallback total slots、`0x9C GIF_LAYOUT` 回读同时存在。
- Impact: 固件容量变化时 fallback 与真实设备可能分叉。
- 是否当前阻塞: 否，但 Harness 应覆盖。

## Protocol debt

### `0x90 UPDATE_STATE` 语义重叠

- Evidence: 用于拨杆/状态更新；`parseDeviceStatus()` 明确忽略 6-byte `0x90`，避免覆盖 switch state。
- Impact: 上位机和固件若新增状态事件，容易把 ACK/事件/状态混淆。
- 是否当前阻塞: 否，但高风险。

### `0x86` 历史冲突

- Evidence: `CMD_LEGACY_CONFLICT` 注释说明曾被 GIF 套图和待机时间复用，当前保留但不发送。
- Impact: 旧固件兼容风险。
- 是否当前阻塞: 否。

### BLE GATT 契约不完整留在 Java 仓库

- Evidence: Java 只看到 TCP bridge packet；GATT UUID 仅在 `ble_bridge.py` 中出现一个 write char。
- Impact: Desktop Harness 无法仅凭 Java repo 验证 BLE driver 与 firmware GATT 契约。
- 是否当前阻塞: 对 BLE/Firmware 联调 Harness 是阻塞项。

### Response 类型统一度有限

- Evidence: command response 统一 `cmd/status/payload`，但 status frame、mode sync event、write result、BLE status resp 使用不同解析路径。
- Impact: Harness 需要分别模拟多种 response/event。
- 是否当前阻塞: 否。

## Device-state ownership debt

### 自动审批依赖 freshness，状态路径复杂

- Evidence: `ApprovalService` 要求 fresh connected physical status；`BleManager` 有 `PhysicalStatusFreshness`、`acceptedPhysicalStatus`、thread local approval status。
- Impact: 安全性较好，但测试必须覆盖 stale/cached status，否则容易误批。
- 是否当前阻塞: 否，已有测试但 Harness 需保留。

### 工作模式同步有多输入

- Evidence: UI selected mode、`0x92` ACK、`0x9B` mode sync、`0x00` status 都会影响模式。
- Impact: race/stale 回报风险。
- 是否当前阻塞: 否，`WorkModeSynchronizer` 是保护点。

## Transport coupling

### `BleManager` 名字与职责不匹配

- Evidence: `BleManager` 同时管理 USB HID、BLE TCP bridge、status freshness、request lock、recovery、capability gate。
- Impact: 阅读成本高，未来 Harness 需要按“DeviceManager/TransportManager”理解，而不是按名字只测 BLE。
- 是否当前阻塞: 否。

### OLED 写入强依赖 USB，但入口分散

- Evidence: `OledUploadService.validateUploadPlan()` 和 clear/upload 流程检查 USB；UI 多处可打开动画配置。
- Impact: 断连/传输切换时用户路径容易踩到限制。
- 是否当前阻塞: 对 BLE-only 使用场景可能阻塞。

## Error handling

### 多数错误反馈为状态文本或 Alert 混用

- Evidence: `studioState.syncStatus`、Alert warning/error、日志、弹窗 progress 各自显示错误。
- Impact: 自动化 Harness 需要观测多个 surface；用户也可能错过错误。
- 是否当前阻塞: 否。

### 命令 timeout 固定 15 秒

- Evidence: `RESPONSE_TIMEOUT_MS = 15000`。
- Impact: 大量命令或固件忙时用户等待长；短交互失败也要等。
- 是否当前阻塞: 否。

## Test gap

### UI 端到端测试不足

- Evidence: 存在少量 view unit tests，但未看到完整 JavaFX E2E 截图/用户流程测试。
- Impact: UI 信息架构和 disable/loading/error 状态容易回归。
- 是否当前阻塞: 否。

### BLE driver exe / GATT integration 不在测试范围

- Evidence: Java 测试覆盖 `BleManager` 和 `UsbHidTransport`，但外部 `BLE_tcp_driver.exe` 不在本 repo。
- Impact: BLE/Firmware 联调风险无法由当前 repo 单测关闭。
- 是否当前阻塞: 对 Desktop Harness 是阻塞项。

### 固件真实设备协议兼容只能部分由 fixture 覆盖

- Evidence: 只有 `ahakey-protocol-3.2.json` golden 覆盖 `0x9F`、`0x9D`。
- Impact: 多数命令缺少 golden frame/response fixture。
- 是否当前阻塞: 否，但 Harness 优先级高。

## Developer-only UI 泄露

- Evidence: Hook 安装检测、日志、WCHISP 环境诊断、BLE driver 进程控制对普通用户可见。
- Impact: 普通用户可能误触，支持成本增加。
- 是否当前阻塞: 否。

## Naming / Typography / Visual inconsistency

- Evidence: Java 类名仍有 `BleManager` 管 USB；UI 文案混有中文硬编码和 i18n resources；部分菜单项中文硬编码如“屏幕动画”。
- Impact: 可维护性和本地化一致性风险。
- 是否当前阻塞: 否。

## 最大风险摘要

1. BLE driver/GATT 契约在当前 Java 仓库内不完整。
2. `BleManager` 职责过宽，任何 transport 改动影响连接、审批、同步、OLED。
3. `0x90` 语义重叠。
4. UI 设备信息弹窗混合用户/维护/developer 功能。
5. HID code 逻辑分散。
6. 状态 ownership 双层，需要守住 freshness/session token。
7. OLED 写入 USB-only 限制与多入口 UI 容易产生用户困惑。
8. 多数协议命令缺少 golden fixture。
