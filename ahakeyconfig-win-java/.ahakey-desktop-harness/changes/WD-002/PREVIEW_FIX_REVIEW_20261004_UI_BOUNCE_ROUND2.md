# WD-002 Preview Fix Lightweight Review - UI mode bounce round 2

Time: 2026-10-04
Role: DLA
Mode: PREVIEW_FIX_REVIEW

## Reviewed inputs

- Owner Preview feedback: `.ahakey-desktop-harness/evidence/owner-preview-feedback-WD-002-ui-bounce-still-fails-20261004.md`
- DIB Preview Fix report: `.ahakey-desktop-harness/changes/WD-002/PREVIEW_FIX_REPORT_20261004_UI_BOUNCE_ROUND2.md`
- Actual source diff: `src/main/java/com/example/ahakey/app/StudioController.java`

## Review result

PASS for Preview Fix fast lane.

Rationale:

- The fix remains inside the original WD-002 Contract: no firmware opcode change, no protocol shape change, no polling-period change.
- The keyboard already switching successfully to the target mode means the remaining defect is desktop visual state handling.
- The guard now remains active for the full 5000 ms post-confirmation settle window, even if a target-mode status frame arrives first.
- Delayed old-mode status frames during that window cannot overwrite local `deviceStatus.workMode` or `studioState.selectedMode`.
- Failure, disconnect and mismatch paths still clear the guard and return visible state to keyboard-authoritative status.
- Keyboard-originated mode-change latency remains deferred and was not modified.

## Machine evidence reviewed

- `git diff --check`: exit code 0, CRLF warnings only.
- `mvn -q -DskipTests compile`: exit code 0 with `D:\jdk-17.0.19.10-hotspot`.
- `mvn -q test`: exit code 0 with `D:\jdk-17.0.19.10-hotspot`; no dedicated `src/test` behavior tests exist.

## Limits

This is not formal fresh review, not Git candidate, not formal UAT and not Owner Preview PASS. It only authorizes the next Preview build for Owner retest.
