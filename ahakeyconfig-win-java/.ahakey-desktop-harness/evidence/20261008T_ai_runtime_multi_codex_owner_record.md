# Owner Record: WS3 CP1 AI runtime multi-slot display

Date: 2026-10-08

Owner approved the product direction for Windows adaptation of firmware WS3 CP1 AI runtime presentation:

- Add a global manual AI runtime display mode switch in the Light right-side options, not a new main page and not inside persistent Inspector/OLED/resource configuration.
- The switch supports SINGLE and MULTI, sends 0x98 immediately, and is remembered locally by Windows.
- MULTI manages four focused task slots through a dialog/drawer entered from the Light panel.
- First version supports Codex only.
- Codex sessions are discovered from the local Codex data directory, defaulting to `%USERPROFILE%\.codex`, with a user-selectable Codex data directory.
- The selector groups sessions by project and sorts sessions by time, similar to the Codex sidebar.
- The selector shows Codex session summaries and metadata only, not full chat contents.
- Editing slot bindings does not send to the keyboard. The explicit button text is "应用到键盘".
- Clicking "应用到键盘" sends one complete 4-slot 0x99 snapshot.
- After applying, Windows does not send timer keepalive snapshots. It sends another complete 0x99 only when a bound Codex session has a recognized state change.
- When switching to SINGLE, Windows keeps local slot bindings but stops sending MULTI snapshots.
- When switching back to MULTI, Windows automatically sends the current applied slot snapshot.
- SINGLE keeps legacy 0x90 behavior for one global AI state.
- MULTI maps the internal nine IDE states to firmware slot states waiting/running/done.
- To make MULTI work, Codex hook forwarding must preserve per-session identity from the hook payload, instead of only forwarding the event name.

Explicit exclusions for this round:

- No resource upload, image/GIF preview persistence, resource partition writes, display factory restore, whole-device factory restore, firmware upgrade/recovery, or full Host Protocol.
- No changes to ordinary key configuration, side switch configuration, Voice, sleep wait time, firmware capability, mode sync, or status query semantics.
- No polling all Codex files for arbitrary content changes as runtime status.
