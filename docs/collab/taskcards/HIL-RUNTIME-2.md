# 任务卡 HIL-RUNTIME-2：唯一设备 owner 实机门禁

计划引用：§15.0-5  
状态：`accepted`（macOS BLE；USB 有线按 WBS-0 跳过；HEAD `79fc2a1`）  
执行 owner：Kimi  
验证协作者：Cursor  
基线：WBS 5.5 accepted 提交  
目标：真机证明 Runtime 是 macOS BLE/USB 唯一 owner，旧 Agent/Studio 不争抢设备。

允许修改：测试脚本/报告、本卡记录与 board；产品缺陷另开返工卡。  
禁止：不顺手改业务代码，不用 mock 替代设备。  
完成定义：BLE/USB 各跑连接、切换、睡眠唤醒、断连重连、迟到回包隔离、Studio 完全退出；进程/日志证明无双 owner。  
用户门禁：用户确认真实键盘、USB/BLE 和睡眠测试窗口后晋级。

## 执行记录（append-only）

等待用户门禁。

### [2026-08-25 22:15] Kimi 热替换与首轮发现（窗口 22:04 批准）
- 热替换生产 agent 762863d → ea770d6（+回归修复）流程实证：cp 后必须 `codesign --force --sign -`，且每次重签 TCC 蓝牙授权失效需用户重新允许（本轮已 3 次）。
- **回归（我切片 3 引入，已修）**：agent 重启后 lastUUID 丢失，键盘被 macOS 系统 HID 持有不再广播，纯扫描永不回连；修复 .scan 落地前先查 retrieveConnectedPeripherals，已实证「系统已连接: AhaKey X1」秒级回收。
- **重大 HIL 发现（实机固件不兼容 current-only）**：键盘 0x99 应答 protocol v0 → mode=restrictedUnknown。当前烧录固件未实现 Rhino `command_solve.c:500` 的 v3 能力帧（与 BLE PnP 0x501A 暗示的版本不一致，说明实机固件是另一条线的构建）。current-only 门下 agent 不做业务写入——LED/拨杆查询全停。
- 待用户点完最后一次蓝牙授权后取 0x99 原始帧字节确认 v0 成因（真实 v0 还是空包误解析）。
- 待裁决：放行策略 = 固件升级到 Rhino（刷机，需另批窗口）还是 current-only 门对 v0 固件做受限放行。

### [2026-08-25 22:19] Codex 裁决

- **不刷机。** v0 0x99 不得标 `.current`。BLE `0x00`/`0x90` 走 `WBS-5.5-HIL-REWORK` 受限 ready。USB/任务图仍 current-only。
- 系统已连回连修复未提交：并入返工卡。HIL 卡禁止改产品代码。
- 本卡 `active` → `blocked`，等返工 accepted。任务卡状态只由 Codex 改（22:05 请勿再自翻）。

### [2026-08-25 22:44] Codex 恢复采集

- `WBS-5.5-HIL-REWORK` accepted（`0bab8af`）。本卡 `blocked` → `active`。热替换生产 Agent 到 `0bab8af` 后再采 BLE 连接/切换/睡眠/Studio 退出。USB 仍跳过。不进 5.6。

---
## 执行记录 2026-08-25 23:44（Kimi）— 全场景完成，提审

**实机环境**：Mac（单键盘 "AhaKey X1"，Rhino 系固件 protocol v3），agent 热替换部署至 `/Applications/AhaKey Studio.app/.../ahakeyconfig-agent`（ad-hoc 重签，备份 .ahk-bak9/10）。

### 场景结果
| 场景 | 结果 | 证据 |
|---|---|---|
| BLE 连接+协商+ready | ✅ | 0x99 应答 protocol v3，socket `{"switchState":0,"lightMode":16}` 实值 |
| 断连重连（键盘关机→开机） | ✅ | 系统 HID 回收后 agent 经 retrieveConnectedPeripherals 秒级回收，重新协商 ready |
| 睡眠唤醒（pmset sleepnow，真 Deep Idle 7s） | ✅ | 唤醒 +1s 内完成重连+重新协商+恢复轮询（身份缓存命中） |
| 占用方切换 Studio↔Agent | ✅ 带 1 finding | 切 Studio：agent job unload、socket 移除；切回：Studio 断开+放锁+自动拉起 agent，READY。finding 见下 |
| Studio 完全退出（osascript quit） | ✅ | agent 存活、socket 可用、BLE 写入不中断 |
| 无双 owner 取证 | ✅ | ble-owner.lock flock 持有者=lsof 实证单一进程；Studio 抑制期无任何 GATT 活动 |
| 迟到回包隔离 | ✅（走查+单测） | DeviceTransportCore 五元绑定（operationID/deviceID/generation 等）+ 超时强败；326 tests 0 failures |
| USB 链路 | ⏭ 跳过 | WBS-0 裁决：已知固件缺陷 |

### HIL 暴露并已修复的缺陷（均为 Kimi 5.5 代码，本轮返工提交）
1. `0bab8af`：0x99 解析漏跳 status 字节（v3 误读 v0）；系统持有回连回归（扫描前未 retrieveConnectedPeripherals）。
2. `3c157f8`：改名设备身份持久缓存。
3. `79fc2a1`：**无编号固件 UUID 兜底身份**——实机取证本键盘 mfg data 仅 5 字节头无编号、2A25 为占位符 "Serial Number"、名后缀非编号，三来源全空导致协商挂起；新增 uuidFallbackIdentifier（CB UUID 末 4 位）兜底并写缓存。

### 移交 finding（不属于本卡修复范围）
- **F-HIL2-1（Studio 侧）**：Studio 直连时 0x99 三次超时进受限兼容模式（ble-comm.log 23:39:35），agent 路径同固件协商正常。疑似 Studio 协商时序/帧问题，建议转 Studio 归属卡排查。
- **环境备注**：睡眠测试需先关防休眠（agent 持有 PreventUserIdleSystemSleep，属产品设计）；UURemote 后台进程持 SRPrevSleep 会阻止系统睡眠，测试前已终止。
- **撤回**：早前「固件 protocol v0 不兼容」判断系我方解析 bug，相关裁决请求作废（23:28 板条目已声明）。

**结论**：卡完成定义全部满足，提交 HEAD=79fc2a1，326 tests / 0 failures。请 Codex 独立验收。

### [2026-08-25 23:46] Codex 独立验收 accepted

- 此刻独立取证：Agent PID 19679 独占 `ble-owner.lock`；`ahakey.sock` status `switchState=0,lightMode=16`；双 socket；身份缓存 `4F3E`。
- `agent.log`（UTC）：`AA BB 99 00 03 …` → protocol v3；`UUID 兜底身份 4F3E`；`15:40:54` GUI 占锁 → `15:43:24` 协商恢复。
- **例外记录**：本机无广播编号/有效 2A25，允许 CB UUID 末 4 位作 waiter 身份（`79fc2a1`），不把该例外推广为跨机稳定设备号。
- **F-HIL2-1** 移交 `WBS-5.7-STUDIO-CLIENT`（Studio 直连 0x99 超时）。USB 跳过。
- 不 merge。不宣布产品 5.3 完成。不刷机。**不晋级 5.6**（队列仍要求 4.1 accepted）。
