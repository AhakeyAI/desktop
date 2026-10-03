# WD-002 Owner Alignment Patch - Q7 Offline Edit Boundary

Status: OWNER_CONFIRMED_ALIGNMENT_PATCH
Role: DLA
Harness: AhaKey Windows Harness v1.0.1
Date: 2026-10-03

## Scope

Change: WD-002 - WS2 CP4A Mode Sync + Display Status

This record captures an Owner correction made during DIB implementation after DIB noticed that the previous Q7 language treated offline draft editing as allowed.

This record does not modify Java, Firmware, eternal, Git, build artifacts, candidate state, or test status.

## Superseded Q7 Meaning

The previous Q7 language allowed:

- offline browsing of local drafts
- offline local draft editing
- disabled device-write actions while disconnected

Owner corrected this because configuration editing is keyboard configuration editing, not a disconnected local-only editing journey.

## Corrected Q7 Meaning

Confirmed:

- Offline state is browse-only for keyboard configuration.
- Users may inspect existing local drafts / local view while disconnected.
- Users must not enter configuration edit state while disconnected.
- Clicking Edit Configuration should first try to connect the keyboard.
- If connection does not succeed, Desktop remains out of edit state.
- Device-write actions remain disabled while disconnected.
- Mode picker offline use must not send `0x92` or queue replay.
- Existing local drafts remain preserved and are not discarded.

Suggested existing UI/status wording:

`连接键盘后可保存/应用`

## DIB Implementation Meaning

DIB should adjust the current unsubmitted implementation to this corrected Q7:

- Keep connected-state Mode picker semantics from Q1.
- Keep `0x92 OK` plus `0x00` readback confirmation.
- Keep keyboard-originated mode follow and draft-preserved messaging.
- Do not implement offline keyboard configuration editing.
- Keep Edit Configuration as the connect-first entry.
- Do not let Mode picker save configuration, call `saveConfig`, or upload OLED.
- Preserve WD-001 `0x95` / `0x9F` regression behavior.

## Status Impact

This is a CHANGE alignment patch, not a DIB submission.

Current in-progress DIB diff is not a formal candidate and may contain old-Q7 behavior. It must be reviewed and adjusted by DIB before any builder submission.
