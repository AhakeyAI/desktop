# WD-002 Preview Fix Report - UI mode bounce round 2

Time: 2026-10-04
Role: DIB
Mode: PREVIEW_FIX

## Owner Preview feedback

Source:

`.ahakey-desktop-harness/evidence/owner-preview-feedback-WD-002-ui-bounce-still-fails-20261004.md`

Classified defect:

- Original WD-002 Contract implementation bug.
- When the Owner switches mode from the Windows UI, the keyboard has already switched to the new mode.
- The Windows UI still briefly returns to the old mode before returning to the new mode.
- Owner asked to fix only this issue.

## Code change

Changed:

- `src/main/java/com/example/ahakey/app/StudioController.java`

Implementation:

- Keep the existing PC-initiated mode target guard.
- Extend the post-confirmation settle window from 1500 ms to 5000 ms.
- Do not clear the guard just because a matching target status frame arrives during the settle window.
- During the guard, stale status frames for any non-target mode continue to update general device fields where safe, but do not overwrite local `deviceStatus.workMode` or `studioState.selectedMode`.

Why this addresses the remaining bounce:

- The first fix allowed the guard to clear as soon as a target-mode status arrived after confirmation.
- If a delayed old-mode status arrived after that early clear, the Windows UI could still bounce back.
- This fix keeps the UI target guarded for the full settle window, so delayed old-mode frames cannot redraw the UI during the visible bounce interval.

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
