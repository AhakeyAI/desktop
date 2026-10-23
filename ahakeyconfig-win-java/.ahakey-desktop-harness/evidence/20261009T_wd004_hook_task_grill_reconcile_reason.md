# WD-004 DLA contract reconcile reason - Hook/task grill

DLA decision: this is WD-004 contract revision 3, not a new task.

Reason:

- The decisions refine the existing WD-004 WS3 CP1 AI runtime presentation journey. They do not add a new firmware protocol, new persistent device storage, resource upload, factory restore, firmware upgrade, or full capability table.
- Cursor is now explicitly included as a WD-004 task source alongside Codex. This is still within the approved Hook/runtime display scope because Cursor Hook compatibility and PR #78 behavior were already part of WD-004 revision 2.
- The new details change user-facing semantics and runtime slot matching behavior. They must be captured before DIB continues because they affect acceptance criteria, local persistence, Hook status model, task discovery, and 0x99 foreground behavior.
- The revision preserves the approved core protocol boundaries: SINGLE uses 0x90, MULTI uses complete 4-slot 0x99 snapshots, 0x98 mode control remains set-only, and 0x9A remains ACK-only compatibility.

Effective DIB boundary added by this revision:

- Implement detailed "AhaKey Hook 管理" UI behavior and status semantics from the Owner scope record.
- Implement Cursor local metadata discovery from `%APPDATA%\\Cursor\\User`, with configurable Cursor data directory in the task slot manager.
- Implement Cursor metadata-only session list grouped by tool -> project -> session, using `composerHeaders.composerId` as stable ID and `conversation-search.db.conversations.title` as preferred title source.
- Implement Cursor Hook full stdin JSON forwarding and session-ID runtime matching.
- Forbid project/workspace/cwd fallback for both Cursor and Codex runtime slot matching.
- Implement task selector availability, partial-unavailable prompts, all-unavailable blocking, and empty-state behavior.
- Implement 主槽位 selection, persistence, availability repair, and 0x99 foreground mapping.
- Keep Hook install/update safety behavior: backup first, replace/add only AhaKey hooks, preserve user non-AhaKey hooks, and do not expose uninstall UI in WD-004.

Allowed production paths for this reconcile:

- Existing WD-004 allowed production paths remain valid.
- Explicitly included for this revision:
  - `src/main/java/com/example/ahakey/view/TopBar.java`
  - `src/main/java/com/example/ahakey/view/InspectorPane.java`
  - `src/main/java/com/example/ahakey/app/StudioController.java`
  - `src/main/java/com/example/ahakey/service/HookInstaller.java`
  - `src/main/java/com/example/ahakey/service/HookDispatchServer.java`
  - `src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java`
  - `src/main/java/com/example/ahakey/service/*Codex*.java`
  - `src/main/java/com/example/ahakey/service/*Cursor*.java`
  - `src/main/java/com/example/ahakey/model/*Ai*.java`
  - `src/main/java/com/example/ahakey/model/*Codex*.java`
  - `src/main/java/com/example/ahakey/model/*Cursor*.java`
  - `src/main/java/com/example/ahakey/model/*Runtime*.java`
  - `src/main/java/com/example/ahakey/util/*Ai*.java`
  - `src/main/java/com/example/ahakey/util/*Codex*.java`
  - `src/main/java/com/example/ahakey/util/*Cursor*.java`
  - `src/main/java/com/example/ahakey/util/*Runtime*.java`
  - `src/main/resources/messages*.properties`
  - `src/main/resources`
  - `pom.xml` only if the existing approved SQLite dependency path is still required and the reason remains recorded.
  - `.ahakey-desktop-harness/changes/WD-004/**`
  - `.ahakey-desktop-harness/evidence/**`

Forbidden unless Owner separately authorizes:

- No production build/package/install as part of DLA reconcile.
- No local Hook installation/update execution on the Owner machine.
- No device writes, firmware flashing, or runtime display apply during DLA reconcile.
- No Git stage, commit, push, reset, or cleanup.
- No cloud Hook version service in WD-004.
- No full local firmware capability table in WD-004.
- No display of full chat content in the task selector.
- No project/workspace/cwd fallback to update runtime slots.
