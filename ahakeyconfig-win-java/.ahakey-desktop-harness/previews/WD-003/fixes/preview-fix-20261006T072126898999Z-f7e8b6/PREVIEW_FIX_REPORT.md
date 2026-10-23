# WD-003 Preview Fix Report - CP4C 0x97 action envelope

Token: `preview-fix-20261006T072126898999Z-f7e8b6`

## Scope

This Preview Fix addresses the Owner Preview failure where CP4C side-switch save sent bare HID keycodes in `0x97` Custom actions and firmware returned status `2`.

The fix stays inside the WD-003 reconciled Contract:

- Shortcut actions are wrapped as `0x73 len keycodes...`.
- Macro actions are wrapped as `0x74 len macroBytes...`.
- Bare HID keycodes are no longer sent as `0x97` Custom action payloads.
- Side-switch Custom Shortcut UI supports modifier combinations such as Left Ctrl + V.
- Current firmware `0x97` readback action budget is surfaced and enforced before send; long macros are not silently truncated.

## Production Files Changed In This Preview Fix

- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
- `src/main/java/com/example/ahakey/service/DeviceSyncService.java`
- `src/main/java/com/example/ahakey/model/StudioState.java`
- `src/main/java/com/example/ahakey/view/InspectorPane.java`

## Implementation Notes

- `DeviceSyncService` now has side-switch-specific action envelope helpers for save and readback.
- `StudioState` stores CP4C side-switch Custom actions in the firmware envelope format.
- `AhaKeyProtocol.setSideSwitchConfig()` validates Custom action envelopes and rejects over-budget payloads instead of truncating.
- `InspectorPane` side-switch Custom Shortcut editor now uses a key list with add/delete, allowing one base key plus modifiers.
- The UI shows the current combined Custom action byte usage against the 52-byte CP4C `0x97` readback budget.

## Machine Checks

Evidence log: `.ahakey-desktop-harness/evidence/20261006T1535_wd003_preview_fix_cp4c_action_machine_checks.log`

Recorded checks:

- JDK17 Maven compile: exit code `0`.
- Static grep: no forbidden `0x98` ordinary-key readback match.
- Static grep: no `col02` / `mi_00&col02` config-channel selection reintroduced.
- Static grep: no side-switch action truncation pattern; only explicit storage-limit validation remains.
- Encoding sample:
  - Backspace -> `73012A`
  - Enter -> `730128`
  - Ctrl+V -> `7302E019`
  - Both Custom Backspace/Enter side-switch frame -> `AABB9701030373012A0303730128CCDD`

## Not Claimed

This is not a formal DLA review pass, not a Git candidate, not a formal build, not Owner UAT, not true-device PASS, and not a release.
