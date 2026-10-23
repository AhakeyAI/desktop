# WD-003 Owner Decision - CP4C side-switch action scope

At 2026-10-06T15:17:51+08:00, Owner confirmed the Windows-side Preview Fix scope for CP4C side-switch Custom actions:

- Complete single-key shortcut support.
- Complete combination shortcut support, for example Ctrl+V.
- Complete short macro support.
- Do not solve arbitrary/oversized macro support in this stage.
- Update the Windows UI accordingly.

This is a WD-003 Contract revision decision for the existing CP4C input configuration domain. It does not approve light, OLED/GIF/image, Voice, Power, Restore Factory, CP5, firmware upgrade/recovery, HID descriptor, full Host Protocol, release, installer packaging, device write, flashing, Git write, or formal Owner UAT.

Protocol/product interpretation recorded for DIB:

- `0x97` side-switch Custom action payload must use the firmware action envelope:
  - shortcut: `0x73 len keycodes...`
  - macro: `0x74 len macroBytes...`
- Windows must not save a `0x97` Custom action as a bare HID keycode.
- Combination shortcut is not oversized: Ctrl+V is expected to encode as `73 02 E0 19`.
- Current firmware-side CP4C `0x97` readback is constrained by one 64-byte USB report. The current anchor is 52 bytes total action payload across both side-switch positions.
- Windows should support single key, combination shortcut and short macro. Oversized macro handling may fail/disable/prompt instead of being fully solved in this stage, but must not be silently truncated into a misleading save success.
