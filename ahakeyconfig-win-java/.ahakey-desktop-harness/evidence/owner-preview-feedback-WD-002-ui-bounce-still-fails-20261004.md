# WD-002 Owner Preview Feedback - UI bounce still fails

Time: 2026-10-04
Preview token: `preview-20261004T031045322075Z-f81ce2`
Role capturing feedback: DLA
Scope: Owner Preview, not formal UAT PASS

## Owner Feedback

Owner reports the previously supplied Preview JAR still has the same PC-initiated mode-switch UI bounce:

- When the Owner switches to a new mode from the Windows upper-computer UI, the keyboard has already switched to the new mode.
- Even though the keyboard is already in the new mode, the Windows UI still first returns to the old mode, then returns to the new mode.
- Owner asks to fix only this one issue.

## DLA Triage

This remains an original WD-002 Contract implementation bug within the Preview Fix fast lane.

The behavior indicates the keyboard-side command path succeeds, but the desktop visual selection is still being redrawn from an old UI/state path during the PC-initiated mode-switch window.

Deferred and out of scope for this fix:

- Keyboard-initiated mode-change follow latency.
- Polling period changes.
- Firmware/protocol changes.
- Release Batch / formal candidate / formal UAT.
