# WD-001 — CP3A 睡眠等待时间 Windows 联调

状态：DLA 草案。本文用于 Owner 一次确认范围；它不是实现批准记录，批准后才可进入 DIB 实现。

## Owner 指派与本轮目标
来源记录：`.ahakey-desktop-harness/evidence/owner-task-cp3a-sleep-wait-time.md`。

本轮目标是为 CP3A 固件联调定义 Windows 上位机“睡眠等待时间”功能的最小实现合同。它来自 Owner 显式指派，不是从 backlog、历史报告排序或 M1a 建议自动选中。

已确认产品/协议边界：
- UI 名称：睡眠等待时间。
- 说明：键盘无按键操作，且未收到上位机灯效、显示或配置指令达到设定时间后，将进入睡眠。
- 入口：主画布右上角 More / “Hawk 安装分发工具”弹窗 / 第一个“设备信息”卡片内；不新增卡片。
- 选项：永不、30 分钟、60 分钟、120 分钟。
- 固件 CP3A：`0x95` 是 self-persisting set/query；Windows 不发送 `0x04 save_config`。
- Windows 流程：`0x95 set -> wait 0x95 OK -> 0x95 query -> readback match`。
- 指定 CP3A HEX：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws1-cp3a-host-configurable-quiet-sleep-timeout\HID_Keyboard_582m_vibe_coding.hex`。
- HEX SHA256：`9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`。

## 实现范围与三仓依据
接收仓现状：
- `TopBar.showDeviceInfoDialog()` 已有 More 弹窗与第一个“设备信息”卡片，当前显示连接状态、电量、设备名称、拨杆。这是唯一 UI 插入点。
- `StudioController.getBleManager()` 已存在，TopBar 可通过现有控制器访问 BLE 管理器。
- `BleManager` 已有同步发送、等待指定命令响应、USB/BLE transport 与命令锁；本项复用现有通信链路。
- `AhaKeyProtocol` 当前未声明 `0x95`；`AhaKeyResponseParser` 当前未解析睡眠等待时间响应。

Firmware 只读依据列在 `REFERENCES.json`：
- Owner 协议决定确认 `0x95` 自持久化，Windows 不发送 `0x04`。
- `APP/sub_main/command_solve.c` 已实现 `0x95` query/set、合法值校验、保存后 EEPROM 回读验证、返回状态码。
- `APP/services/standby_config.h`/`.c` 定义合法值 `0/30/60/120`，默认值和错误码。
- `.ahakey-harness/contracts/x1/protocol-commands.yaml` 标记 `0x95` 为官方 self-persisting sleep wait time 命令，`0x04` 仍是普通 save_config。
- CP3A candidate readiness 记录为可进入 Owner UAT；这不等于 Windows 联调已完成。

eternal 只作为历史参考；本合同不迁移 eternal 旧 UI，不继承旧选项，不把 eternal 行为当作接收仓实现依据。

允许修改路径与 `change.json` 一致：
- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
- `src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java`
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/view/TopBar.java`
- `src/main/resources/messages_zh.properties`
- `src/main/resources/messages_en.properties`

不新增第三方依赖，不整文件替换，不修改 Firmware、eternal 或 Harness 规则。

## 本轮适用基线与保持不变
本项不要求先批准全局产品基线，也不把历史问题自动纳入本轮。

保持不变：
- More / “Hawk 安装分发工具”弹窗入口、原有卡片、日志区、Hook/驱动安装分发相关功能。
- 设备信息卡片内现有连接状态、电量、设备名称、拨杆显示。
- 现有配置保存链路和 `0x04 save_config` 语义；只有“睡眠等待时间”这一项不走 `0x04`。
- USB/BLE transport、状态轮询、断连处理、语音输入、键盘注入、按键配置、OLED 图片和其它协议命令。
- 不做导航、主题、组件库、全局弹窗视觉重设计。

## UI 与操作语义
`ui_mode = minimal`。这是 CP3A 内部联调需要的最小产品入口，不是正式 UI 重设计。

位置：`TopBar.showDeviceInfoDialog()` 中第一个“设备信息”卡片，在现有连接状态、电量、设备名称、拨杆信息之后增加一行控制。

控件语义：
- 标签：睡眠等待时间。
- 说明：键盘无按键操作，且未收到上位机灯效、显示或配置指令达到设定时间后，将进入睡眠。
- 选项：永不、30 分钟、60 分钟、120 分钟。内部协议值分别为 `0/30/60/120` 分钟。
- 打开弹窗时读取固件当前值；读取到合法值则选中对应项。
- 读取到其它值时显示“当前值异常，请重新保存”，并允许用户选择四个合法值后保存。
- 未连接时控件禁用，提示“请先连接键盘”。
- 读取失败、保存失败、回读不匹配时给出明确状态提示，不假装成功。
- 保存中控件暂时禁用；成功后显示已保存的选项。

本轮不新增单独卡片、不新增页面、不新增正式设置中心入口。

## 协议、兼容与内部联调范围
命令：`0x95`。

查询帧：`AA BB 95 CC DD`。

设置帧：`AA BB 95 <lo> <hi> CC DD`，分钟值为 uint16 little-endian。

查询成功响应：`AA BB 95 00 <lo> <hi> CC DD`。

设置成功响应：`AA BB 95 00 CC DD`，随后 Windows 必须再发一次查询并检查回读值等于刚保存的值。

错误码按固件当前定义处理：
- `0`：OK。
- `1`：OUT_OF_RANGE，非法值。
- `2`：SAVE_FAILED，固化失败。
- `3`：INVALID_PAYLOAD，payload 长度错误。

语义边界：
- 对 Windows 来说，`0x95 OK` 表示固件已完成运行态更新、计时刷新和持久化保存；Windows 不需要、也不得为本项追加 `0x04 save_config`。
- 掉电保持由 Owner 真机 UAT 验证；Windows 的软件完成条件是收到 OK 后查询回读匹配。
- 第一版仅面向指定 CP3A 内部联调固件，不做 `0x9F` 能力发现，不把未知固件上的写入能力泛化为正式发布承诺。
- UI 只暴露合法四个值，因此非法值测试需通过协议/固件测试工具完成，不通过普通 UI 暴露非法输入。

## 先行实现与外部阻塞
Owner 批准本合同后，DIB 可在 allowed_paths 内实现：
- `AhaKeyProtocol` 增加 `0x95` 常量与 query/set 帧构造。
- `AhaKeyResponseParser` 增加睡眠等待时间响应解析和状态码表达。
- `BleManager` 增加读取、设置并回读校验的封装，复用现有同步命令等待机制。
- `TopBar` 在设备信息卡片内加入最小控件、状态提示、忙碌/断连处理和 i18n 文案。

阻塞条件：
- 若接收仓现有响应等待机制无法可靠区分 `0x95` set/query 响应，应先上报最小风险和选项，不自行发明新协议。
- 若 CP3A 实机返回格式与 Firmware 记录不一致，应报告差异，不清空状态、不改固件。

## 验收与恢复
机器验收：
- Java 17 Maven 编译通过。
- 静态核对：睡眠等待时间保存路径不发送 `0x04 save_config`。
- UI 静态核对：入口位于 More 弹窗第一个“设备信息”卡片内，没有新增卡片。

Owner 真机 UAT：
- 烧录指定 CP3A HEX，并确认 SHA256 为 `9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`。
- 上位机查询 `0x95`，记录当前睡眠等待时间。
- 设置 30，收到 `0x95 OK` 后立刻查询，确认回读是 30。
- 断电/重启键盘，再查 `0x95`，确认仍是 30。
- 同样测试 0 / 60 / 120；其中 0 表示永不自动进入 Quiet/Sleep。
- 发送非法值，确认返回失败，并且原值不变。
- 确认上位机不需要再发 `0x04 save_config`。
- 测 Sleep/Wake / real Sleep / display loop：休眠后唤醒，屏幕亮、状态正确、按键/连接恢复，不能出现自动反复醒来或黑屏循环。
- 快速烟测 WS1 生命周期：Power 短按/长按、Forget guard、USB fake-off、true-off USB 插入、single-host reconnect、USB/Mac wired lifecycle。

完成定义：WD-001 只代表 CP3A 内部联调功能完成并经对应验证，不代表整机版本发布通过。

## 本轮明确排除和遗留
明确排除：
- 不启动 M1a，不要求 Owner 选择迁移候选。
- 不做全仓调查或完整产品基线讨论。
- 不迁移 eternal UI，不加入 eternal 旧选项。
- 不新增正式设置页、独立睡眠卡片、全局能力发现或发布级兼容矩阵。
- 不修改 Firmware、eternal、Harness 规则。
- 不运行固件构建、烧录、产品构建、应用或设备操作。

遗留：
- 正式发布前是否需要能力发现、旧固件禁用策略、视觉精修和多语言补全，可另立任务。

## 批准方式
Owner 确认点：

是否批准 DIB 按 WD-001 合同，仅修改 `change.json` 中列出的 allowed_paths，实现 CP3A “睡眠等待时间”内部联调支持？

批准后 DLA 才会登记 approve 并派发实现；未收到明确批准时保持 `CONTRACT / WAIT_OWNER_TASK`。
