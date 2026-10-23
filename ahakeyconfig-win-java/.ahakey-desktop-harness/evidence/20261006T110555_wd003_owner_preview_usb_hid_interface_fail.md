# WD-003 Owner Preview FAIL - USB HID interface selection

Date: 2026-10-06
Change: WD-003
Role: DLA
Mode: DEFECT_TRIAGE / SCOPE_RECONCILE
Preview token: preview-20261006T020818762431Z-95879e

## Owner Feedback

Owner reported during WD-003 preview:

- Side-switch CP4C editable form did not appear; the UI stayed on the legacy Auto/Manual side-switch panel.
- Device status query/save failed.
- Firmware version readback and sleep wait time readback, which previously worked, failed.
- The user-visible error included: `USB HID write failed: 1`.

This is recorded as Owner Preview FAIL only. It is not formal Owner UAT, release, or real-device PASS/FAIL for formal delivery.

## Evidence Summary

Preview runtime log showed the current WD-003 preview connected to:

```text
hid#vid_413c&pid_2107&mi_00&col02
```

and failed immediately when sending basic configuration commands such as `0x9F` and `0x95`:

```text
Firmware catalog key read skipped/fallback: USB HID write failed: 1
Sleep wait time UI read failed: java.io.IOException: USB HID write failed: 1
```

Earlier known-good WD-002 runtime evidence showed successful configuration traffic when connected to:

```text
hid#vid_413c&pid_2107&mi_01
```

with successful `0x9F` catalog key and `0x95` sleep wait time reads.

Firmware source inspection found that the current firmware command handlers for `0x9F`, `0x95`, `0x97`, and `0x87` still exist. Firmware USB descriptor code presents interface 0 for keyboard/consumer HID and interface 1 for vendor/config traffic. Therefore the strongest current diagnosis is that Windows selected the wrong HID interface/collection for configuration traffic.

Windows source inspection found `UsbHidTransport.findDevicePath()` currently accepts either `mi_01` or `col02` for VID `413c` PID `2107`. The `col02` path can select the keyboard/consumer HID collection under `mi_00`, which is not the vendor/config command interface and rejects the current write path.

## Defect Classification

Classification: original WD-003 contract implementation bug / preview blocker.

Rationale:

- WD-003 requires connection/reconnection `0x9F` catalog gating before CP4C readback.
- The failure prevents `0x9F` from reaching firmware, so CP4C gating falls back to legacy behavior and the new side-switch form never appears.
- The failure also breaks existing baseline configuration reads such as `0x95`, making it a precondition defect in the approved input-domain integration.
- No new product behavior is being requested.
- No protocol semantic change is required.

## Scope Reconcile Decision

DLA approves adding the existing transport file to the WD-003 effective implementation boundary only for this preview defect:

```text
src/main/java/com/example/ahakey/service/UsbHidTransport.java
```

The allowed repair is limited to USB HID configuration interface selection:

- Do not treat `col02` as sufficient evidence of the config channel.
- Prefer or require `mi_01` for the AhaKey USB vendor/config interface.
- If probing is added, it must only skip non-config interfaces and must not change protocol semantics.
- Do not change `0x87`, `0x97`, `0x9F`, or `0x95` firmware/host protocol semantics.
- Do not add new product UI or unrelated transport behavior.

