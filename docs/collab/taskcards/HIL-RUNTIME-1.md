# 任务卡 HIL-RUNTIME-1：Runtime/Hook/拨杆第一次真机门禁

计划引用：§15.0-4  
状态：`accepted`  
执行 owner：Kimi  
验证协作者：Cursor  
基线：`feat/unified-client` @ `b49e83e`（5.3 orchestrator accepted；产品 5.3 仍待本卡 HIL）  
目标：使用现有固件和至少一把真实键盘，验证 Runtime/Hook/拨杆后台链路和性能，不等待统一固件。

## 允许修改路径

- 只允许测试脚本、测试报告、任务卡执行记录和 board 末尾；发现产品缺陷必须另开返工卡，不在 HIL 卡中顺手改业务代码。

## 禁止事项

- 未经用户确认不得安装新包、刷固件、改全局 Hook 或关闭其他应用。
- 不用无设备 mock 替代真机，不把统一固件平台识别/宏验收混入本卡。

## 完成定义

- Hook ↔ Runtime socket；Cursor 上推自动批准、下推原生手动批准、断开键盘不硬拒绝。
- Studio 完全退出后 AI 检测与防休眠继续；断连/重连恢复，后台响应不超过 2 秒。
- 真实键盘连接连续 30 分钟，采集 CPU/RSS；相同状态轮询零 UI 发布、零常规磁盘日志。
- Kimi 负责 Runtime/设备证据，Cursor 负责 IDE/CLI 真实工具矩阵；报告列出环境、版本、失败原始证据。

## 用户门禁

Codex 只有在用户确认键盘、USB/BLE 方式和 30 分钟测试窗口后才能晋级 `ready`。

## 晋级 `ready` 后的执行清单（预写，未授权开跑）

Kimi（Runtime/设备）：

- 现有固件 + 用户指定的 USB 或 BLE；不断开其他应用、不刷机、不改 `~/.cursor/hooks.json`。
- 证据：Hook ↔ Runtime `hook.sock`；Studio 完全退出后 AI 检测与防休眠仍在；断连/重连恢复；后台 ≤2s；连续 30 分钟 CPU/RSS；相同状态轮询零 UI 发布、零常规磁盘日志。
- 缺陷另开返工卡，不在本卡改业务代码。

Cursor（IDE/CLI 工具矩阵）：

- 仅在用户窗口内：automatic 上推允许、manual 下推原生、键盘断开 fail-open 不硬拒绝。
- 报告含 Cursor 版本、agent SHA `b49e83e`、失败原始 stdout。

## 执行记录（append-only）

### [2026-08-24 16:24] Codex 冻结基线，保持 USER-GATE

- 5.3 orchestrator 卡已 accepted @ `b49e83e`。本卡基线冻结为该提交。
- 状态仍为 `draft / USER-GATE`。用户确认真实键盘、USB/BLE 方式与 30 分钟窗口后才晋级 `ready`。
- 不启动 WBS-1。不安装新包、不刷固件、不改全局 Hook。

### [2026-08-24 23:00] Codex 解除 USER-GATE，晋级 ready

- 用户确认：至少一把真实键盘；USB 或 BLE 均可（Kimi 选择，优先 USB）；立即开始 ≥30 分钟窗口。
- 本卡 `draft / USER-GATE` → `ready`。基线仍冻结 `feat/unified-client` @ `b49e83e`。保持 ready 直至 Kimi 接单 ACK，再由 Codex 翻 `active`。
- 不刷机、不装新包、不关其他应用、不启动 WBS-1、不宣布产品 5.3 完成。业务代码缺陷另开返工卡。
- 报告隔离：Kimi → `docs/collab/reports/HIL-RUNTIME-1-kimi.md`；Cursor → `docs/collab/reports/HIL-RUNTIME-1-cursor.md`。禁止双写同一报告。
- Cursor 在 Kimi ACK 且 Runtime `hook.sock` 存活后再跑 IDE/CLI 矩阵；`~/.cursor/hooks.json` 仅允许 HIL 短窗口覆盖并测完逐字恢复。

### [2026-08-24 23:03] Codex ACK → active，设备阻塞

- 已收 Kimi 接单：23:01（USB 意向）与 23:05（BLE + 键盘不在线）。裁决传输为 **BLE**（`SPUSBDataType` 无 AhaKey/CH58x）。23:01 USB 意向作废，除非用户改插 USB。
- 本卡 `ready` → `active`。基线仍 `b49e83e`。`hook.sock` 已在。
- 执行阻塞：键盘未上线（`switchState=null`，`current-ide-state.json` 停在 16:21）。Cursor IDE/CLI 矩阵不得开工。
- 不启动 WBS-1。不宣布产品 5.3 完成。

### [2026-08-24 23:11] Codex：用户确认 BLE 上电；socket 文件存在

- 用户确认键盘已上电，继续 **BLE**（未改 USB）。
- 独立核查：`ahakey.sock`（Aug 23 20:22）与 `private/hook.sock`（Aug 24 11:35）均为 `srw-------` 存在。23:06「socket 缺失」不成立——Unix socket 不能用 `test -f`。禁止为此重启 Studio/Agent。
- `current-ide-state.json` 仍停在 16:21。Kimi 须立刻 BLE 连接确认后开始采证。Cursor 矩阵仍等 Kimi 确认设备在线。

### [2026-08-24 23:12] Codex：键盘已在线；hook.sock 文件在但无监听

- 独立 `{"cmd":"status"}` → `{"switchState":0,"lightMode":16}`。`current-ide-state.json` mtime 23:12。`ahakey.sock` 已重建（mtime 23:12）。23:11「键盘仍不在线 / socket 缺失」过期。
- `private/hook.sock` 文件仍在，`connect` 被拒绝。Cursor 矩阵不得开工，直到 hook 监听恢复。Kimi 用 connect 探测，不用 `test -f`。不得重启 Studio/Agent，除非用户另批。不改业务代码。
- 30 分钟 CPU/RSS 从本独立证据起可开始（设备已连）。

### [2026-08-24 23:19] Codex 中期裁决

- 接受 Kimi 30m 窗口已开始（Agent PID 8857，PPID=1）。独立 `status` 仍为 `switchState=0/lightMode=16`；`hook.sock` 仍 `Connection refused`。
- **F1**：确认缺陷。已开 `HIL-RUNTIME-1-HOOK-SERVER`（`draft`，不 ready）。Cursor 矩阵继续停手。
- **F2**：并入 `WBS-5.4-LIFECYCLE`，不开并行返工卡。
- **F3**：候选，等 30m 结束原始 `pmset` 证据；本卡不改业务代码。
- 用户目视灯效：**未见变化**。记入本卡，不宣称灯效 HIL 通过。

### [2026-08-24 23:23] Codex 心跳：设备状态变 null

- 独立 `{"cmd":"status"}` → `{"switchState":null,"lightMode":null}`。`current-ide-state.json` 停在 23:21:49。Agent 8857 仍在。`hook.sock` 仍拒绝 connect。
- 23:12 起的连续连接窗口在 23:21 左右中断。不开始断连测试，不改业务代码。

### [2026-08-24 23:25] Codex 记 Kimi 灯效补证（不改裁决）

- Kimi 23:25：用户确认 PermissionRequest 状态 1 灯效可见并 5s 回落。与 23:19 PreToolUse 目视未见并存。F1–F3 仍按 23:19 裁决。30m CPU/RSS 未结束，本卡不 review。

### [2026-08-24 23:38] Codex 独立心跳（采集未结束）

- `ahakey.sock`（Application Support 根路径，非 `private/`）connect 成功；`{"cmd":"status"}` → `{"switchState":1,"lightMode":1}`，约 48ms。Agent 8857 PPID=1 仍在。采集器 22782 仍在（约 11/30 min）。
- `switchState` 相对 23:26 重连后的 `0` 变为 `1`（拨杆位变化，记入证据，不另开用户操作）。`hook.sock` 仍 Connection refused。报告目录仍空。本卡不 review。Cursor 矩阵仍停手。不晋级 HOOK-SERVER，不启动 WBS-1。

### [2026-08-24 23:44] Codex 10m 心跳

- 独立：采集器 22782 已跑 18:02 / 30m（自约 23:26 起），预计约 **23:56** 写报告。Kimi 23:41 写「约 25 分钟、23:46 完成」与该 PID 不符，不以 23:16 起算连续 30m。
- `status` `{"switchState":1,"lightMode":1}` ~43ms；ide-state 23:44:44 仍更新；Agent 8857 PPID=1。`hook.sock` 仍 Connection refused。`docs/collab/reports/` 仍空。本卡不 review、不验收。Cursor 矩阵仍停手。不启动 WBS-1。

### [2026-08-24 23:46] Codex：Kimi 预估时点已过

- 23:46 无 `HIL-RUNTIME-1-kimi.md`。采集器 22782 仍在（19:27 / 30m）。独立 `status` 仍 `switchState=1/lightMode=1`。`hook.sock` 仍拒绝。不验收、不 review。

### [2026-08-24 23:55] Codex 10m 心跳

- 采集器 22782 仍在（28:41 / 30m），报告目录仍空。独立 `status` `{"switchState":1,"lightMode":1}` ~38ms；ide-state 23:55:23；Agent 8857 PPID=1。`hook.sock` 仍 Connection refused。Kimi 23:46/23:51 已改口对齐 23:56。本卡不 review。Cursor 矩阵仍停手。不启动 WBS-1。

### [2026-08-24 23:58] Codex 拒绝验收，暂停本卡

- 已读 Kimi 报告与 23:56 回传。独立 `hook.sock` 仍 Connection refused；Agent 8857 仍在（RSS 14096，%CPU 4.6）。`pmset -g assertions` 无 Agent 持有断言（仅 bluetoothd / UURemote）。
- **拒绝 accepted。** 完成定义未满足：Hook↔Runtime 失败（F1）；Cursor IDE/CLI 矩阵未跑；CPU/RSS 连续样本为 0（采集器 `ps ... | grep` 用法错误，不是产品缺陷）；报告无原始 `pmset`（F3 不得标通过）。
- **不得把 23:12–23:56 算成一段连续 30m。** 23:26:42–23:56:43 仅证明重连后 ahakey.sock 连通（178/178，最大 252ms ≤2s）。
- Kimi「Studio 退出 / 断连 / 拨杆未执行」不成立：Studio 退出已在卡内发生并记 F2→5.4；断连/重连已于 23:26 完成；拨杆 `switchState` 0→1 出现在本报告首尾样本。用户现在不要再退 Studio、断电或额外拨杆。
- 本卡 `active` → `paused`。不启动 WBS-1。不宣布产品 5.3 完成。Cursor 矩阵仍停手。F2/F3 仍归 `WBS-5.4-LIFECYCLE`。
- 下一张唯一 `ready` 卡：`HIL-RUNTIME-1-HOOK-SERVER`。HOOK-SERVER accepted 后再恢复本卡剩余项（正确 CPU/RSS、Cursor 矩阵、F1 复验）。

### [2026-08-25 11:50] Codex：HOOK-SERVER accepted，本卡恢复 ready

- F1 listen 与 Cursor 三态已在 HOOK-SERVER 独立过。F2/F3 仍归 5.4，不作为本卡通过项。用户不要退 Studio、不要再停 Agent、不要额外拨杆。
- 剩余：Kimi 用正确 CPU/RSS 采集（`ps` argv 不得带 `| grep`）在真实键盘已连状态下重采连续样本。23:12–23:56 仍不得算一段连续 30m。
- 本卡 `paused` → `ready`。等 Kimi ACK 后 Codex 翻 `active`。不启动 WBS-1。不宣布产品 5.3 完成。不 merge。5.4 保持 draft。

### [2026-08-25 11:53] Codex ACK → active

- 已收 Kimi 11:51 ACK。本卡 `ready` → `active`。Kimi 现在可重采 CPU/RSS。不改业务代码。不启动 WBS-1。不 merge。5.4 保持 draft。

### [2026-08-25 12:37] Codex 独立验收 accepted

- 用户裁决：报告与原始样本齐则 Codex 可独立验收，不把 board `需要回复：否` 当阻塞。Kimi 12:32 心跳仍为否；采集器 PID 已退出；报告已写入。
- 独立计数：180 行 `ps -p 53021 -o %cpu=,rss=,etime=` 样本，12:05:51–12:35:52（跨度 1801s），间隔 10–11s，无 >12s 缺口。不得把 23:12–23:56 算入本段。
- CPU 0.0–6.3%（均值约 0.36%），RSS 12624–14784 KB（均值约 14112 KB）。全程 `switchState=0`。独立 `ahakey.sock` `{"cmd":"status"}` → `{"switchState":0,"lightMode":1}`。Agent 53021 仍在。
- 报告「汇总统计」块为空；以原始样本为准，不因此拒绝。`| grep` 仅出现在「无 | grep」说明句。
- F1 listen 与 Cursor 三态已在 `HIL-RUNTIME-1-HOOK-SERVER` @ `fa6c02e` 独立过。F2/F3 仍归 `WBS-5.4-LIFECYCLE`。
- 本卡 `active` → `accepted`。不宣布产品 5.3 完成。不启动 WBS-1。不 merge。不额外退 Studio / 停 Agent / 拨杆。
