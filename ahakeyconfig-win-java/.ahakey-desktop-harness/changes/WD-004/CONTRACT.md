# WD-004 - WS3 CP1 AI runtime presentation Windows adapter

Status: DLA draft. This Contract records the proposed Windows scope for Owner approval. It is not implementation permission until approved through the Harness.

## Owner Direction And Goal

Owner wants Windows to adapt firmware WS3 CP1 so that AI workflow runtime state can appear on the keyboard light/display surface:

- Keep this inside the existing Light right-side options, not as a new main page and not as persistent OLED/resource configuration.
- Provide a global manual switch between SINGLE and MULTI.
- Send 0x98 immediately when the user switches mode, and remember the preference locally in Windows.
- In MULTI, let the user manage four followed task slots through a dialog/drawer.
- First provider is Codex only.
- Show all local Codex sessions grouped by project and ordered by time, similar to the Codex sidebar.
- Let the user bind a selected session to Slot 1-4.
- Do not send while editing. Send only when the user clicks "应用到键盘".
- After applying, send another full 0x99 snapshot only when a bound Codex session has a recognized state change. No periodic keepalive.

Owner record: `.ahakey-desktop-harness/evidence/20261008T_ai_runtime_multi_codex_owner_record.md`

## Change Classification And Journey

- `change_classification`: `scope_expansion`, `architecture_change`, `protocol_change`
- `journey_ids`: `J004`
- `review_policy`: `high_impact`

Journey J004:

- Entry: Light right-side AI runtime display controls.
- Windows owns local display mode preference, Codex data directory, slot bindings, hook-derived per-session runtime state, and 0x98/0x99/0x9A host commands.
- Firmware owns volatile runtime presentation lifecycle and clearing behavior on timeout, disconnect, Quiet, and Sleep.

## Implementation Scope

Windows production code may implement:

- Protocol builders for WS3 CP1:
  - 0x98 set runtime display mode, set-only: SINGLE=0, MULTI=1.
  - 0x99 version 1 complete four-slot snapshot: each slot has valid/state/foreground.
  - 0x9A compatibility ACK command only if needed by the existing transport surface.
  - Legacy 0x90 remains the SINGLE global AI state path.
- BleManager methods for 0x98/0x99/0x9A send paths, preserving existing connection and error behavior.
- Internal model for runtime display mode, four slot bindings, foreground slot, Codex session identity, and slot runtime state.
- Local persistence for:
  - global SINGLE/MULTI preference,
  - Codex data directory,
  - four slot bindings,
  - last applied slot set if needed for connect/reconnect behavior.
- Codex session discovery:
  - default data directory: `%USERPROFILE%\.codex`;
  - user can choose another Codex data directory;
  - prefer stable local index/database such as `state_5.sqlite` and `session_index.jsonl`;
  - do not recursively scan arbitrary transcript files as the primary source;
  - invalid/unreadable directory shows "未找到 Codex 会话记录" and does not affect SINGLE.
- Narrow firmware gate for this round:
  - use the existing 0x9F catalog key read path when available;
  - treat `x1-c582-hw1-p1-1.0.0-r001` as the known new firmware key for WS3 CP1 device writes;
  - treat old firmware, missing 0x9F, failed 0x9F, or unknown catalog key as legacy/unsupported for WS3 CP1 MULTI device writes;
  - do not build a full local capability table in WD-004.
- Codex hook forwarding:
  - update generated Codex hook scripts so Java receives event name plus hook stdin identity, especially `session_id`, `transcript_path`, `cwd`, `turn_id`, and `hook_event_name` when present;
  - keep legacy event-only input accepted for Claude/Kimi/Cursor and for old installed hooks.
- Runtime routing:
  - SINGLE mode: keep current 0x90 global behavior.
  - MULTI mode: match Codex hook payload by stable slot identity, update only the matching bound slot, fold internal 9-state IDEState to firmware waiting/running/done, then send a full four-slot 0x99 snapshot.
  - Unmatched events must not change the MULTI display.
  - Switching to SINGLE keeps bindings but stops MULTI snapshots.
  - Switching back to MULTI automatically sends the current applied bindings snapshot.
- Light-side UI:
  - add an "AI 运行展示" group in the existing Light inspector area;
  - show mode switch, four-slot summary, and a "管理关注任务槽" entry;
  - use a dialog/drawer for slot management;
  - first version uses button binding, not drag and drop;
  - button text for sending the draft to the keyboard is exactly "应用到键盘";
  - show project name + session name in slot cards, with full path/stable ID in details.

Allowed production paths:

- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/service/HookDispatchServer.java`
- `src/main/java/com/example/ahakey/service/HookInstaller.java`
- `src/main/java/com/example/ahakey/service/HookClient.java`
- `src/main/java/com/example/ahakey/service/*Codex*.java`
- `src/main/java/com/example/ahakey/service/*Runtime*.java`
- `src/main/java/com/example/ahakey/model/*Ai*.java`
- `src/main/java/com/example/ahakey/model/*Codex*.java`
- `src/main/java/com/example/ahakey/model/*Runtime*.java`
- `src/main/java/com/example/ahakey/model/IDEState.java`
- `src/main/java/com/example/ahakey/model/StudioState.java`
- `src/main/java/com/example/ahakey/app/StudioController.java`
- `src/main/java/com/example/ahakey/view/InspectorPane.java`
- `src/main/java/com/example/ahakey/util/*Ai*.java`
- `src/main/java/com/example/ahakey/util/*Codex*.java`
- `src/main/java/com/example/ahakey/util/*Runtime*.java`
- `src/main/resources/messages*.properties`
- `pom.xml` only if implementation proves a dependency is required and the reason is recorded.

## Preserved Behavior

Must not change:

- ordinary key readback/write behavior;
- side switch 0x97 behavior;
- Voice 0x96 behavior;
- sleep wait time 0x95 behavior;
- firmware capability 0x9F behavior;
- mode sync 0x92 behavior;
- status query 0x00 behavior;
- persistent light-effect save semantics;
- resource upload, image/GIF preview saving, resource partition writes, display factory restore, whole-device Restore Factory, firmware upgrade/recovery, or full Host Protocol.

## Protocol And State Semantics

Firmware WS3 CP1 facts:

- 0x90 is valid only in SINGLE mode and displays one legacy AI state.
- 0x98 is set-only and has no query/readback.
- 0x99 accepts a complete four-slot snapshot only in MULTI mode.
- 0x99 v1 slot state values are empty/off through `valid=0`, running=1, waiting=2, done=3.
- 0x9A is ACK-only compatibility and does not report active mask or extend display state.
- Firmware clears AI/task runtime state after five minutes without refresh, on USB/BLE disconnect, and on Quiet/Sleep, while retaining display mode.

Windows device-write gating for WD-004:

- The only allowlisted new-firmware catalog key for WS3 CP1 device writes in this round is `x1-c582-hw1-p1-1.0.0-r001`.
- If 0x9F is missing, times out, cannot be parsed, or returns an unknown key, Windows must not send 0x98, 0x99, or 0x9A.
- Legacy SINGLE 0x90 behavior remains available where it already worked.
- Local MULTI slot binding and Codex session management remain available even when device writes are gated off.
- Windows must not infer WS3 CP1 support from visible firmware version text, from `1.0.0` status bytes, or by trial-sending 0x98/0x99.

Desktop mapping:

- waiting: `Notification`, `PermissionRequest`
- running: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`
- done: `Stop`, `TaskCompleted`, `SessionEnd`

Historical Codex sessions with no current explicit event are shown as done when applied.

## Verification And Owner Test

Machine checks:

- compile the Java project;
- unit/static checks for protocol bytes where practical;
- inspect that 0x98/0x99 framing matches firmware WS3 CP1;
- verify legacy event-only hook input still maps to 0x90 in SINGLE.

Owner/device test outline:

- connect WS3 CP1-capable keyboard;
- switch SINGLE/MULTI from Light right-side UI and confirm immediate 0x98 send behavior;
- in SINGLE, trigger a Codex/AI hook and confirm 0x90 legacy state display;
- in MULTI, bind up to four Codex sessions and click "应用到键盘";
- confirm a full 0x99 snapshot is sent and slots display waiting/running/done;
- confirm editing the dialog alone does not send;
- confirm unmatched hook events do not pollute bound slots;
- confirm switching to SINGLE stops MULTI snapshot sends while preserving bindings;
- confirm switching back to MULTI sends the current applied snapshot;
- confirm firmware clears runtime display after disconnect, timeout, Quiet, or Sleep according to firmware behavior.

Completion means Windows internal integration is ready for Owner Preview/UAT against the specified firmware gate. It does not mean installer release or whole-device release.

## Exclusions And Deferred Work

Out of scope:

- non-Codex providers for MULTI;
- automatic IDE/process discovery beyond local Codex session records;
- full chat transcript viewing in the selector;
- periodic 0x99 keepalive;
- drag/drop slot management;
- persistent keyboard storage of runtime display state or slot bindings;
- resource upload or display asset management.
- full local firmware capability table or release catalog behavior; deferred to WS005.

Deferred WS005:

- Local Windows firmware capability resolver/table.
- Full mapping of prior WS1, WS2, and WS3 stage differences across old/new firmware.
- Consolidation of 0x95, 0x96, 0x97, 0x87, 0x90, 0x98, 0x99, 0x9A, and 0x9F feature availability into one maintainable model.
- Evidence record: `.ahakey-desktop-harness/evidence/20261008T_ws005_local_capability_table_deferred.md`.

## Approval

Owner must approve this Contract before implementation starts. After approval, DIB may implement only within this scope and allowed paths. Any new provider, new persistent device behavior, new resource protocol, or different refresh policy must return to CHANGE.
