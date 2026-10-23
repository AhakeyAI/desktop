# WD-004 Owner scope confirmation - Hook manager and task slot grill

Owner completed a detailed grill for WD-004 Hook management and Codex/Cursor task-slot behavior on 2026-10-09.

Hook management decisions:

- Top-right "更多 -> Hook 管理" opens "AhaKey Hook 管理" and automatically scans all four tools: Claude, Cursor, Codex, Kimi.
- Four tools use unified user-facing states: 检测中 / 未检测到应用 / 未安装 / 待更新 / 最新 / 异常.
- The app may keep internal version markers, but UI must not expose concrete internal version names such as `ws3-cp1-v1` or `v1.0`.
- "待更新" means an AhaKey Hook is installed but not current, or an AhaKey Hook can be located but its version is unknown. Anything completely unidentifiable is "异常".
- If any of the four tools are "待更新", Hook 管理 automatically shows one summary prompt per app run only. The prompt lists concrete tool names, says update will back up original Hook files and only replace AhaKey hooks, and has one primary button: "一键更新".
- One-click update updates all "待更新" tools only. It does not install missing tools and does not rewrite tools already "最新".
- During one-click update, the prompt remains open, buttons are blocked, and current tool name is shown.
- If all updates succeed, close the prompt, rescan all four tools, and return to the list.
- If any update fails, keep the prompt open, list failed tool names and simple reason, and after user clicks "知道了" return to the list.
- Hook 管理 list keeps per-tool actions:
  - 未检测到应用: disabled "不可安装", description "未检测到对应应用，暂不可安装 Hook".
  - 未安装: "安装 Hook", description "未安装 Hook，安装后可支持 AhaKey 功能".
  - 待更新: "更新 Hook", description "当前 Hook 需要更新，更新后可支持多任务灯光状态，并优化 Cursor 权限流程".
  - 最新: disabled "已是最新", description "已是最新版，支持多任务灯光状态".
  - 异常: disabled "异常", description "检测异常，请联系管理员".
- Hook 管理 list has "重新检测"; scans are read-only and respect the one-prompt-per-app-run rule.
- Single install/update directly executes without a second confirmation, but must backup first, preserve non-AhaKey hooks, block concurrent actions during the write, and rescan all four tools after success.
- Backup failure means do not write the new hook and report the tool update as failed.
- Single install/update failure shows a prompt with simple reason: 备份失败 / 文件不可写 / 配置无法读取 / Hook 格式无法识别 / 未知错误, plus "请联系管理员".
- Hook 管理 does not show an uninstall entry in WD-004. Service-level uninstall code may remain, but the UI must not expose it.
- Hook 管理 bottom note: "安装或更新时，AhaKey 只会添加/替换自己的 Hook，不会删除你原本配置的其他 Hook。"
- Hook 管理 bottom note also says: "当前多任务灯光支持 Codex / Cursor。"
- Hook 管理 does not show local file paths, update source, network status, or last scan time.

Light page and task source decisions:

- Light page "应用到键盘" does not directly install/update Hooks. If needed, it prompts and provides "去 Hook 管理".
- WD-004 related task sources are Codex and Cursor. Task-slot sources include both Codex and Cursor.
- The task selector may open even if no usable source exists. It shows an empty state and "去 Hook 管理".
- Empty state when no usable source exists: "暂无可用任务来源，请先在 Hook 管理中安装或更新 Codex / Cursor Hook。"
- A source is usable for task selection only when its Hook state is "最新".
- If a source Hook is not "最新", the source group remains visible but shows "需安装/更新 Hook" and no sessions, with "去 Hook 管理".
- Cursor data directory is configurable in the task slot manager, defaulting to `%APPDATA%\Cursor\User`. Codex data directory remains configurable there too.
- Invalid Cursor directory does not affect Codex; invalid Codex directory does not affect Cursor.
- Source Hook latest but invalid data directory: "数据目录无效，请重新选择目录".
- Source Hook latest and valid data directory but no records: "暂无可绑定任务".

Cursor discovery and matching decisions:

- Cursor task list uses the same model as Codex: tool -> project -> session.
- Cursor first version reads metadata only, not full chat content.
- Cursor title source: prefer `conversation-search.db.conversations.title`; fall back to `composerHeaders` metadata.
- Cursor project mapping: prefer `workspaceStorage/<hash>/workspace.json` folder mapping and match against `composerHeaders.workspaceId`.
- Cursor archived sessions are not shown. Cursor subagent sessions are not shown.
- Cursor sessions sort by most recent `lastUpdatedAt / updated_at` descending. Cursor projects sort by newest session under the project.
- Cursor slot stable ID is `composerHeaders.composerId`; `conversation-search.db.conversations.id` is only used to supplement title/time and aligns to the same ID.
- Cursor hook runtime must forward full stdin JSON.
- Cursor runtime matching priority: `conversation_id`, then `session_id`, then `composerId / composer_id`, then `conversationId / conversation_id`.
- Cursor runtime updates must match concrete session ID to a bound slot. It is forbidden to use project, workspace, workspaceId, cwd, or workspace roots as slot-update fallback.
- Cursor runtime events without a concrete session ID are ignored in MULTI and logged only.

Codex matching decisions:

- Codex also uses session-level matching only.
- Codex runtime updates must match concrete `session_id` or `transcript_path`.
- Codex must not use `cwd` or project as slot-update fallback.

Task-slot UI and runtime decisions:

- Task selector hierarchy is fixed: tool -> project -> session. Project is display grouping only; session is the binding object.
- Slot cards display tool name, project name, session title/summary, and recent time. Internal IDs are not shown.
- Empty title displays "未命名会话".
- The same session cannot be bound to more than one slot. Already-bound sessions show "已绑定 槽位 X" and cannot be selected again.
- No "move to current slot" in the first version; user must unbind first.
- Slot editing is saved locally but does not send to keyboard until "应用到键盘".
- If a bound session disappears from local index, keep the binding, show "会话记录已不可用", allow unbind, do not refresh that slot.
- If a bound session is unavailable or its source Hook is unavailable, applying sends that slot empty/off.
- If all slots would be empty/off because none are usable, block apply with: "当前没有可应用到键盘的任务槽。请检查 Hook 状态或重新选择会话。"
- If at least one slot is usable, allow apply. If some slots are unavailable, show a prompt every time before applying:
  - "以下任务槽当前不可用，将不会显示到键盘："
  - list "槽位 N：<reason>"
  - button "知道了"; after user acknowledges, continue applying.
- UI uses "槽位 1/2/3/4", not "Slot".
- Four slots are fixed; no add/remove slots.

Primary slot / foreground decisions:

- User manually chooses a "主槽位" using a radio control on each slot card.
- Explanation at top of slot manager: "主槽位代表屏幕上展示 GIF 的具体会话。"
- 主槽位 can only be a bound and usable slot.
- If current 主槽位 becomes unusable, automatically switch to the first usable slot and save locally. Mention the adjustment in the partial-unavailable prompt when applicable.
- If user unbinds the current 主槽位, switch to the first still-usable slot; if none, clear 主槽位.
- If user binds the first usable slot while no 主槽位 exists, automatically set it as 主槽位.
- Slot state changes do not automatically change 主槽位.
- If applying while no 主槽位 exists but usable slots exist, auto-select the first usable slot and save locally.
- In 0x99 snapshot, only 主槽位 has `foreground=1`; all other slots have `foreground=0`.
- If no usable slots exist, do not send 0x99.
- Non-primary slot state changes still send a full 0x99 snapshot; foreground remains the selected 主槽位.
- In MULTI, do not send legacy 0x90. All MULTI updates use 0x99 only.

Owner requested these decisions be added to WD-004 by DLA contract reconcile before DIB continues implementation.
