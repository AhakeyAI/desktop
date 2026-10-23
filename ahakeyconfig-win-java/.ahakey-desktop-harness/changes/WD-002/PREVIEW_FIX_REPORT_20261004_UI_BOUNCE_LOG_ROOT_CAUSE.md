# WD-002 Preview Fix Report - UI bounce log root cause

## Scope

Fix only the Windows-initiated mode switch UI bounce where the UI briefly returns to the previous mode before showing the new mode.

Keyboard-initiated mode switch follow latency is not changed.

## Log finding

The logs show the keyboard accepts the mode switch quickly with the `0x92` acknowledgement. The BLE bridge also reports the new work mode through `DEVICE_INFO_RESP`.

However, `BleManager.setWorkModeAndVerify()` waited only for a `0x00` status notify frame after the `0x92` acknowledgement. When that specific response timed out, the controller treated the switch as failed and rolled the UI back to the previous authoritative mode. A later status update then moved the UI back to the new mode.

This matches the Owner-observed random bounce: the device was already in the new mode, but the Windows app produced a false failure rollback.

## Change

- Keep the `0x92` acknowledgement requirement for mode switch commands.
- Replace the narrow post-ack `0x00` wait with a refreshed work-mode readback window.
- Accept refreshed cached status from BLE `DEVICE_INFO_RESP` as valid readback when it reports the requested target mode.
- Request BLE status, device info, and normal device status during the readback window.
- Keep the previous UI stale-status guard, but reduce the post-confirmation settle window back to 1500 ms.

## Files

- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/app/StudioController.java`

## Checks

- `git diff --check`: PASS
- `mvn -q -DskipTests compile` with JDK 17: PASS
- `mvn -q test`: PASS
