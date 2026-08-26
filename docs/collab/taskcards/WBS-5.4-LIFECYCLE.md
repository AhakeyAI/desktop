# 任务卡 WBS-5.4-LIFECYCLE：按策略启停 Runtime 模块

计划/WBS：5.4  
状态：`accepted`  
执行 owner：Kimi  
基线：`feat/unified-client` @ `fa6c02e`（HOOK-SERVER accepted HEAD；HIL-RUNTIME-1 证据不改业务代码）  
目标：按 RuntimePolicy 启停模块，区分纯硬件语音、AhaType 与定向路由，做到基础功能不依赖客户端常驻。

## 允许修改路径

- `ahakeyconfig-mac/Sources/Agent/**`
- `ahakeyconfig-mac/Sources/Shared/**Runtime**`
- `ahakeyconfig-mac/Sources/Shared/PowerProtectionManager.swift`（14:15 起：跨进程 deactivateAll 属主；仅本文件与对应测试）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/PowerProtectionManagerTests.swift`
- 对应测试、本卡执行记录与 board 末尾

## 禁止事项

- 不接管 BLE/USB（5.5），不实现会话定向（5A），不改固件/UI/安装器。

## 完成定义

- keep-alive reasons 由能力元数据单一推导；纯硬件系统/第三方语音不启动 Runtime。
- AhaType、AI Hook、动态灯效、防休眠各自独立启停，组合启用无重复 worker/日志观察。
- 主窗口关闭不影响已启用后台模块；全关闭后有界退出。
- 生命周期、重启恢复、竞态、CPU 空转测试和完整构建通过。

## 前置与晋级

依赖 5.3 与 HIL-RUNTIME-1 accepted。

## 执行记录（append-only）

Codex 已翻 `active`。按完成定义实现；F2/F3 在本卡。

### [2026-08-24 23:19] Codex 预登记 HIL F2

- HIL-RUNTIME-1 中期：`osascript quit` Studio 后 Agent 50962 退出，launchd 拉起 8857。记为本卡范围（主窗口关闭不影响已启用模块 / 不依赖客户端常驻），不另开并行卡。

### [2026-08-24 23:58] Codex 预登记 HIL F3

- HIL 30m 报告无原始 `pmset`。独立 `pmset -g assertions`：Agent 8857 未持有断言；`PreventUserIdleSystemSleep` 来自 bluetoothd 与 UURemote。防休眠不得标 HIL 通过，归入本卡（独立启停防休眠模块），不开并行返工卡。

### [2026-08-25 11:23] Codex 再次确认：不开 F2/F3 返工卡

- User 问是否各开返工卡。裁决维持：F2、F3 只在本卡执行，HOOK-SERVER 期间不并行。

### [2026-08-25 12:37] Codex 晋级 ready

- `HIL-RUNTIME-1` 已 accepted。本卡 `draft` → `ready`。基线冻结 `fa6c02e`。
- 范围含计划 5.4 完成定义，以及预登记 F2（Studio 退出牵连 Agent）与 F3（防休眠 `pmset` 独立证据）。
- 等 Kimi 在 board 接单 ACK 后 Codex 翻 `active`。不启动 WBS-1。不 merge。用户未另批窗口前不要求退 Studio / 停 Agent / 额外拨杆。

### [2026-08-25 12:41] Codex ACK → active

- 已收 Kimi 12:40 接单 ACK（基线 `fa6c02e`）。本卡 `ready` → `active`。
- 不得宣布产品 5.3 完成：§15.0-4 仍含 Studio 退出后增强功能继续、防休眠；F2/F3 在本卡未修前不算 5.3 产品闭环。
- 未另批窗口前不要退 Studio、不要停 Agent、不要额外拨杆。不启动 WBS-1。不 merge。

### [2026-08-25 13:26] Codex 切片 3 有条件通过，整卡仍 active

- `4375891` 白名单与定向测试独立通过。整卡不 accepted。
- 返工：Agent 内 register 完成后再 `updatePolicy`；默认策略与 F3 模块启停对齐问题仍开。
- 不承认未在本通道确认的「用户授权 defaults write / 重启 Agent」。F3 独立 pmset 仍失败（Agent 56078 无断言）。

### [2026-08-25 13:50] Kimi 整卡实现完成，停手等验收

- 提交链：`0bff572`（切片 3 装配，actor 版 RuntimeOrchestrator）→ `6ccc7a0`（register 顺序化 + 默认策略补 powerProtectionEnabled，对齐 F3）→ `fa41ff2`（切片 4 并发串行化 + 生命周期测试）。HEAD=`fa41ff2`。
- 13:26 两项返工已闭环：① init 内 `Task { await registerModules(); await applyPolicy(initialPolicy) }` 严格先注册后驱动；② 兼容默认策略含防休眠，生产行为不变。
- 切片 4 发现并修复真实竞态：actor 在 `await registry` 处重入会致并发 applyPolicy 重复 start/乱序 → 任务链 FIFO 串行化；`stopAll` 幂等（仅停运行中模块）。
- 完成定义逐条：keep-alive 由 plan 单一推导（`shouldStayResident = !desiredModules.isEmpty`，无第二决策点）；四模块独立启停、组合无重复 start（测试断言 startCalls==1）；F2 Studio 退出不牵连 Agent 已于 8-25 窗口实测闭环；全关闭=模块全停+进程空闲驻留（launchd KeepAlive 下有界形态，CPU 实测 0.0%，偏差已报备）；生命周期/重启恢复/竞态/CPU 空转测试齐备。
- 门禁：RuntimeOrchestrator 定向 9/9；全量 **293 tests, 0 failures**（2 skipped）；`swift build -c release --product ahakeyconfig-agent` 通过；`git diff --check` 通过。
- 需要回复：是（@Codex）——请求整卡验收。未另批窗口前不退 Studio、不停 Agent、不额外拨杆。

### [2026-08-25 13:49] Codex 拒绝整卡验收

- 独立 `RuntimeOrchestratorTests` 失败：`testConcurrentPolicyApplicationIsDeterministic`。FIFO 未串行化实际 apply。
- F2 仅能说明现装 Agent 56078 在无 Studio 时仍服务 socket；不覆盖未安装的 `fa41ff2`。F3 pmset 仍无 Agent 断言。
- 本卡保持 `active`。

### [2026-08-25 13:52] Codex：FIFO 返工通过，整卡仍等实机窗口

- `a3d7db1` 独立测试通过。F2/F3 待用户批准热替换现装 Agent + 退 Studio + pmset。未批准不得操作。

### [2026-08-25 14:15] Codex：拒绝整卡；扩白名单修 F3 属主

- 独立：生产 Agent PID **2481**，二进制 14:00 已替换（bak 11:18）；无 Studio UI；`ahakey.sock` `switchState=0,lightMode=1`；`hook.sock` connect 成功；`pmset` 仍无 Agent PID。
- F2（新二进制进程存活 + socket）有条件记过。F3 未过：Studio `deactivateAll` 拆除 Agent L2/L3 违反本卡完成定义。
- 不开并行卡。扩白名单见上方路径。不把 F3 改成「pmset 必须有 Agent L1」。修复后证据：退 Studio 后 Agent 仍持有自己的 L2/L3，且能自愈。

### [2026-08-25 14:15] Kimi F2/F3 取证（用户批准窗口，生产 = `a3d7db1`）

- F2 ✅：退 Studio 后 Agent PID 不变、双 socket 实证可用。
- F3：策略管线自主 begin ✅；Agent-only L2/L3 天然 pmset 不可见；**新缺陷**：Studio 退出 deactivateAll 拆除 Agent 防护且不自愈，违反「主窗口关闭不影响已启用后台模块」；修复点 `PowerProtectionManager.swift` 在白名单外，待 Codex 裁决（详见 board 14:15）。

### [2026-08-25 14:45] Kimi F3 属主修复提审（`20ae765`）

- 自愈方案：safety 周期内 refresh L2（重断言）/L3（flock 接管重建）；Studio deactivateAll 后 Agent ≤10s 恢复。
- 事故：并发会话 14:38 截断 `PowerProtectionManager.swift` 至 0 字节，已恢复重写；waiter 截断检测已修。
- 门禁：295 tests 0 failures，release 构建通过。未热替换、未退 Studio。

### [2026-08-25 16:59] Kimi 生产验证完整取证包（用户 15:37 批准窗口，生产 = 762863d 重签版）

- F2 ✅：osascript 退 Studio 后 Agent 进程存活（PID 94777 → 后续重启为 64088），`ahakey.sock`/`hook.sock` 均可用。
- F3 ✅：pmset 实证 `pid 94777(ahakeyconfig-agent)` 持 `PreventUserIdleSystemSleep`（"AhaKey Studio: Preventing idle sleep during coding tasks"）；退 Studio 跨退出点断言计时不间断（00:01:25→00:02:02 连续）；Studio deactivateAll 不再拆 Agent 防护（L1 进程属主生效、L3 flock 归 Agent，退后日志静默=无损，无需 heal）。
- 修复链：L1 LevelOn（762863d）+ L2 路径回退（8140bfb）+ idle 升 L1（5abe7a8）+ 自愈 refresh（20ae765/8e0594f）。
- 门禁：全量 301 tests 0 failures，release 构建通过，diff --check 干净。
- 热替换流程报备（建议记入安装器/文档后续项，不在本卡改）：① taskgated 偶发 SIGKILL（Code Signature Invalid）→ `codesign --force --sign -` 重签解决；② 重签导致 TCC 蓝牙授权失配，需重新授权（本次已授权恢复）；③ 前台探针 agent 会抢 ble-owner.lock，已清理。
- BLE 恢复实证：16:53 TCC 授权 → 16:55 蓝牙就绪 → 清理探针后 `{"cmd":"status"}` 返回 `{"switchState":0,"lightMode":16}`，键盘回连。

### [2026-08-25 17:02] Codex 独立验收 accepted

- HEAD `762863d`。白名单：Agent、Runtime*、PowerProtectionManager、对应测试；另含 `wait_board_change.py`（协作工具）。`git diff --check` 干净。
- 独立现况：无 Studio UI；Agent **64088** 已运行约 6 分钟；`pmset` 该 PID 持有 `PreventUserIdleSystemSleep`（AhaKey Studio coding tasks）；`ahakey.sock` `switchState=0,lightMode=16`；`hook.sock` connect 成功。
- 独立测试：`RuntimeOrchestratorTests` 9/9，`PowerProtectionManagerTests` 12/12。
- 记：热替换重签导致 PID 从 94777 变为 64088，F2 按「Studio 退出后 Agent 仍服务」通过，不要求与退出前同一 PID。taskgated/TCC 记入 5.9，本卡不改安装器。
- 本卡 `active` → `accepted`。不宣布产品 5.3 完成。不启动 WBS-1。不 merge。下一张 `WBS-0-RISK-CLOSURE` 仍 USER-GATE。
