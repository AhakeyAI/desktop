# BASELINE_SUMMARY

## 10 分钟概览

这是一个 Java 17 + JavaFX 的 Windows 上位机。当前不是 clean-room 原型，而是已经有较完整功能的桌面应用: 设备连接、键盘配置、语音输入、AI Hook 联动、灯效/OLED、固件升级、更新发布、Windows native 输入/USB HID 都已经在代码里。

## 软件当前大模块

1. UI 主应用:
   - `App` 组装主窗口、托盘、语言、语音初始化。
   - `TopBar + CanvasPane + InspectorPane + StatusBar` 构成主界面。
2. 应用总线:
   - `StudioController` 持有状态、连接、同步、Hook、语音、固件更新服务，是多数用户操作的编排中心。
3. 设备通信:
   - `BleManager` 实际是 USB/BLE 双 transport 设备管理器。
   - 优先 USB HID，失败后连接 BLE TCP bridge。
4. 协议:
   - `AhaKeyProtocol` 负责编码 `AA BB ... CC DD`。
   - `AhaKeyResponseParser` 负责 response/capability/config/OLED 等解析。
5. 配置和草稿:
   - `StudioState` 是编辑草稿。
   - `DeviceSyncService` 把草稿转换成设备命令列表。
   - `StudioStore` 做本地持久化。
6. Voice / AI:
   - 本地语音: Sherpa-ONNX + microphone + keyboard injection。
   - 物理语音键: Windows hook + F18/raw route。
   - AI Hook: Claude/Cursor/Codex/Kimi hook server -> 任务灯/审批。
7. Firmware / Maintenance:
   - `FirmwareUpdateService` + WCHISP flasher/runtime。
   - 设备维护 UI 包含固件更新和恢复出厂。
8. Release / Update:
   - Maven package。
   - jpackage + WiX Windows installer。
   - Release 脚本强制 BLE driver 和可选 WCHISP runtime 打包校验。

## 当前 UI 信息架构

主 UI 是单窗口、非多页路由:

- 顶部 TopBar:
  - 连接状态、电量、拨杆。
  - 连接/断开。
  - BLE 驱动。
  - AhaType。
  - 语音服务。
  - 编辑配置/保存配置。
  - 更多菜单。
- 左侧 Canvas:
  - 4 个键盘模式。
  - 键盘部件热点: K1/K2/K3/K4、灯条、OLED、拨杆。
- 右侧 Inspector:
  - 根据选中部件显示配置:
    - K1 语音短按/长按动作。
    - K2-K4 快捷键/宏/描述/模拟。
    - 灯条亮度、AI 灯效、任务显示。
    - OLED/屏幕动画。
    - 拨杆自动/手动审批。
- 设备信息弹窗:
  - 设备信息、待机、固件维护、配对、支持、Hook 管理、日志都堆在一个长滚动弹窗里。

## Windows ↔ Firmware 通信怎么走

### Transport

- Desktop 自动选择 transport。
- 首选 USB HID:
  - Windows HID JNA。
  - 设备匹配 `VID_413C&PID_2107`。
  - report 内部用 `0xA1` command / `0xA2` data。
- 备选 BLE:
  - Java 连接本机 TCP `127.0.0.1:9000`。
  - 外部 `BLE_tcp_driver.exe` 负责真实 BLE。
  - TCP packet 是 `[type][length LE][data]`。

### Protocol

- 应用协议帧:
  - Header `AA BB`
  - Command byte
  - Payload
  - Trailer `CC DD`
- ACK/response:
  - `cmd/status/payload`
  - status 0 成功，非 0 映射为设备错误。
- 一般命令 timeout 15 秒。
- 大数据 OLED 写入 4K block，失败最多重试 3 次。

### 关键命令

- `0x00` status。
- `0x73` key mapping/macro/description。
- `0x84/0x85/0x91` 灯效/亮度。
- `0x92/0x9B` 工作模式 set/sync。
- `0x80/0x81/0x82/0x83/0x93/0x94/0x9C` OLED/GIF。
- `0x95` 待机。
- `0x96` 出厂重置。
- `0x97` 语音键配置。
- `0x98/0x99/0x9A` 任务灯。
- `0x9D` bounded config read。
- `0x9F` capabilities/device contract。

## 值得 Preserve 的现有架构

- `AhaKeyProtocol` / `AhaKeyResponseParser`: 协议集中，适合作为 Harness golden source。
- `DeviceSyncService.commandsForModes()`: 草稿到设备命令的映射点清晰。
- `BleManager` 的 request lock + session token + stale receiver 防护: 这是实际抗竞态逻辑。
- `PhysicalStatusFreshness` / `ApprovalService`: 自动审批依赖 fresh physical status，安全边界明确。
- `WorkModeSynchronizer`: 保护 UI 选中模式不被 stale 设备回报覆盖。
- WCHISP runtime contract/provider/runner: 对发布和固件更新有较多校验与测试。
- 现有测试覆盖面不错，尤其是 service/protocol/firmware/update。

## 最大风险

1. BLE driver/GATT 契约不完整在当前 Java 仓库中，Desktop Harness 不能只靠 Java repo 关闭 BLE 风险。
2. `BleManager` 名字叫 BLE，但实际管 USB、BLE、状态、recovery、ACK、capabilities，修改 blast radius 大。
3. `0x90 UPDATE_STATE` 语义重叠，代码已通过忽略 6-byte `0x90` 防止错误覆盖状态。
4. UI 信息架构里用户功能、维护功能、developer diagnostic 混在同一设备信息弹窗。
5. HID code 逻辑分散在 UI、model、protocol、sync service。
6. Device state 有 `BleManager.cachedStatus` 和 UI `DeviceStatus` 两层，必须守住 session/freshness。
7. OLED/GIF 写入要求 USB，但入口分散，BLE-only 时用户体验风险较高。
8. 多数协议命令没有 golden fixture。
9. 本地语音、Windows hook、firmware capability gate 相互耦合，需防止误触发 F18/语音路由。
10. 发布脚本依赖外部 BLE driver、WCHISP、WiX/JDK/signature，release harness 要覆盖。

## 仍然 UNKNOWN 的事实

- `BLE_tcp_driver.exe` 的真实 GATT service/characteristic/scan/reconnect 实现。
- 固件源码内部如何处理每条命令。
- `CMD_CHANGE_NAME 0x01` 和 `CMD_CHANGE_APPEARANCE 0x02` 是否被旧 UI/旧固件实际使用。
- `VoiceInputPanel.fxml` 是否为历史遗留。
- `cloudAccount` 菜单项预期功能。
- 当前 UI 实际视觉是否有文字溢出/错位，未运行截图验证。

## 建立 Desktop Harness 下一步最该解决

1. 先建立协议 golden fixture:
   - 覆盖 `0x00/0x73/0x84/0x85/0x90/0x92/0x95/0x97/0x98/0x99/0x9B/0x9C/0x9D/0x9F`。
2. 建立 fake transport:
   - 模拟 USB HID 和 BLE TCP bridge。
   - 覆盖 ACK、timeout、stale response、transport reconnect。
3. 锁定 Feature -> Protocol matrix:
   - 每个 UI 操作断言发出的命令序列。
4. 专门保护高风险状态:
   - 工作模式 stale report。
   - 自动审批 freshness。
   - USB/BLE fallback。
   - OLED USB-only。
5. 建立 UI smoke harness:
   - 启动、未连接、连接中、已连接、错误、保存、断开、维护弹窗。
6. 将 BLE driver/GATT 契约补成可测试 artifact:
   - 至少把当前 exe 的外部协议和 GATT UUID/notify/write 行为记录成 fixture 或 adapter contract。
