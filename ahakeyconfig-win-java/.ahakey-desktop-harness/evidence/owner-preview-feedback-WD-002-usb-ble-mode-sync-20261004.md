# WD-002 Owner Preview Feedback - USB/BLE Mode Sync

Time: 2026-10-04
Task: WD-002 - WS2 CP4A Mode Sync + Display Status
Role capturing feedback: DLA
Scope: Owner Preview, not formal UAT PASS

## Owner Feedback

USB:

- Windows-to-keyboard mode switching is functionally OK. When the Owner selects different modes on the PC, the keyboard follows, although with some delay.
- Keyboard-to-Windows mode switching is functionally OK. When the Owner changes modes on the keyboard, the PC follows quickly relative to the previous blocker.

BLE:

- BLE driver can now be opened after launching the Preview JAR from the repository root so the existing `BLE_tcp_driver.exe` is visible to the application.
- Windows-to-keyboard mode switching over BLE is fast: each new mode selected in the PC UI is quickly reflected on the keyboard.
- UI display has a visible bounce: after the Owner clicks a new mode, the Windows UI first briefly returns to the old mode for less than about one second, then returns to the new mode.
- Keyboard-to-Windows mode switching is slow. BLE often takes about 3-4 seconds for the software to follow; USB takes about 2-3 seconds.

## DLA Triage

This is a Preview defect, not evidence that the CP4A HEX or BLE driver is wrong.

Probable causes:

- The application applies ordinary `0x00` status updates while a PC-initiated mode switch is still being confirmed. A stale/old status frame can briefly overwrite the optimistic target mode, then the later `0x92 OK + 0x00` confirmation sets the UI back to the new mode.
- Keyboard-originated mode changes depend on periodic status polling. The current packaged configuration has `status.poll.period.seconds=5`, matching the observed 2-4 second latency.

## Fix Request For DIB

Keep the WD-002 protocol contract:

- No new firmware opcode.
- PC-initiated mode switch still succeeds only after `0x92 OK` plus `0x00` readback matching the requested mode.
- Failure still returns visible Windows state to keyboard-authoritative mode.
- USB and BLE should have equivalent behavior.

Requested fix:

1. During PC-initiated mode switching, use optimistic UI semantics: after the user clicks a mode, Windows may show the selected target mode immediately, but stale `0x00` status frames must not visually bounce it back to the previous mode during the confirmation window.
2. Preserve keyboard-authoritative recovery on timeout, disconnect, non-OK response, or readback mismatch.
3. Keep offline browse-only semantics unchanged.
4. Do not change keyboard-originated mode-change polling/latency in this fix. Owner explicitly deferred that issue from the current batch.

Suggested implementation shape:

- Track the pending target mode while `modeSwitchInProgress` is true.
- In `applyBleStatus`, update battery/status fields from incoming status, but do not change `studioState.selectedMode` away from the optimistic target during the confirmation window unless the switch fails, disconnects, times out, or the confirmed readback completes.
- Do not lower the status polling period or add new keyboard-originated mode-change responsiveness behavior in this round.
- Add focused notes/checks for USB/BLE PC-initiated mode switching without UI bounce in the next execution report.

## Current Owner Test Disposition

- USB Preview: functionally OK but latency exists.
- BLE Preview: connection and PC-to-keyboard mode switch work, but UI bounce requires fix.
- Keyboard-to-Windows latency remains observed but is explicitly deferred by Owner for this batch.
- Formal Owner UAT: not passed.
