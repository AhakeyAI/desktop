# 任务卡 WBS-6-QUALIFICATION：性能与完整 HIL 资格验证

计划/WBS：6.1-6.4 / v1.0
状态：`draft`（`USER-GATE`）  
执行 owner：Zcode
验证协作者：Cursor  
基线：v1.0 功能 WBS accepted 后冻结候选版本
目标：完成 v1.0 reducer/日志/隐藏 UI 性能、跨平台 USB/BLE、量产一致性、升级/降级/断电/断连门禁。v0.3-v0.5 与 v1.1 各由独立 HIL 卡验收。

允许修改：测试工具、报告、阻断缺陷任务卡；候选业务代码冻结，不在本卡顺手修。  
禁止：不以无设备性能代替真实键盘；不省略 Windows/变体/长稳；不发布。  
完成定义：真实键盘 CPU/RSS/日志/≤2秒；Mac/Windows×USB/BLE；Standard/Rhino；升级/降级/断电/断连；8 小时重连。
用户门禁：确认设备矩阵、Windows 环境、8 小时窗口与可中断升级测试后晋级。

## 执行记录（append-only）

等待用户门禁。

### [2026-08-29] Codex：本卡收敛为 v1.0 完整资格

v0.2-v0.5 与 v1.1 分别由独立 HIL 卡承担，本卡只等待 v1.0 前置，不反向阻塞早期版本。
