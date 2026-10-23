# WD-004 Isolation From Existing Work

Date: 2026-10-08

WD-004 is approved as a new WS3 CP1 AI runtime presentation Windows adapter task.

Existing workspace changes and paused/historical Harness records are not part of WD-004 unless they are explicitly listed in WD-004 allowed paths and changed by this implementation.

WD-004 must not revert, clean, stash, or overwrite pre-existing work. It must preserve:

- prior WD-001/WD-002/WD-003 records and artifacts;
- existing config_server.json local state;
- existing build/preview artifacts;
- unrelated repository dirty files.

WD-004 implementation scope remains the approved Contract:

- AI runtime display mode and task-slot UI;
- Codex session discovery and hook identity forwarding;
- Cursor hook non-blocking repair based on PR #78 behavior;
- WS3 CP1 0x98/0x99/0x9A protocol sends under narrow 0x9F catalog-key gate;
- no full local capability table, which is deferred to WS005.
