# WD-003 StudioController Scope Reconcile Reason

Date: 2026-10-05

Role: DLA

## Trigger

DIB preflight passed for WD-003 and DIB inspected the actual Windows call chain before editing production code.

No production Java source was modified.

## Finding

WD-003 Contract already requires:

- connection/reconnection readback for CP4C firmware;
- reading `0x97` side-switch configuration;
- reading all ordinary keys through `0x87`;
- save verification by write/save/readback/compare;
- preserving failed or unverified local drafts instead of unconditional save success.

The required runtime entry points are in `src/main/java/com/example/ahakey/app/StudioController.java`:

- `BleManager.BleCallback.onConnected()` and `onStatusReceived()` are where connection/reconnection status reaches the application orchestration layer.
- `syncAllModes(...)` currently calls `DeviceSyncService.writeSequentially(...)` and then clears dirty state in the completion callback.

Without touching this controller, DIB can add protocol/service/model/view helpers, but cannot wire CP4C readback into the actual connection and save journeys.

## Reconcile Decision

This is not a product semantic change. It is a missing implementation entry point for the already-approved WD-003 Contract.

Add only this production source file to WD-003 `allowed_paths`:

- `src/main/java/com/example/ahakey/app/StudioController.java`

All original WD-003 protocol, UI, legacy fallback, and preservation requirements remain unchanged.

## Boundaries

- Do not reopen Product Grill.
- Do not alter `0x87`, `0x97`, or `0x9F` protocol meaning.
- Do not add unrelated app/controller refactors.
- Do not build, run the app, run device writes, or perform Git writes as part of this reconcile.
