# WD-003 Preview Fix Review - CP4C 0x97 action envelope

Token: `preview-fix-20261006T072126898999Z-f7e8b6`

Decision: `pass`

Scope: Preview Fix review only. This is not formal high-impact fresh review, not a Git candidate, not a formal build, not Owner UAT, not true-device PASS, and not a release.

## Reviewed Inputs

- Request: `.ahakey-desktop-harness/previews/WD-003/fixes/preview-fix-20261006T072126898999Z-f7e8b6/REQUEST.json`
- Submission: `.ahakey-desktop-harness/previews/WD-003/fixes/preview-fix-20261006T072126898999Z-f7e8b6/SUBMISSION.json`
- Implementation report: `.ahakey-desktop-harness/previews/WD-003/fixes/preview-fix-20261006T072126898999Z-f7e8b6/PREVIEW_FIX_REPORT.md`
- Machine evidence: `.ahakey-desktop-harness/evidence/20261006T1535_wd003_preview_fix_cp4c_action_machine_checks.log`

## Conclusion

The implementation is within WD-003 revision 6 Preview Fix scope.

- `0x97` side-switch Custom shortcut actions are now wrapped as `0x73 len keycodes...`.
- `0x97` side-switch Custom macro actions are now wrapped as `0x74 len macroBytes...`.
- The reviewed save path no longer sends bare HID keycodes as `0x97` Custom action payloads.
- The side-switch Custom Shortcut UI now supports modifier combinations such as `Left Ctrl + V`.
- The current CP4C `0x97` readback action budget is surfaced and enforced before send; oversized long macros are not silently truncated.
- `0x97` readback parsing preserves action payload bytes, so save verification compares the same envelope format expected by current firmware.

## Evidence Checked

- JDK17 Maven compile recorded exit code `0`.
- Static grep recorded no forbidden `0x98` ordinary-key readback.
- Static grep recorded no `col02` / `mi_00&col02` configuration-channel regression.
- Encoding samples match the reconciled firmware contract:
  - Backspace: `73012A`
  - Enter: `730128`
  - Ctrl+V: `7302E019`
  - Dual Custom Backspace/Enter `0x97` save frame: `AABB9701030373012A0303730128CCDD`

## Notes

This review did not modify firmware and did not perform device I/O. The next step is to rebuild an Owner Preview artifact, then ask Owner to validate on the current firmware that `0x9F`, `0x95`, `0x97`, `0x87`, side-switch save/readback, combination shortcut save/readback, and short macro behavior work on real hardware.
