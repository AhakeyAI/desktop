# WD-002 Preview Fix Report - UI mode bounce

Time: 2026-10-04
Role: DIB
Mode: PREVIEW_FIX

## Owner Preview feedback

Source:

`.ahakey-desktop-harness/evidence/owner-preview-feedback-WD-002-usb-ble-mode-sync-20261004.md`

Classified defect:

- Original WD-002 Contract implementation bug.
- PC-initiated mode switching worked, but the Windows UI could briefly bounce back to the old mode before returning to the new mode.
- Keyboard-initiated mode-change latency is explicitly deferred by Owner and was not changed.

## Code change

Changed:

- `src/main/java/com/example/ahakey/app/StudioController.java`

Implementation:

- Track the PC-initiated target mode while mode switching is in progress.
- Keep a short 1500 ms post-confirmation settle window for the confirmed target mode.
- During that window, stale status frames for a different mode may still update connection, battery, switch and firmware fields, but they do not overwrite local `deviceStatus.workMode` or `studioState.selectedMode`.
- A matching target status frame ends the guard after the confirmation thread has completed.
- Disconnect and failure paths clear the guard and continue to restore the visible state from keyboard-authoritative status.

Not changed:

- No firmware opcode change.
- No status polling period change.
- No keyboard-originated mode-change latency fix.
- No offline browse-only behavior change.
- No Release Batch, EXE, installer, Firmware, eternal or Git write action.

## Machine checks

- `desktop.py preflight --id WD-002 --role DIB`: PASS after v1.3 Preview Fix route state was aligned.
- `git diff --check`: exit code 0; only existing CRLF conversion warnings.
- `mvn -q -DskipTests compile`: exit code 0 using `D:\jdk-17.0.19.10-hotspot`.
- `mvn -q test`: exit code 0 using `D:\jdk-17.0.19.10-hotspot`; repository still has no dedicated `src/test` coverage for this behavior.

## Limits

This report records source and machine checks only. It is not Owner Preview PASS and not formal UAT PASS.
