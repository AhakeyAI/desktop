# 任务卡 HIL-CONFIG-TRANSACTIONS：配置事务真机门禁

计划引用：§15.0-6  
状态：`ready`（用户 20:18 在场批准断电/断连窗口；等 Kimi ACK）
执行 owner：Kimi  
验证协作者：Cursor  
基线：WBS 5.6 accepted @ `19eb4dc`  
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
