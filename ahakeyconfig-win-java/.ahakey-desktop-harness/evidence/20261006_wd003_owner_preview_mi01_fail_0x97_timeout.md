# WD-003 Owner Preview FAIL - mi_01 selected, 0x97 timeout blocks follow-up reads

Preview token: `preview-20261006T033312012647Z-3272d5`

Scope: Owner Preview result only. This is not formal Owner UAT, not release, and not a formal delivery candidate result.

## Owner Feedback

Owner reported that firmware version/catalog can be read, but sleep wait time is not shown in the UI. The side-switch CP4C UI appears, but it displays an input configuration read failure.

Screenshots:

- `.ahakey-desktop-harness/evidence/20261006_wd003_preview_mi01_fail_sleep_0x95.png`
- `.ahakey-desktop-harness/evidence/20261006_wd003_preview_mi01_fail_0x97_timeout.png`

Runtime log:

- `.ahakey-desktop-harness/evidence/20261006_wd003_preview_mi01_fail_runtime_log.txt`

## Observed Evidence

- USB HID path selected `mi_01`:
  `USB HID connected: \\?\hid#vid_413c&pid_2107&mi_01#...`
- `0x9F` catalog read succeeded:
  `Firmware catalog key: x1-c582-hw1-p1-1.0.0-r001`
- CP4C side-switch readback started and sent `0x97`:
  `Reading CP4C side switch config with command 0x97`
  `发送命令: AABB97CCDD`
- The USB reader stopped shortly after the `0x97` send:
  `USB HID read stopped: 1167`
- Later status polling reconnected to `mi_01` and `0x00` status polling worked.
- Sleep wait time UI read started, but timed out before the blocked command queue released:
  `Sleep wait time UI read timed out: serial=1`
- After the `0x97` timeout, `0x95` was actually sent and answered:
  `发送命令: AABB95CCDD`
  `数据内容(前16字节): AA BB 95 00 3C 00 CC DD`
  `Sleep wait time read: 60 minutes`
- UI ignored the late `0x95` response as stale:
  `Sleep wait time UI update ignored for stale read: serial=1, current=2`

## DLA Classification

This is still an Owner Preview FAIL.

The previous failure mode was broad USB HID write failure caused by selecting `mi_00&col02`. This preview shows that the transport now selects `mi_01` and can successfully read `0x9F`.

The remaining failure appears to be inside the original WD-003 contract surface: CP4C input readback through `0x97` blocks or times out, and the blocked/late command flow causes the sleep wait UI read to time out even though `0x95` later receives a valid response. This is classified as an original-contract implementation bug for Preview fast-lane handling, pending DIB diagnosis.

No protocol semantic change is authorized by this record.
