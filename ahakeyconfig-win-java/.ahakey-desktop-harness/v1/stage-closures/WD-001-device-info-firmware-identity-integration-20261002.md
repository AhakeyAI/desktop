# Increment Closure: Device Info / Firmware Identity Integration

Created at: 2026-10-02T19:12:37+08:00
Role: DLA
Harness: 1.0.0
Workflow: V1_CHANGE_IMPLEMENT_VERIFY_RELEASE
Active change remains: WD-001

## Status

CLOSED_FOR_SCOPE

NOT_ACCEPTED_AS_PRODUCT_PASS

This is an increment boundary record only. It does not close WD-001, does not
approve the current worktree, does not validate the current JAR, and does not
transfer historical Owner PASS results to the current source or artifact.

## 1. Original Stage Goal

The stage under closure was Device Info / Firmware Identity Integration. Its
observed scope was:

- display firmware main/sub identity already available from device status;
- read the firmware catalog key through `0x9F`;
- add a Device Info refresh affordance;
- keep old-firmware fallback behavior soft, with UNKNOWN or failure display
  rather than treating missing `0x9F` as device-wide unsupported state;
- compose the new identity information with the existing Device Info area that
  also contains the WD-001 `0x95` sleep wait time entry.

This stage was broader than the original approved WD-001 contract. The original
WD-001 contract and DLA review covered only the CP3A `0x95` sleep wait time
integration in the More / Device Info card. The original review explicitly did
not cover `0x9F`, firmware catalog identity, Device Info refresh, shared response
ownership changes, or new `StudioController` / `DeviceStatus` / `pom.xml`
production changes.

## 2. Actually Implemented In Current Worktree

Current tracked source differs from the recorded WD-001 candidate at
`666494c358fd5373b27b6213e9f4a35a424dd2c6`. The observed diff is 10 tracked
files with approximately 469 insertions and 77 deletions:

- `AGENTS.md`
- `pom.xml`
- `src/main/java/com/example/ahakey/app/StudioController.java`
- `src/main/java/com/example/ahakey/model/DeviceStatus.java`
- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
- `src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java`
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/view/TopBar.java`
- `src/main/resources/messages_en.properties`
- `src/main/resources/messages_zh.properties`

Observed implementation content includes:

- `AhaKeyProtocol.CMD_FIRMWARE_CATALOG_KEY` and `queryFirmwareCatalogKey()`.
- `AhaKeyResponseParser.parseFirmwareCatalogKey(...)`.
- `BleManager.readFirmwareCatalogKey()`, cached firmware catalog key, firmware
  main/sub copying, command-keyed pending response queues, and BLE notify frame
  reassembly.
- `StudioController` paths for connection-time catalog key read, Device Info
  refresh, clearing firmware identity, and status snapshot refresh.
- `DeviceStatus` firmware main/sub/catalog key fields and display-version
  fallback.
- `TopBar` Device Info firmware display, refresh button, and continued `0x95`
  sleep wait time control.
- `pom.xml` manifest entry support for implementation metadata.

The current runtime observation index reports the current JAR at
`target/ahakey-studio-1.0.0.jar` with SHA256
`b9723cdc1f5b5f7eccb4f0a3ff14b87a7668c9cf7a6c307c377c404e8a68be43`, while the
legacy WD-001 build receipt/brief used SHA256
`c16f5bad0f518fb8fea00f7dee7f97caaf7ac6dc3865092442a2bee260217886`.

## 3. Product Behaviors Confirmed For Retention

These behaviors are retained as the desired product direction for the recovery
scope, subject to proper review and test:

- `0x95` remains the sleep wait time command with legal values
  `0/30/60/120`; Windows must not send `0x04 save_config` for this item.
- `0x9F` is limited to existing firmware catalog key identity reading. It is not
  a capability framework, update gate, release catalog, or broad compatibility
  mechanism.
- `0x9F` failure, timeout, or old-firmware absence must not block `0x95` read,
  save, or save-readback behavior.
- firmware main/sub fallback can still provide a useful display when catalog key
  is absent or unreadable.
- Device Info remains the UI home for these fields; no new full settings page or
  product-wide UI redesign is implied.
- T07 illegal-value testing remains `not_executed` / Owner accepted
  post-decision; it is not silently converted to PASS.

## 4. Not Yet Complete

The following are not complete for the current source or current JAR:

- no DLA actual-diff review PASS for the current 10-file worktree;
- no high-impact review bound to the current response ownership / BLE reassembly
  / `0x9F` catalog key behavior;
- no Git candidate binding for the current worktree;
- no fresh build receipt for the current source;
- no artifact identity proving the current source produced a validated test
  package;
- no Owner UAT for the current `b9723...` JAR;
- no installer / Release Batch validation;
- no helper-supported recovery addendum record that legally associates this
  recovery work with WD-001 while preserving old WD-001 history and two
  cumulative diff segments.

## 5. Moved Into Current WD-001 Recovery

The following problems are moved into the current WD-001 Recovery scope:

- response ownership for command replies shared across USB/BLE;
- BLE notify frame splitting and multi-frame reassembly;
- connection session / command request / device session / dialog refresh session
  isolation;
- disconnect and device switch handling for `0x95` and `0x9F` reads;
- stale UI updates after refresh, timeout, dialog close, or reconnect;
- narrowing Device Info refresh semantics so the refresh button does not
  silently become a broad status snapshot plus forced `0x95` refresh;
- conservative UI wording for result-unknown states, especially when `0x95 set`
  may have been sent but readback was not confirmed.

## 6. Evidence And Limits

Evidence used in this boundary record:

- `.ahakey-desktop-harness/changes/WD-001/CONTRACT.md`
- `.ahakey-desktop-harness/changes/WD-001/REVIEW.json`
- `.ahakey-desktop-harness/changes/WD-001/OWNER_RESULTS.json`
- `.ahakey-desktop-harness/v1/artifact_identity.json`
- `.ahakey-desktop-harness/v1/evidence_state.json`
- current `git diff --stat`, `git diff --name-only`, `desktop.py status`, and
  `desktop.py guard-status --id WD-001`
- current source inspection for `0x9F`, Device Info refresh, response queues,
  firmware identity and `0x95` composition

External recovery review files under
`C:\Users\20825\Desktop\AhaKey-Harness-Recovery-Review\20261002T043335Z` were
referenced by the Owner prompt but were not present on disk during this run.
This record therefore does not claim to re-read those bytes in this pass.

## 7. Boundary Decision

The Device Info / Firmware Identity Integration stage is closed for scope
clarity only:

- status: `CLOSED_FOR_SCOPE`;
- acceptance: `NOT_ACCEPTED_AS_PRODUCT_PASS`;
- active implementation remains `WD-001 Recovery`;
- next implementation actor remains blocked until the recovery addendum can be
  legally registered and Owner-authorized;
- no DIB work, build, Git candidate, product test, or release is authorized by
  this closure.

