# WD-002 DLA Review

Status: PASS
Role: DLA
Reviewed at: 2026-10-03T18:26:43+08:00
Harness: AhaKey Windows Harness v1.1.0
Build round: 3
Code fingerprint: `937d716d93f20e7fb13e3b994f834b0b002a65fff424acb48cef0855f5981e41`

## Review Pack

- Pack: `.ahakey-desktop-harness/changes/WD-002/reviews/20261003T102347709569Z-c2970c/PACK.json`
- Actual diff: `.ahakey-desktop-harness/changes/WD-002/reviews/20261003T102347709569Z-c2970c/ACTUAL_DIFF.txt`
- Diff SHA256: `58a73864a6e3c9cb7e7d4cd7ac8f4670b0429eb1c93a1e5002ef44ce53c1193b`
- Submission SHA256: `63dd75975a42c3d1297ef36f3a191d2ce981b961ff767a33042bbf7c889df85c`
- Approval SHA256: `a34f0f05a0daee947b6ebddd45a22762a6316d6c41c2304928c2814fc57aeaed`

Review-pack reports missing original bytes for:

- `src/main/java/com/example/ahakey/app/StudioController.java`
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/view/CanvasPane.java`

This review therefore used the generated pack, current source, `git diff`, and call-chain inspection rather than claiming a byte-for-byte baseline reconstruction.

## Files Reviewed

- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/app/StudioController.java`
- `src/main/java/com/example/ahakey/view/CanvasPane.java`
- Adjacent protocol/readback references in:
  - `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
  - `src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java`
  - `src/main/java/com/example/ahakey/view/TopBar.java`

## Findings

No blocking findings in the DIB build_round 3 fix.

## Decision Notes

The previous DLA blocker is resolved. `BleManager.processNotifyFrame()` now keeps the existing status-cache/UI path for valid `0x00` frames and also calls `enqueueNotifyFrame(data)` before returning. That means a status readback can update `cachedStatus` / `callback.onStatusReceived(status)` and still be observed by the thread waiting for the command response.

`BleManager.queryDeviceStatusSnapshot()` still sends `AhaKeyProtocol.queryDeviceStatus()` and waits for `CMD_QUERY_STATUS`. The wait path now special-cases `CMD_QUERY_STATUS`: it validates the frame with `AhaKeyProtocol.parseDeviceStatus(frame)` and returns the raw frame, instead of interpreting byte 3 through `AhaKeyResponseParser.CommandResponse.status()`. This avoids treating the `0x00` status payload battery byte as a command error code.

`setWorkModeAndVerify()` still sequences the CP4A contract path as `0x92` command response followed by `queryDeviceStatusSnapshot(2000, true)`, then compares the readback mode to the requested target mode. Disconnect during the `0x92` wait uses `waitForReconnect=false`, so that operation fails visibly rather than silently waiting across a lost connection.

The Q7 product semantics remain within the effective WD-002 contract: disconnected mode selection is browse-only; `Edit Configuration` sets `enterEditingAfterConnect` and starts connection; `activateConfigurationEditing()` is only called after an actual connected callback or when already connected/simulated; disconnect/error clears the pending edit flag; save/apply/write paths still guard on connected state or simulation.

Adjacent WD-001 regression surfaces reviewed: `0x95` sleep wait time still uses the same command constant, set/query readback, and parser path; `0x9F` firmware catalog key still sends `queryFirmwareCatalogKey()` and parses through `parseFirmwareCatalogKey()`. The new per-command response queues do not remove those response paths.

## Scope / Coverage Notes

The DIB FIX remains inside WD-002 allowed paths for the submitted review pack. The wider local Git working tree still contains other dirty files from the ongoing WD-002/harness workspace; those are not a Git candidate or delivery artifact yet and must be handled by the later candidate step.

DIB machine checks are recorded as pass for build_round 3: `git diff --check`, JDK 17 `mvn -q -DskipTests compile`, and JDK 17 `mvn -q test`. The mock check remains `not_applicable` because this repository currently has no `src/test` tree and WD-002 allowed_paths did not include adding tests. This is an accepted review limitation for this pass, not Owner UAT or real-device proof.

No real-device test, Owner UAT, runnable build receipt, test packet, installer, Git candidate, or Release Batch is claimed by this review.
