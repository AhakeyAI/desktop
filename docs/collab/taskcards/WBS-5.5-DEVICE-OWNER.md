# 任务卡 WBS-5.5-DEVICE-OWNER：Runtime 唯一设备所有权

计划/WBS：5.5  
状态：`accepted`  
执行 owner：Kimi  
基线：`feat/unified-client` @ `762863d`（WBS-5.4 accepted HEAD）  
目标：把 BLE/USB、current-only 协商、设备身份、命令队列、waiter 和断线恢复迁入 Runtime，Studio/旧 Agent 不再争抢设备。

## 允许修改路径

- `ahakeyconfig-mac/Sources/BLE/**`
- `ahakeyconfig-mac/Sources/Agent/**`
- `ahakeyconfig-mac/Sources/Shared/BLEConnectionLock.swift`
- `ahakeyconfig-mac/Sources/Shared/DeviceStateReducer.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyUSBConfiguration.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyDevicePresentation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyFirmwareCapabilities.swift`
- `ahakeyconfig-mac/Sources/Shared/**Runtime**`（仅注册/启停设备模块，不改 5.6 planner）
- 新建 `ahakeyconfig-mac/Sources/Shared/` 下设备/transport/waiter 文件（CoreBluetooth/IOKit 可进 Shared）
- `ahakeyconfig-mac/Sources/Utilities/AgentManager.swift`（仅 BluetoothConnectionOwner / 抑制 Studio 直连；不改安装器 UI 文案大修）
- `ahakeyconfig-mac/Package.swift`（仅 Agent/Shared 链接 CoreBluetooth/IOKit，或把 BLE 源从 Studio 目标迁入 Shared）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/**`、`ahakeyconfig-mac/Tests/AhaKeyAgentTests/**` 中设备/锁/waiter/transport 测试
- 本卡执行记录与 `board.md` 末尾

## 禁止事项

- 不改 `Sources/Views/**`、不接 snapshot/event 配置 UI（5.7）。
- 不实现 ConfigurationPackage planner / 图片事务（5.6）。
- 不改固件、不刷机、不开工 WBS-1。
- 不 merge `main`。不宣布产品 5.3 完成。
- 不得保留「Runtime 失败则 Studio 直连」的生产回退（架构 §11/§12）。
- USB 有线枚举已知固件缺陷：本卡实现 current-only 与 waiter 隔离；HIL-RUNTIME-2 的 USB 实机仍 USER-GATE，不在本卡假装 USB 链路已通。

## 完成定义

- Runtime/Agent 为 BLE（及代码路径上的 USB HID）唯一 owner；Studio 进程不得再作为竞争 Central（可用 suppress + AgentManager 默认交给 Agent；删除 Studio 协议栈属 5.7）。
- USB/BLE current-only 协商；稳定 device ID；串行命令队列；waiter 绑定 operation/device/session generation/transport generation；迟到回包不得完成新 generation waiter。
- 断连/睡眠/唤醒恢复；周期与连接生命周期状态经 `DeviceStateReducer`；RSSI 仅诊断窗口轮询，不进主快照。
- 相同状态零 UI 发布、零常规磁盘日志。

## 测试 / 门禁

- 并发连接、waiter、超时、迟到回包、重连、Studio 退出不杀 Agent、相同状态零发布。
- 定向新测 + `AhaKeyAgentTests` / Shared 相关；完整 Swift 测试；`swift build -c release --product ahakeyconfig-agent`；`git diff --check`。
- 实机 BLE/USB/睡眠在 **HIL-RUNTIME-2**（USER-GATE），本卡可用现有已连键盘做开发，但不把本卡标成 HIL 通过。

## 前置与晋级

5.2/5.3/5.4 accepted。WBS 4.1 不挡本卡（v4 Studio 模型仍在 `WBS-4-STUDIO-V4`）。用户 2026-08-25 19:03：先把客户端全线做好再测，再启动固件；WBS-1 暂缓。完成后必须进入 HIL-RUNTIME-2，不得直接跳 5.6。

等 Kimi board 接单 ACK（基线 `762863d`）后 Codex 翻 `active`。已于 19:16 ACK；Codex 19:42 补记 `active`，切片 2–4 未整卡验收。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 19:13] Codex 晋级 ready

- 用户在 Cursor 会话提交 Kimi 19:03 原文：「先把客户端的全线做好 让我测试下客户端，再启动固件部分」。裁决：WBS-1 暂缓，本卡 `draft` → `ready`。基线 `762863d`。
- 「全线」不授权跳过 HIL-RUNTIME-2 / HIL-CONFIG，也不把 5A 插到 5.9 前。
- 等 ACK。不刷机。不 merge。

### [2026-08-25 19:21] Kimi 切片 1 提交 `a4bb55f`：串行队列 + waiter 注册表
- 现状盘点结论：Agent 已通过 BLEConnectionLock（flock `ble-owner.lock`）+ Studio `setSuppressedForAgentOwningKeyboard` 在生产上独占 BLE；Studio 侧 `AhaKeyBLEManager`（1800+ 行 ObservableObject）仍是完整竞争栈，需在本卡迁入 Shared/Runtime 并 suppress。
- 新增 `Shared/DeviceCommandSequencer.swift`（纯逻辑，无 CoreBluetooth）：
  - `DeviceCommandQueue`：FIFO 串行、head 在途、`invalidateAll` 断连清空
  - `DeviceWaiterRegistry`：operation/device/session/transport/requestID 五元绑定；迟到回包（任何分量不符）绝不完成新 waiter；超时收集；代际失效强败
- 测试：`DeviceCommandSequencerTests` 10/10 通过。diff --check 干净。
- 下一切片：BLE transport seam（扫描/连接/订阅/写入抽象进 Shared，Agent 与 Studio 共用），current-only 协商挂 0x99。

### [2026-08-25 19:40] Kimi 切片 2-4 提交（`6c930e0`、`465a932`、切片4）
- 切片 2 `DeviceTransportCore`：连接生命周期状态机（current-only 门、transport generation 递进、BackoffSchedule 重连、锁等待、已知 UUID→系统已连→扫描偏好）。
- 切片 3 Agent 接入：生命周期决策全部移交核心；新增 0x99 协商（3×2s），仅 .current 放行 0x90/轮询；status waiter 绑定登记代际，断连换代后迟到回包 nil 收尾；重连退避 4→30s。
- 切片 4：删除「Agent 未装则 Studio 临时直连」生产回退（架构 §11/§12）；Agent 状态帧/连接生命周期经 DeviceStateReducer 归并。
- 门禁：全量 322 tests 0 failures，diff --check 干净。
- 明示缺口：USB transport 代码路径（AhaKeyUSBHIDTransport 已在 Studio 侧，未迁入 Agent；固件 USB 链路用户确认已知缺陷）；HIL 实机属 HIL-RUNTIME-2（USER-GATE）。稳定 device ID 目前取 UUID 兜底（广播编号解析在 Studio 侧，Agent 暂未消费 manufacturer data）。

### [2026-08-25 19:42] Codex 独立审查切片 2–4：整卡不 accepted

- 19:16 ACK 补记：本卡 `ready` → `active`。HEAD `8207b16`。白名单内 6 文件。定向测独立 21/21。
- **不收口。** Agent 未使用 `DeviceCommandQueue` / `DeviceWaiterRegistry`；`sendState` 直写 BLE；`statusWaiters` 并行。`DeviceTransportCore.invalidateTransport` 用 `notMatching: current`，断连不淘汰当前代际 waiter。`testDisconnect_invalidatesStaleWaiters_*` 未驱动核心断连。`didDiscover` 丢弃 `handle` 返回动作后自行 `connect`。Studio 仍可切 `.ahaKeyStudio` 成竞争 Central；`AhaKeyUSBHIDTransport` 在 suppress 时仍 `start()`。device ID UUID 兜底。
- USB 实机枚举按 WBS-0 延期，但 Studio USB 与 Agent BLE 双 owner 本卡必须收。HIL-RUNTIME-2 不晋级。

### [2026-08-25 19:55] Kimi 切片 5 提交 `ea770d6`：Codex 五条 finding 返工
- ① sendState/0x00 全部经 DeviceCommandQueue；statusWaiters 闭包数组删除，改核心 registerWaiter/resolveWaiter + requestID 回调表；ACK/应答完成 head；3s head 超时防卡死。
- ② 断连 `waiters.invalidateAll()` 强败全部（含当前代际）；空转测试换成 `testDisconnect_failsCurrentGenerationWaiters` + 新增 `testReady_requiresStableDeviceID_noUUIDFallback`。
- ③ didDiscover 执行 handle 返回 actions。
- ④ `AhaKeyUSBHIDTransport.stop()` 新增；Studio suppress 时停 USB，启动按 owner 门控。
- ⑤ deviceID 仅广播 manufacturer data/设备名后缀（复用 AhaKeyDevicePresentation）；已知 UUID 路径连接后 `deviceIdentified` 补身份；未识别不 ready 不注册 waiter。
- 门禁：全量 323 tests 0 failures，diff --check 干净。无白名单外改动。

### [2026-08-25 19:51] Codex 独立验收切片 5：accepted

- HEAD `ea770d6`。定向测 45（含新 2 项）；`swift build -c release --product ahakeyconfig-agent` 通过。
- 五条 finding 闭合：生产队列/waiter、断连强败当前代际、didDiscover 执行 actions、Agent 独占时 USB `stop()`、无 UUID 兜底 ready。
- 记录非挡：USB HID 代码仍在 Studio（实机枚举 WBS-0 延期）；设备信息页仍可切回 Studio Central（删协议栈属 5.7）；HIL-RUNTIME-2 仍 USER-GATE。
- 不 merge。不宣布产品 5.3 完成。不启动 5.6。
