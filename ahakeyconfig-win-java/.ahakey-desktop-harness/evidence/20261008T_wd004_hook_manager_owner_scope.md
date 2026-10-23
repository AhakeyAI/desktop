# WD-004 Owner scope confirmation - Hook manager boundary

Owner confirmed on 2026-10-08 that WD-004 should include the existing top-right "More -> Hook 管理" entry because WS3 CP1 AI runtime presentation depends on the newer Codex/Cursor hooks.

Facts provided by Owner:

- WD-004 is already in IMPLEMENT and DIB has produced one draft implementation.
- Current `TopBar.java` Hook 管理 scans Claude, Cursor, Codex, and Kimi, but is mainly binary Installed / Not Installed.
- WD-004 now needs Hook state to distinguish at least: 未安装 / 旧版 / 最新 / 异常.
- Light page "应用到键盘" and top-right Hook 管理 must use the same `HookInstaller.getHookStatus()` standard.
- Cursor hook update must follow AhakeyAI/desktop#78 direction: only explicit auto-allow outputs allow; manual, no response, or unavailable cases return control to Cursor native permission handling.
- Codex hook update must carry version marker `ws3-cp1-v1` and forward stdin JSON identity fields including `session_id`, `transcript_path`, `cwd`, `turn_id`, and `hook_event_name`.
- Installing or updating hooks must back up the original file and only replace or add the AhaKey hook. User-owned non-AhaKey hooks must not be silently overwritten.

Owner asked DLA to reconcile the WD-004 contract and produce the new DIB implementation boundary and allowed paths. Owner explicitly requested no build, no hook install, no device write, and no Git commit or push in this DLA step.
