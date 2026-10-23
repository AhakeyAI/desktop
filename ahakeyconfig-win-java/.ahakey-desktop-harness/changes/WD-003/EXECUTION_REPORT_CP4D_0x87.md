# WD-003 CP4D 0x87 Windows Execution Report

Date: 2026-10-07

## Identity And Scope

- Role: DIB, mode: IMPLEMENT.
- Preflight: `python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-003` returned PASS.
- Contract revision: WD-003 revision 7 / build_round 8 after DLA contract reconcile for CP4D `0x87` single-packet ordinary-key readback.
- Modified production files are within WD-003 allowed_paths: `AhaKeyProtocol.java`, `AhaKeyResponseParser.java`, `BleManager.java`, `DeviceSyncService.java`, `StudioState.java`, `StudioController.java`.
- No firmware edit, no Git add/commit/push/reset/clean/stash, no installer build, no install, no device write, no flash, no formal Owner UAT.

## Actual Changes

- Added Windows protocol constants for `0x87` status values: OK `0`, invalid payload `1`, out of range/unsupported action `2`, too large `3`.
- Tightened `0x87` parser to accept only one complete <=64 byte CP4D response and exact `action_len + desc_len <= 53`.
- `0x87` parser now supports empty ordinary-key slots: `action_type=0x00`, `action_len=0`.
- `0x87` parser continues to accept shortcut `0x73` and macro `0x74`, and rejects unsupported action types.
- `BleManager.readOrdinaryKeyConfig()` now waits for `0x87` with `throwOnDeviceError=false`, then maps nonzero device statuses to explicit ordinary-key readback errors, especially `0x87 03` fail-closed for oversized keys.
- CP4C connect/reconnect readback no longer fails the whole input domain just because one ordinary key cannot be read. It preserves the successful `0x97` side-switch readback and reports partial ordinary-key readback failure.
- `StudioState.applyOrdinaryKeyReadback()` no longer marks a mode as fully read after only one key. A mode is marked read only after all four ordinary keys for that mode read successfully.
- `DeviceSyncService.matchesReadback()` accepts firmware empty-slot `action_type=0x00` when Windows expected an empty shortcut payload.
- Existing `0x97` side-switch Custom envelope behavior remains unchanged: shortcut/macro action payloads still use `0x73/0x74 + len + payload`, with the 52-byte side-switch budget preserved.

## Machine Checks

- JDK17 Maven compile: `mvn -q -DskipTests compile`, exit `0`.
- Static grep: no `0x98` / `CMD_TASK_LIGHT_MODE` usage in Windows ordinary-key readback path.
- Static grep: `UsbHidTransport.java` contains no `col02` or `mi_00` configuration-channel fallback.
- Static grep: `0x87`, `STATUS_TOO_LARGE`, `ORDINARY_KEY_ACTION_EMPTY`, `0x97`, `SUB_SHORTCUT`, `SUB_MACRO`, and side-switch budget anchors are present.
- `git diff --check`: exit `0`, only CRLF warnings.
- Evidence log: `.ahakey-desktop-harness/evidence/20261007T1125_wd003_cp4d_0x87_windows_checks.log`.

## Delivery To DLA

- This is an implementation submission for review only.
- It is not a formal high-impact fresh review pass, Git candidate, formal build, true-device pass, Owner UAT, release, or installer validation.
- Real USB/BLE integration remains for the next Owner Preview after DLA review and Preview build.
