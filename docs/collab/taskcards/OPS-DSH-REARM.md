# 任务卡 OPS-DSH-REARM：DSH 执行侧持久重唤闭环

计划引用：协作规范 §2.3、§8.1  
状态：`blocked / manual board handoff`  
执行 owner：DSH  
验收：Codex  
基线：DSH 接替 Cursor 的未完成及未来客户端执行卡；`OPS-CURSOR-REARM` 仅作为历史证据保留

## 目标

证明 DSH 从无活跃卡的静默状态，能够在新 `ready` 卡或未回复 `@DSH` board 事件到达时被自动唤醒、读取权威任务卡、追加一次 ACK，并在停手后由第二个独立事件再次唤起。通过前只允许人工打开 DSH 会话并按 board 交接，不得宣称自动续工。

## 边界

- `watch_board_events.py` 识别 `DSH →` / `@DSH` 只证明事件可被分类，不证明 DSH Desktop 能接收或恢复会话。
- 不复用 Cursor IDE Hook、`OPS-CURSOR-REARM` 结果或 Agent Relay 中的 `client-worker=cursor` binding 冒充 DSH 证据。
- 不改产品代码、用户 IDE 权限、Runtime/Hook、固件仓或 USER-GATE。
- 若 DSH 平台没有可验证的 resume 接口，本卡保持 blocked，使用 board 手工交接。

## 完成定义

1. 固定 DSH 会话身份与项目目录，记录可审计的唤醒入口。
2. 两轮彼此独立的外部事件均能在 DSH 静默后触发；每轮只追加一次 ACK，不重复施工。
3. 无关 board append、`需要回复：否`、面向其他 owner 的事件均不唤醒 DSH。
4. 重启 DSH 或 watcher 后从 durable cursor 恢复，不重复消费旧事件。
5. USER-GATE、`blocked`、`draft` 卡只提示，不自动开工。
6. 给出停用/回滚办法；重复 watcher 不得并存。

## 执行记录

等待 DSH 平台唤醒接口可验证后另行开放。本卡不阻塞 DSH 在用户手工打开会话后的任务卡执行。

