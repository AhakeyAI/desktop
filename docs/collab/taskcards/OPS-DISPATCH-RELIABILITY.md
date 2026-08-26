# 任务卡 OPS-DISPATCH-RELIABILITY：三方自动调度闭环

计划引用：协作规范 §8.1-8.2  
状态：`accepted`  
执行 owner：Kimi  
验证方：Codex  
基线：WBS 5.2 accepted 时的协作文档提交/工作区  
目标：证明 Codex 发卡后 Kimi 不依赖用户传话即可被自动唤起和回板。当前 Kimi Desktop 版本不轮询 condition，临时采用 30 分钟 interval 降级模式；空闲零模型消耗保留为平台限制，不再阻塞业务关键路径。Cursor 的持久 re-arm 验证已拆分为 `OPS-CURSOR-REARM`，安排在 WBS 5.2 后、5.3-C 前。

## 允许修改路径

- Kimi AhaKey 自动化的 `automation.json` 与 `should_fire.py`（保留备份，仅结构化更新）
- `docs/collab/**` 的本卡记录、测试 fixture 与 board 末尾

## 禁止事项

- 不修改任何业务代码、Hook 决策、全局工具权限或其他项目自动化。
- 不用 manual run 冒充 condition/interval run；不保持高频模型空轮询。
- 未经用户确认不重启 Kimi/Cursor，不强制结束有未保存内容的客户端。

## 完成定义

- Kimi：`workspacePath` 有值/空/缺失均命中正确仓库；至少一条 run 日志明确显示由 interval 自动触发，而非 manual。临时 cadence 为 30 分钟，空闲 run 必须快速退出且不写“无变化”消息。
- Codex：30 分钟心跳只做调度/验收；最后一张活跃卡结束后自动暂停，下一张 ready 时恢复。
- 本卡从 `ready` 触发真实 interval run；Kimi 回传 runId、trigger 类型和 startedAt 后，Codex 验收。condition 空闲零调用待平台支持后复验，不伪称已满足。

## 用户门禁

用户已于 2026-08-23 15:01 后正常重启 Kimi Desktop，重启门禁已满足。不得再次要求用户为同一门禁重启。

## 执行记录（append-only）

等待 WBS 5.2 accepted 或真实自动 tick 证据。

### [2026-08-23 14:50] Codex 阻塞记录

- Kimi condition 对三种 context 均为 `true`，但 14:03 manual 之后超过四个 10 分钟窗口仍没有自动 run。
- 需要用户先正常重启 Kimi Desktop，使 runtime 从磁盘重新加载 automations；不得由 Codex 强制结束应用。
- 重启后先观察一条明确的 condition/interval run，再恢复 WBS 5.2；Cursor re-arm 在 WBS 5.2 accepted 后继续验证。

### [2026-08-23 15:09] Cursor GPT-5.6（Codex 统筹态）恢复记录

- 用户重启已完成；Kimi 15:07 确认重启后条件在无活跃卡时返回 false，符合设计。
- 本卡从 `blocked / USER-GATE` 恢复为 `ready`，以本卡本身触发真实 condition/interval run；不提前开放 WBS 5.2。
- 原完成定义同时要求“OPS accepted 后才能做 5.2”与“5.2 accepted 后验证 Cursor re-arm”，形成循环依赖。Cursor re-arm 已拆为独立 `OPS-CURSOR-REARM`，安排在 5.2 后、5.3-C 前。

### [2026-08-23 15:41] Cursor GPT-5.6（Codex 统筹态）最终验收

- 自动 run：`run_50c19069-26c4-42f4-82c3-f8e46d68f036`
- `startedAt`: `2026-08-23T07:31:56Z`；`scheduledAt`: `2026-08-23T07:31:14Z`
- 运行日志明确为 `Automation.run triggered by interval`，状态 succeeded；不是 manual。
- A/B 证据确认当前 Kimi Desktop runtime 能加载 interval，但不轮询 condition。condition 空闲零模型调用不可达是平台限制，不是仓库脚本 false-negative。
- 裁决：临时降为 30 分钟 interval（10 分钟的三分之一调用频率），空闲 run 快速退出且不写 board；平台恢复 condition 后再切回“10 分钟文件判定、命中才唤醒”。
- 本卡 `accepted`。该验收只证明 Kimi/Codex 自动流转；Cursor 持久 re-arm 仍由 `OPS-CURSOR-REARM` 验证。
