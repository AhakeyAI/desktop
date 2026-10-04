# WD-002 Preview Fix Lightweight Review - UI mode bounce

Time: 2026-10-04
Role: DLA
Mode: PREVIEW_FIX_REVIEW

## Reviewed inputs

- Owner Preview feedback: `.ahakey-desktop-harness/evidence/owner-preview-feedback-WD-002-usb-ble-mode-sync-20261004.md`
- DIB Preview Fix report: `.ahakey-desktop-harness/changes/WD-002/PREVIEW_FIX_REPORT_20261004_UI_BOUNCE.md`
- Actual source diff: `src/main/java/com/example/ahakey/app/StudioController.java`

## Review result

PASS for Preview Fix fast lane.

Rationale:

- The fix is inside the original WD-002 Contract: PC-initiated mode switching still uses `0x92 OK` plus matching `0x00` readback; no firmware opcode or protocol shape changed.
- The UI optimistic target is protected while a PC-initiated mode switch is being confirmed.
- After successful confirmation, a short 1500 ms settle guard suppresses stale old-mode status frames from overwriting both `studioState.selectedMode` and local `deviceStatus.workMode`.
- Battery, connection, switch and firmware fields still update from status frames during the guard.
- Disconnect and failure paths clear the guard and continue returning visible state to keyboard-authoritative mode.
- The deferred keyboard-to-Windows latency issue was not changed: no polling period change, no new responsiveness path.

## Machine evidence reviewed

- `git diff --check`: exit code 0, CRLF warnings only.
- `mvn -q -DskipTests compile`: exit code 0 with `D:\jdk-17.0.19.10-hotspot`.
- `mvn -q test`: exit code 0 with `D:\jdk-17.0.19.10-hotspot`; no dedicated `src/test` behavior tests exist.

## Limits

This is not formal fresh review, not Git candidate, not formal UAT and not Owner Preview PASS. It only authorizes the next Preview build for Owner retest.
