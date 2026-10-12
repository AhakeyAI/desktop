# WD-004 implementation report

Date: 2026-10-08
Actor: DIB

Implemented:
- Added WS3 CP1 runtime display protocol support for 0x98 and 0x99 with new/old firmware gating by catalog key `x1-c582-hw1-p1-1.0.0-r001`.
- Added local AI runtime display state: SINGLE/MULTI preference, Codex data directory, and four local task slot bindings.
- Added Codex session discovery from `%USERPROFILE%\.codex\state_5.sqlite`, with `session_index.jsonl` fallback.
- Added Light inspector entry for AI runtime display, slot summaries, and a Codex session selector dialog grouped by project.
- Added "应用到键盘" flow with Hook version gate for MULTI; missing/old hooks trigger install/update and require a second apply click.
- Updated Hook dispatch so SINGLE remains compatible with legacy 0x90 while MULTI updates only bound Codex sessions with complete 4-slot snapshots.
- Updated generated Codex hook to forward stdin JSON identity fields and mark version `ws3-cp1-v1`.
- Updated generated Cursor hook behavior following desktop PR #78 direction: only explicit auto-approval emits `{"permission":"allow"}`; otherwise Cursor native permission handling is preserved.
- Updated Codex/Cursor hook install merge behavior to keep non-AhaKey hook entries and replace only AhaKey commands.

Not run:
- Maven compile/package and installer build were not run because the project Harness says not to auto-build without Owner action.

---

Date: 2026-10-09
Actor: DIB
Mode: IMPLEMENT
Contract revision: 3

Preflight:
- Ran `desktop.py preflight --role DIB --id WD-004`; result PASS for current IMPLEMENT / DIB / IMPLEMENT route.
- Read the effective WD-004 `change.json`, Owner scope record `20261009T_wd004_hook_task_grill_owner_scope.md`, and DLA reconcile reason `20261009T_wd004_hook_task_grill_reconcile_reason.md`.

Implemented:
- Reworked top-right `更多 -> Hook 管理` entry to open `AhaKey Hook 管理`, scan Claude / Cursor / Codex / Kimi, and use the unified user-facing states `检测中 / 未检测到应用 / 未安装 / 待更新 / 最新 / 异常`.
- Removed WD-004 UI exposure of uninstall actions in the Hook manager list. The service uninstall methods remain but are not shown by the WD-004 UI.
- Added one-per-app-run outdated Hook summary prompt with `一键更新`; it updates only `待更新` tools and keeps missing/latest tools untouched.
- Kept Hook write safety in service flow: writes go through backup first, write failures return simple reasons, and install/update merges replace AhaKey entries while preserving non-AhaKey Hook entries.
- Changed the Light page apply path so it no longer installs or updates Hooks directly. If Codex/Cursor Hook is not latest, it offers `去 Hook 管理`.
- Added generic `AiRuntimeSession` plus Cursor data directory persistence. Cursor defaults to `%APPDATA%\Cursor\User`; Cursor and Codex directories are saved independently.
- Added Cursor metadata discovery using `conversation-search.db` titles, `workspaceStorage/<hash>/workspace.json` project mapping, and `composerHeaders.composerId` as stable session ID. The selector only displays metadata/title/project/time, not full chat content.
- Rebuilt the task slot manager around the fixed hierarchy `工具 -> 项目 -> 会话`, with Codex and Cursor source groups. Non-latest sources remain visible but show `需安装/更新 Hook` and no sessions.
- Enforced four fixed local slots labeled `槽位 1/2/3/4`, duplicate-session prevention, local-only bind/unbind persistence, missing-record retention, and unavailable-slot reasons.
- Added manual `主槽位` radio selection and persistence. Apply repairs an unavailable/missing primary slot to the first usable slot, and 0x99 marks only that slot as `foreground=1`.
- Changed MULTI runtime matching so Codex accepts only `session_id/sessionId` or `transcript_path/transcriptPath`, Cursor matches `conversation_id -> session_id -> composerId/composer_id -> conversationId/conversation_id`, and neither source falls back to project/workspace/cwd.
- Ensured MULTI hook events without concrete session identity are logged and ignored, and MULTI updates send only full 0x99 snapshots. SINGLE legacy 0x90 behavior remains unchanged.
- Added all-unavailable apply blocking with `当前没有可应用到键盘的任务槽。请检查 Hook 状态或重新选择会话。` and partial-unavailable prompt listing `槽位 N：原因` before continuing.

Checks actually run:
- `git diff --check` exited 0; only existing CRLF normalization warnings were printed.
- Read-only searches confirmed no remaining `HookStatus.MISSING/OLD/ABNORMAL`, no direct `install("Codex")` / `install("Cursor")` calls from the apply path, and no `cwd` fallback / `thread_id` fallback in runtime matching.
- `git status --short` was read only. It shows substantial pre-existing dirty/untracked work in the workspace, including WD-004 new files; no Git write action was taken.
- Attempted `desktop.py submit --id WD-004 --role DIB`; helper stopped with `HARNESS STOP: Out-of-scope production changes since activation: src/main/java/com/example/ahakey/view/TopBar.java`. DIB did not alter Harness rules. Revision 3 DLA reconcile explicitly lists `TopBar.java` as allowed, so this is handed to DLA as a governance/guard reconciliation item.

Not run:
- Maven compile/package, installer build, app launch, local Hook installation/update, device write, and Git stage/commit/push were not run because Owner explicitly forbade those actions for this DIB turn.

Known limitations for DLA review:
- No Java compiler/build validation was performed in this turn due to the explicit no-build instruction.
- Cursor metadata locations are implemented defensively for observed Cursor storage shapes (`conversation-search.db`, `workspaceStorage`, `state.vscdb` composer metadata); DLA should review against the actual target Cursor dataset before Owner preview.

---

Date: 2026-10-09
Actor: DIB
Mode: FIX
Contract revision: 4

Preflight:
- Re-ran `desktop.py preflight --role DIB --id WD-004`; result PASS for current IMPLEMENT / FIX / DIB route.
- Read DLA actual diff review result from `.ahakey-desktop-harness/changes/WD-004/REVIEW.json` and limited this round to the four required fail findings.

Fixed:
- Updated the shared MULTI Hook freshness gate in `StudioController.java` so Codex/Cursor passes when at least one related tool is `LATEST`. Manual apply, mode-switch auto apply, and firmware-ready auto snapshot now all pass the real per-tool latest flags into `AiRuntimeDisplayService` instead of treating both tools as available.
- Updated `CursorSessionDiscoveryService.java` to prefer the actual `composerHeaders` SQLite table in `state.vscdb`, use `composerId` as the stable session ID, skip archived/subagent rows, join title/workspace metadata when available, and keep the previous `ItemTable` JSON scan only as fallback when the table is absent.
- Updated `InspectorPane.java` so the primary-slot radio is enabled only for a bound and currently usable slot. Opening the task-slot dialog now calls `prepareApply(...)` with current Hook status first, so the UI reflects service-side primary-slot repair.
- Updated `TopBar.java` so single-tool Hook install/update uses a dialog-level busy state. The active button shows `安装中` or `更新中`, other Hook buttons and refresh are disabled until the write completes and the follow-up scan refreshes the list. The existing one-click update flow was left intact.

Checks actually run:
- `git diff --check -- src/main/java/com/example/ahakey/app/StudioController.java src/main/java/com/example/ahakey/service/CursorSessionDiscoveryService.java src/main/java/com/example/ahakey/view/InspectorPane.java src/main/java/com/example/ahakey/view/TopBar.java` exited 0; only CRLF normalization warnings were printed.
- Targeted read-only `rg` checks found no old `Codex && Cursor` apply gate, no default `applyToKeyboard()` auto-snapshot call in `StudioController.java`, no old `primary.setDisable(!slot.isBound())`, and no old single-button-only `runSingleHookWrite(String hookName, Button action, ...)` signature.
- `git status --short` was read only and confirms the workspace still contains substantial pre-existing dirty/untracked WD-004 and historical Harness files. No Git stage/commit/push was performed.

Not run:
- Maven compile/package, installer build, app launch, local Hook installation/update, device write, and Git stage/commit/push were not run because Owner explicitly forbade them for this FIX turn.
