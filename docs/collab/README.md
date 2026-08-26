# 三方异步沟通区（Codex / Kimi / Cursor）

本目录是 Codex、Kimi、Cursor 三方的**唯一异步沟通通道**。规则如下，三方共同遵守：

## 原则

1. **不依赖用户传话**。任何需要其他方知道的信息，必须写入本目录；任何行动前先读本目录。
2. **append-only**：`board.md` 只允许在末尾追加条目，不修改、不删除历史条目。更正旧信息用新条目说明。禁止用 `>`、整文件 Write 或截断覆盖。追加请用 `python3 docs/collab/tools/append_board.py`（stdin 或参数）。
3. **先读后写**：每次开始工作前，先通读 `board.md` 末尾自上次读后的新条目，以及与自己相关的任务卡。
4. **写完即答**：读到需要自己回应的条目（标了 `@你的名字` 或 `需要回复`），在同次工作中追加回复，不拖延。
5. **完成事件**：Kimi/Cursor 完成、阻塞或请求验收时，必须在条目末尾写 `需要回复：是（@Codex）`（Kimi 主叫）。Codex 通过 `watch_board_events.py` 获知；独立验收口径见下文「等待、唤醒与独立验收」。不依赖 Goal 自动续跑，也不把周期性心跳当完成信号。
6. **Kimi 单会话施工**：任一 `ready/active` 任务卡在同一时刻只允许 **一个** Kimi 会话改产品代码。5 分钟心跳/巡检会话只读 `board.md` 与任务卡，禁止 Write/覆盖白名单源码。防撞车发现并发写入时停手，不 `checkout` 对方未提交稿以外的「整文件重写」。谁接单 ACK，谁施工到提审。

## 文件结构

```text
docs/collab/
  README.md        本文件，沟通规则（修改需三方协商）
  board.md         主沟通板：进展、问题、决定、交接，按时间追加
  backups/         board.md 快照（gitignore；不是沟通通道）
  queue.md         Codex 维护的顺序执行索引与 USER-GATE
  taskcards/       Codex 下发的任务卡，一个工作包一个文件
  tools/           协作基础设施；事件唤醒、board 备份与追加写入
```

## board.md 条目格式

```text
### [2026-08-23 12:00] Kimi → 全体
类型：进展 | 问题 | 决定请求 | 交接 | 回复
任务卡：（相关任务卡 ID，无则写 -）
正文……
需要回复：否 | 是（@某方，期望回复内容）
```

- `→` 标明预期读者：全体 / Codex / Kimi / Cursor。
- 「决定请求」只有 Codex 能拍板（涉及范围、优先级、门禁）；三方分歧升级给用户时在条目里显式写「升级用户裁决」。

## 任务卡规则

- 只有 Codex 创建和修改 `taskcards/` 下的任务卡状态字段。
- 只有 Codex 修改 `queue.md` 的顺序、依赖和晋级口径；默认任一时刻只有一张卡处于 `ready/active/review`。
- 执行方（Kimi/Cursor）在任务卡文件末尾的「执行记录」区追加自己的进展与交接条目。
- 任务卡字段以最终方案 [`docs/codex-kimi-cursor-collaboration.md`](../codex-kimi-cursor-collaboration.md) 第 5 节为准；根目录两份提案只保留为历史输入。

## 等待、唤醒与独立验收

用户 2026-08-25 冻结（Goal 暂停无效时以本目录 + watcher 为准，不靠 thread Goal 续跑）：

1. **墙钟等待**（采集、ACK、USER-GATE）：不打开 Goal 自动续跑。进度以 `queue.md`、任务卡和 `board.md` 为事实源。
2. **Watcher**：`tools/watch_board_events.py` **只**在最新条目为 `Kimi →` 且含 `需要回复：是` 且 `@Codex` 或 `@Cursor` 时唤醒。不扫 `否`，不改该脚本。
3. **Kimi 主叫**：采集或工作包完成时必须写 `需要回复：是（@Codex）`。这是唤醒主路径。
4. **独立验收不被「否」卡住**：报告与原始证据已齐时，Codex 可验收，即使最新心跳是 `需要回复：否`。否则又变回等人传话。
5. **到点证据不足**：board **一次** `@Kimi` 催补采，卡保持 `active`。把已否决窗口再交一次或明显造假则当场拒绝。不因此打开 Goal 续跑，也不把又一条「否」当成还在采。
6. **重复唤醒算一次**：Kimi 的「是」与 ETA sleeper 落到同一完成事件时，只做一轮验收。
7. **Sleeper**：仅当执行方公布了明确采集 ETA 时，允许 **一个** 睡到 ETA 的 sleeper。ACK 与 USER-GATE 只靠 watcher，不另开 sleeper。无 ETA 时禁止轮询 `ps` / 10 分钟心跳。
8. **独立验收材料**：任务卡规定的报告路径、原始样本、`git diff --check` 与独立探测；不把 board 旗标当作证据。
9. **board 备份**：`tools/backup_board.py` 在每次变更时快照到 `docs/collab/backups/`。若 live 文件相对上一份完好快照缩小超过一半（且快照 ≥4KiB），自动把截断副本另存为 `board-TRUNCATED-*` 并恢复上一份完好快照。沟通仍以恢复后的 `board.md` 为准。`wait_board_change.py` 在截断时也会退出并报警，不只检测变大。

## 与其他文档的关系

- 范围、批次、验收门禁的权威仍是 `docs/unified-firmware-runtime-implementation-plan.md`；本目录只承载过程沟通，不改变计划内容。沟通中达成的结论若影响计划，由 Codex 更新总计划并在 board 上通告。
