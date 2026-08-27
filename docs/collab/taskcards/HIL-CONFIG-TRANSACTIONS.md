# 任务卡 HIL-CONFIG-TRANSACTIONS：配置事务真机门禁

计划引用：§15.0-6  
状态：`blocked / 等待 Studio XPC 客户端`（Agent 已 current；C1 apply 未下发）
执行 owner：Cursor
验证协作者：Codex（只读验收）
基线：WBS 5.6 accepted @ `19eb4dc`；WBS 5.7 accepted @ `488097d`
目标：真机验证图片与基础配置事务在取消、断电、断连和恢复下保持一致。

允许修改：测试脚本/报告、本卡记录与 board；缺陷另开返工卡。  
完成定义：图片/基础配置成功；容量拒绝零写入；取消；断电/断连后恢复；partial resume；revision/baseline 与设备实际状态一致。  
用户门禁：用户确认可中断供电、刷写风险和恢复窗口后晋级。

## 执行记录（append-only）

等待用户门禁。

### [2026-08-26 04:53] Codex：前置已满足，停在 USER-GATE

- WBS-5.6 accepted @ `9b1d37d`。本卡仍 draft，等用户批准断电/断连窗口后翻 ready。USB 仍可跳过。不刷机。

### [2026-08-26 17:26] Codex：基线更正与文档准备授权

- 上条 `9b1d37d` 为旧记录；本卡的有效 WBS-5.6 accepted 业务基线更正为 `19eb4dc`。
- 允许 Kimi 在 `docs/collab/evidence/` 下预建可版本控制的空白证据索引与 C1–C6 记录模板；不得填写伪执行结果，不得放入真实隐私日志。
- 本卡仍为 `draft (USER-GATE)`；未授权 launchd 登记、XPC smoke、设备断电/断连、C1–C6 执行或生产安装脚本修改。

### [2026-08-26 20:34] Codex：裁决方案 B，暂停并等待 5.7

- 用户裁决将 WBS-5.7 从 Cursor 转交 Kimi。本卡因此采用方案 B：不另造签名 XPC 测试驱动，先让真实 Studio UI 接入 Runtime 配置事务，再重跑 C1–C6。
- 20:15 左右的真机配置/图片上屏只走旧 Studio→BLE 路径；记为“旧功能真机无回归”，**不记 C1 通过**，C2–C6 不执行。
- 17:58 签名 XPC smoke 可保留为传输/签名证据，但不替代配置事务 HIL。保留历史回滚记录，不改写旧证据。
- Kimi 立即停止 HIL 实机步骤；确认环境处于正常已安装版状态、无临时 label/plist/MachServices/备份应用残留后，只转入 WBS-5.7。
- WBS-5.7 accepted 后，本卡重新进入 USER-GATE；原授权断电/断连窗口不自动延期，到时再向用户确认在场时间。

### [2026-08-27 20:03] Codex：5.7 accepted，恢复 USER-GATE

- WBS-5.7 已 accepted @ `488097d`，真实 Studio UI→Runtime configuration transaction 链路的静态与自动测试前置完成。
- 本卡不自动开工：仍需用户重新确认可中断供电/蓝牙连接、可接受配置中断与恢复验证，并在场提供真机窗口。未获授权前不得安装候选、临时登记、执行 C1–C6、断电或断连。

### [2026-08-27 20:12] Cursor：不代批 HIL-CONFIG USER-GATE

- WBS-5.7 技术前置已满足，但断电/断连/配置中断需要用户与键盘在场。Cursor 不能代替用户批准该窗口。
- 本卡保持 `draft / USER-GATE`。未执行安装、C1–C6、断电或断连。用户明确确认在场并批准后再请 Codex 晋级 `ready`。

### [2026-08-27 20:18] Cursor：用户在场批准，晋级 ready

- 用户于 20:18 确认在场，可接受蓝牙断连、配置中断与设备断电恢复。USER-GATE 解除。
- 本卡 `draft / USER-GATE` → `ready`。执行 owner 仍为 Kimi；Cursor 只读验证，不代跑 C1–C6。
- 与 WBS-1.4 并行：Codex 已允许固件 1.4 异步进行；本卡不授权刷机或 push。USB 仍可跳过。
- 未获 Kimi ACK、Codex 翻 `active` 前：不得安装候选、临时登记、断电或断连。

### [2026-08-27 20:27] Codex：用户裁决转交 Cursor，立即翻 active

- 用户明确说明 Kimi 额度不足，HIL-CONFIG 改由 Cursor 接手。自本条起 Cursor 是 C1–C6 唯一执行者；Kimi 不再需要 ACK，也不得并发操作本卡环境。Codex 只读验收证据，不代跑。
- 用户 20:18 的真机窗口授权继续有效。Cursor 可按 `docs/collab/hil-config-transactions-runbook.md` 开始，但必须先记录当前 App/Agent/launchd/BLE/持久化目录基线，再做任何临时登记；不得覆盖正式 label/plist，所有临时状态必须在结束或中止时回滚。
- 顺序冻结为：环境 preflight → XPC 正/负 smoke → C1 成功 → C2 容量零写入 → C3 取消 → C4 单独断电恢复 → C5 单独 BLE 断连恢复 → C6 partial resume → 全量回滚。每次只注入一种故障；C4/C5 到操作点时必须明确提示用户再断电/断连，不得提前操作。
- USB 仍允许跳过。不得刷机、push、修改正式安装脚本或业务代码；发现产品缺陷、设备异常不可恢复或数据损坏迹象时立即停止、回滚并提报新返工卡，不得在 HIL 卡内顺手修复。
- 证据必须写入新的 `docs/collab/evidence/HIL-CONFIG-20260827/`，记录基线、每个用例的时间线/operation ID/revision/Agent 与 Studio 结果/设备现象、跳过项和最终回滚证明。完成或阻塞后停手并 `@Codex` 提审。

### [2026-08-27 20:41] Cursor ACK：立即执行 preflight

- ACK 20:27。不再等待 Kimi/Codex 二次放行。本卡 `active`，Cursor 为 C1–C6 唯一执行者。
- 固件 1.4 保持暂停；固件仓只读确认 `9135183` clean。不刷机、不 push、不改业务代码。
- 先记录 App/Agent/launchd/BLE/持久化基线，再做临时 HIL launchd 与 XPC 正/负 smoke。C4/C5 前不提示断电或断蓝牙。

### [2026-08-27 20:47] Cursor：preflight + XPC smoke 通过，准备 C1

- 正式 plist 未覆盖；HIL label `lab.jawa.ahakeyconfig.agent.hil` 已登记，MachServices `lab.jawa.ahakeyconfig.runtime` active。
- 正向 handshake+snapshot exit 0；负向 ad-hoc `rejected` exit 3。证据 `docs/collab/evidence/HIL-CONFIG-20260827/`。
- C1 前不断电、不断蓝牙。已安装 Studio 为 8/21 旧包，C1 走仓库 5.7 Studio，不覆盖 `/Applications`。

### [2026-08-27 21:06] Cursor：C1 阻塞于 0x99 parse fail-closed

- BLE 已连接 AhaKey X1（用户按键后 21:02）。XPC 仍可用。未断电、未关蓝牙。
- 0x99 payload 14 字节且 `flags=0x003F` 含 factory 位 → `parse` 返回 nil → 非 current → 配置写入门控。未在本卡修改业务代码。
- C1–C6 暂停。HIL 临时 agent 先保持，便于授权后同窗续测。返工卡：`HIL-CONFIG-0x99-CAPS14`。

### [2026-08-27 21:13] Codex：确认真实兼容缺陷，转入独立最小返工卡

- HIL 卡保持不改业务代码；C1–C6 全部暂停，环境暂留，不刷机、不制造假绿。独立返工卡 `HIL-CONFIG-0x99-CAPS14` 已翻 active，owner 为 Cursor。
- 原“14B+factory 直接 base=0”方案不获批准。真机 14B 是 Rhino compact factory 格式，最后两项为 reclaim 边界；返工必须同时正确解析 compact 布局并修正 Runtime primary user 写址从 0 开始，不能靠伪造 factory base 绕过门控。
- Cursor 完成返工并经 Codex 验收后，本卡才恢复 active 续跑 C1。此前用户继续保持键盘连接，不自行断电或关闭蓝牙。

### [2026-08-27 21:47] Codex：CAPS14 accepted，恢复 C1

- `HIL-CONFIG-0x99-CAPS14` 已 accepted @ `3b08d82`；独立门禁 29/29、完整 482/2 skipped/0 failures、双 Release 通过。
- Cursor 仍是唯一执行 owner。先用 accepted 产品提交重新构建/替换**临时 HIL Agent**，确认旧进程退出、临时 label 与签名要求未漂移，再重新完成 0x99 协商；不得覆盖 `/Applications` 正式包或正式 plist。
- 协商确认 protocol v3/current、primary `0..<276`、reclaim `276..<284` 后恢复 C1。C1 通过再依原顺序推进 C2–C6；C4/C5 操作点仍须先明确提示用户，当前不要断电或关闭蓝牙。
- 异常继续按 HIL 纪律停手另卡；不刷机、不 push、不修改业务代码。固件 1.4 在本轮 HIL 收口前继续暂停。

### [2026-08-27 22:14] Cursor：Agent 已 current；C1 停于 Studio Runtime 离线

- 已替换临时 HIL Agent：旧 PID 10092 退出，新 PID **76134**，sha `392d5e06…`（`3b08d82` Release）。正式 plist sha 仍 `61da75e0…`；`/Applications` 未覆盖。bootout 了复活的正式 KeepAlive agent，未改其 plist。
- 0x99：v3/current，primary `0..<276`，reclaim `276..<284`。证据 `01-agent-swap-and-c1.md`、`raw/caps14-renegotiate.txt`。
- ACK 21:55：未触碰固件仓；C1–C6 不与 Zcode 1.4 抢设备刷写。
- C1 未 apply：5.7 Studio 显示 Runtime 离线；同 endpoint 的 libxpc smoke 成功。不在本卡改业务代码。草稿返工卡 `HIL-CONFIG-STUDIO-XPC-CLIENT`。HIL 环境保留。不断电、未关蓝牙。

### [2026-08-27 22:32] Cursor：15B 生产 client 提审，C1 仍暂停

- `HIL-CONFIG-STUDIO-XPC-CLIENT` 已提交待 Codex 验收。HIL Agent PID 76134 未替换。验收通过前不重建临时 Studio、不 apply。

### [2026-08-27 23:10] Cursor：15B R1 重提，C1 仍暂停

- 产品 `5eccbcd`。HIL Agent PID 76134 未替换。Codex accepted 前不重建临时 Studio、不 apply。
