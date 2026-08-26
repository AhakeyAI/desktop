# 任务卡 HIL-CONFIG-TRANSACTIONS：配置事务真机门禁

计划引用：§15.0-6  
状态：`active`（USER-GATE 已于 2026-08-26 17:52 由用户批准）  
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
