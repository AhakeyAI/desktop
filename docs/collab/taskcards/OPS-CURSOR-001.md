# 任务卡 OPS-CURSOR-001：临时解除 Cursor 的 AhaKey Hook 硬拦截

状态：`accepted`  
日期：2026-08-23  
执行 owner：Kimi  
验证协作者：Cursor（仅做修复后 smoke，不拥有本卡写入范围）  
基线：`feat/unified-client` @ `52177c2`

## 目标

在不修改客户端业务代码、不扩大任何永久权限的前提下，安全移除当前用户 Cursor 配置里的 AhaKey Hook 条目，使 Cursor 立即恢复原生权限流，可以继续 Read/Write/Shell 协作。永久产品修复仍由新版客户端 WBS 5.3-C 交付。

## 现场事实

- `~/.cursor/hooks.json` 当前有 9 个 AhaKey 条目。
- 真实 Cursor 3.17.8 日志已证明 AhaKey `preToolUse` 在 `agentReply=false`、`switchState=null` 时返回 `permission: deny`，直接拦截 Write。
- Cursor 会热加载 Hook 配置；优先等待热加载生效，只有未生效时才提示用户正常重启 Cursor，不得强制退出应用。

## 允许修改的路径

- `~/.cursor/hooks.json`
- 同目录一份带时间戳的原始字节备份，例如 `hooks.json.ahakey-unblock-20260823T1223.bak`
- 本任务卡末尾“执行记录”（只允许追加）
- `docs/collab/board.md`（只允许在文件末尾追加）

## 禁止事项

- 不修改 `ahakeyconfig-mac/Sources/**`、测试、总计划或 Runtime seam。
- 不修改 `~/.claude/settings.json`、`~/.kimi/**`、`~/.codex/**`。
- 不修改 `~/.cursor/cli-config.json` 或创建 `~/.cursor/permissions.json`。
- 不增加 `Write(*)`、`Shell(*)`、MCP 或其他永久放行规则。
- 不删除或改写任何非 AhaKey Hook，不关闭 Cursor 的第三方配置兼容功能。
- 不强制结束 Cursor 进程，不替用户操作未保存内容。
- 不提交仓库业务代码；本卡不是 WBS 5.3-C 的实现许可。

## 执行步骤

1. 重新读取最终协作规范、board、本任务卡和实时 `git status`；在 board 末尾追加接单 ACK。
2. 解析并验证 `~/.cursor/hooks.json` 是合法 JSON；记录文件权限和 SHA-256。
3. 在同目录创建原始字节备份，备份成功后再继续。
4. 结构化遍历 `hooks` 下所有数组，只移除 `command` 同时包含已安装 AhaKey agent 路径和 ` hook ` 调用的条目。保留其他字段、其他来源和其他 Hook；空事件数组可以删除。
5. 先写同目录临时文件，重新解析验证后原子替换，并保持原文件权限。任一步失败则不替换原文件并在 board 上报阻塞。
6. 验证 Cursor Hook 配置已热加载；若没有热加载，只在 board 说明需要用户正常重启 Cursor，不强制退出。
7. 请 Cursor 作为验证协作者完成最小 smoke，并把结果追加到 board：Read 一个仓库文件、创建并删除一个明确的临时测试文件、执行一个只读 Shell。不得触碰业务文件。

## 完成定义

- `~/.cursor/hooks.json` 仍是合法 JSON，文件权限不放宽。
- AhaKey Cursor Hook 条目从 9 个变为 0；非 AhaKey Hook 的规范化 JSON 前后完全一致。
- 原始配置备份存在，SHA-256 已记录，能够人工回滚。
- `~/.claude/settings.json`、`~/.cursor/cli-config.json` 和 `~/.cursor/permissions.json` 未改变。
- Cursor 最新 Hook 日志不再出现来自原生 Cursor AhaKey `preToolUse` 的 `permission: deny`。
- Cursor smoke 的 Read、临时 Write/Delete、只读 Shell 均能进入 Cursor 原生执行/批准流程并完成。
- Kimi 在本卡和 board 追加回传包；然后停止，不开始 WBS 5.2 或 5.3-C。

若配置修复已完成但尚未取得 Cursor smoke，结果只能写“部分完成：等待 Cursor 验证”，不能宣称完整完成。

## 回滚

仅当结构化校验或 Cursor 加载失败时，使用本卡创建的备份原子恢复 `~/.cursor/hooks.json`，恢复后再次验证 JSON 和权限。不得恢复为永久全放行配置。

## 执行记录（append-only）

等待 Kimi 接单。

### [2026-08-23 12:52] Codex 中间验收

- `lastReviewedCommit`: `52177c2`
- 配置阶段：通过。当前 `hooks.json` 合法、权限仍为 `0644`，AhaKey 条目 `9 -> 0`；备份 SHA-256 与原文件一致，非 AhaKey 条目前后均为空。
- Cursor 已热加载配置并报告原生 user hooks 从 9 个降为 0；无需强制重启。
- 受保护配置保持：Claude settings 与 Cursor CLI config 的既有 SHA-256 未变化，`permissions.json` 仍不存在。
- 任务仍为 `active`：等待 Cursor Read、临时 Write/Delete、只读 Shell smoke，以及新日志无 AhaKey deny 的最终确认。

### [2026-08-23 12:29] Kimi 执行记录

- git 基线核对：`feat/unified-client`，工作区无本卡相关未提交改动。
- 修复前：`~/.cursor/hooks.json` 合法 JSON，perms 644，SHA-256 `977b6e6e186740d93c836374b8b7cb167b7748f0a83b683466c161a759934849`，9 个事件各 1 条、共 9 条，全部为 AhaKey（command 含 `ahakeyconfig-agent` + ` hook `）。
- 备份：`~/.cursor/hooks.json.ahakey-unblock-20260823T1228.bak`，SHA-256 与原文件一致，可人工回滚。
- 移除：AhaKey 条目 9 → 0；无非 AhaKey 条目受影响（kept=0，无第三方 Hook 存在）。空事件数组已删除，`hooks` 现为 `{}`。
- 写入方式：同目录临时文件 + 重新解析验证 + `os.replace` 原子替换，权限保持 644。
- 修复后：合法 JSON，SHA-256 `d8ced3d6d8663b11ef8f3f6c27cf7ee2c25dec21be12c94bf498bccc209a90cc`。
- 旁证未触碰：`~/.claude/settings.json`（mtime 7-29）、`~/.cursor/cli-config.json`（mtime 5-5）未变；`~/.cursor/permissions.json` 不存在（未创建）。
- 热加载：Cursor 会热加载 hooks.json，无需重启；若 smoke 仍被拦，需用户正常重启 Cursor（未强制退出任何进程）。
- 结果：**部分完成：等待 Cursor 验证**（Read / 临时 Write+Delete / 只读 Shell smoke）。

### [2026-08-23 12:52] Cursor 验证记录

- Read：`docs/collab/README.md`、`board.md`、本任务卡、`docs/codex-kimi-cursor-collaboration.md` §8.1。
- 临时 Write + Delete：`docs/collab/_cursor_smoke_OPS-CURSOR-001.tmp` 已创建并删除。
- 只读 Shell：`feat/unified-client` @ `52177c2`；`~/.cursor/hooks.json` 合法，`hooks` 为 `{}`，AhaKey 条目 0。
- 本回合 Write / Shell / Delete 均成功进入执行，未再被 `preToolUse` deny。
- 结果：**部分完成：Cursor smoke 已通过，等待 Codex 验收**。未改业务代码，未开始 WBS 5.2 / 5.3-C。

### [2026-08-23 12:54] Cursor 验证记录（复跑）

- 用户口径已读：临时修复 = 只摘 hooks.json；永久修复 = WBS 5.3-C 新安装包；期间 Studio 可能写回 Hook。
- 三条 smoke 再跑一遍均成功：Read board/任务卡；Write+Delete `docs/collab/_cursor_smoke_OPS-CURSOR-001.tmp`；只读 `git rev-parse` = `52177c227fed3c08558e3ec92f346b009e0c5d89`。
- 无 deny，未装包，未改 `hooks.json`。
- 结果：**Cursor 验证门禁已齐，等待 Codex 验收。**

### [2026-08-23 13:01] Codex 最终验收

- `lastReviewedCommit`: `52177c2`
- 结论：`accepted`。配置备份、结构化移除、权限与受保护文件校验全部通过。
- Cursor 两轮 smoke 均通过：Read、临时 Write/Delete、只读 Shell 可执行，未再出现 `permission: deny`。
- 最新 Cursor Hook 日志显示原生 user hooks 为 0；仍加载的 Claude 兼容 Hook只产生中性/无输出结果，没有阻塞工具。
- 本卡只恢复当前环境；旧版 Studio 再次执行“安装 Cursor Hooks”可能复发。永久关闭仍由 WBS 5.3-C 交付。
