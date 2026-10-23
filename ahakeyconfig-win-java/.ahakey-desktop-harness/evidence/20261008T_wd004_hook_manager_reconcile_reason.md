# WD-004 DLA contract reconcile reason - Hook manager

DLA decision: this is a WD-004 contract revision, not a new task.

Reason:

- The new boundary is still part of the same WS3 CP1 AI runtime presentation user journey. It does not introduce a new firmware protocol, a new provider for MULTI, a new persistent device behavior, or resource upload behavior.
- The dependency is direct: MULTI runtime display requires Codex/Cursor hook updates and the Owner-facing Hook 管理 entry must use the same version standard as the Light page apply gate.
- `src/main/java/com/example/ahakey/view/TopBar.java` and `src/main/java/com/example/ahakey/service/HookInstaller.java` were already within the WD-004 allowed area or guard footprint, but the textual contract did not explicitly require Hook 管理 four-state status and install/update behavior. This reconcile closes that gap.

Effective revised boundary for DIB:

- Hook 管理 must auto-scan status when opened.
- Codex and Cursor are strongly required to show at least four states: 未安装 / 旧版 / 最新 / 异常.
- For Codex and Cursor, 未安装 or 旧版 must present a primary action labeled "安装/更新 Hook". 异常 may use the same repair action if the installer can safely repair after backup.
- Hook 管理 and Light page "应用到键盘" gate must share the same `HookInstaller.getHookStatus()` standard, version marker, and latest-version definition.
- Installing or updating Codex/Cursor hooks must back up the original file first and must preserve user-owned non-AhaKey hook entries. Only the AhaKey hook entry/script may be replaced or added.
- If any visible uninstall/removal action remains for Codex/Cursor in Hook 管理, it must only remove AhaKey-owned entries and must preserve non-AhaKey hooks.
- Codex generated hook must include marker `ws3-cp1-v1` and forward stdin JSON identity fields including `session_id`, `transcript_path`, `cwd`, `turn_id`, and `hook_event_name`.
- Cursor generated hook must follow AhakeyAI/desktop#78 behavior: output allow only when the AhaKey decision is explicitly auto-allow; manual, no response, unavailable, or error cases must defer to Cursor native permission flow.
- Hook 管理 success must make the Light page apply gate pass without a different second definition of "latest".
- Hook 管理 must not automatically install or update hooks just by opening the dialog.
- Hook 管理 must not apply runtime display bindings to the keyboard; that remains the Light page "应用到键盘" action.

Claude/Kimi scope:

- WD-004 strongly requires four-state latest-version semantics only for Codex and Cursor.
- Claude and Kimi may remain on existing installed / not installed behavior in this stage unless DIB has to touch shared UI plumbing. If shared plumbing makes four-state display simpler, DIB may display four states for them too, but WD-004 acceptance must not depend on Claude/Kimi version migration and must not regress their existing install behavior.

Allowed production paths for this reconcile:

- Existing WD-004 allowed paths remain valid.
- Explicitly included for this reconcile:
  - `src/main/java/com/example/ahakey/view/TopBar.java`
  - `src/main/java/com/example/ahakey/service/HookInstaller.java`
  - `src/main/java/com/example/ahakey/service/HookDispatchServer.java`
  - `src/main/java/com/example/ahakey/service/HookClient.java`
  - `src/main/java/com/example/ahakey/app/StudioController.java`
  - `src/main/java/com/example/ahakey/view/InspectorPane.java`
  - `src/main/resources/messages*.properties`
  - `.ahakey-desktop-harness/changes/WD-004/**`
  - `.ahakey-desktop-harness/evidence/**`

Forbidden in this reconcile and next DIB implementation unless separately authorized:

- No build or packaging as part of this DLA reconcile.
- No local hook installation/update execution on the Owner machine.
- No device writes, firmware flashing, or runtime display apply during DLA reconcile.
- No Git stage, commit, push, reset, or cleanup.
- No new providers for MULTI and no broad firmware capability table in WD-004.
