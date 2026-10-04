# WD-R001 Recovery Change Contract

Timestamp: 2026-10-03T01:49:12Z
Actor: DLA
Harness: 1.0.1
Workflow: V1_CHANGE_IMPLEMENT_VERIFY_RELEASE
Change ID: WD-R001
Title: Windows Device Info / Session Stability Recovery
Phase: CHANGE
Status: ABANDONED_BY_OWNER / NO_IMPLEMENTATION_REQUIRED

## Owner Disposition 2026-10-03

Owner explicitly decided not to execute this recovery implementation.

- `ABANDONED_BY_OWNER`
- `NO_IMPLEMENTATION_REQUIRED`
- `SUPERSEDED_BY_OWNER_ACCEPTANCE`

Existing WD-R001 Contract / Approval records are preserved as archive, but WD-R001 does not enter IMPLEMENT, is not handed to DIB, and no Harness change will be made to support WD-R001 activation.

Owner disposition source:

- `.ahakey-desktop-harness/evidence/owner-disposition-WD-001-WD-R001-WD-002-20261003.md`

## Purpose

WD-R001 is the independent Recovery Change identity for the already Owner-approved recovery scope covering:

- response ownership;
- BLE notify reassembly;
- device/request/dialog session lifecycle;
- timeout and stale handling;
- Device Info / Firmware Identity stability recovery.

This record corrects task identity and execution ownership only. It does not reopen or change the product scope already approved by Owner.

## Identity Boundaries

WD-001 remains the historical CP3A sleep wait time task. Its original Contract, Review, candidate, build, Firmware evidence, Owner feedback and historical PASS context are preserved. They are not deleted, rewritten, redefined, or transferred to the current source or any current artifact.

The Device Info / Firmware Identity stage remains closed for scope and not accepted as Product PASS:

- `.ahakey-desktop-harness/v1/stage-closures/WD-001-device-info-firmware-identity-integration-20261002.md`

WD-R001 is related to WD-001 but is the implementation identity for the recovery work listed above.

## Approved Scope Source

WD-R001 inherits its approved recovery scope from the Owner-confirmed Contract:

- `.ahakey-desktop-harness/changes/WD-001/recovery/RECOVERY_CONTRACT_20261003T011312Z.md`
- `.ahakey-desktop-harness/changes/WD-001/recovery/RECOVERY_CONTRACT_20261003T011312Z.json`

Owner confirmation source:

- `.ahakey-desktop-harness/changes/WD-001/recovery/OWNER_CONFIRMATION_RECOVERY_CONTRACT_20261003T012836Z.md`
- `.ahakey-desktop-harness/changes/WD-001/recovery/OWNER_CONFIRMATION_RECOVERY_CONTRACT_20261003T012836Z.json`

The old confirmation sentence named WD-001 as the active implementation, but Owner subsequently corrected the task identity. This WD-R001 record preserves the same approved product scope and changes only the recovery execution identity.

## Classification And Review Policy

Classification:

- `bug_fix`
- `scope_expansion`
- `architecture_change`
- `protocol_change`

High impact: yes.

Reason: response ownership, BLE notify reassembly, request/session/device/dialog lifecycle, timeout/stale handling, and bounded `0x9F` firmware identity parsing affect shared protocol behavior.

After DIB submit, DLA must perform actual cumulative diff review and high-impact review under WD-R001. Historical WD-001 review/UAT evidence may be cited only as historical context.

## Allowed Scope

DIB may converge only:

- original `0x95` CP3A sleep wait time behavior preservation;
- bounded Device Info / Firmware Identity behavior from the closed stage;
- `0x9F` firmware catalog key identity read as soft fallback;
- response ownership;
- BLE notify frame reassembly;
- device/request/dialog session lifecycle;
- disconnect/reconnect/device-switch/dialog-close/manual-refresh handling;
- timeout and stale background result suppression.

Allowed paths:

- `pom.xml`
- `src/main/java/com/example/ahakey/app/StudioController.java`
- `src/main/java/com/example/ahakey/model/DeviceStatus.java`
- `src/main/java/com/example/ahakey/protocol/AhaKeyProtocol.java`
- `src/main/java/com/example/ahakey/protocol/AhaKeyResponseParser.java`
- `src/main/java/com/example/ahakey/service/BleManager.java`
- `src/main/java/com/example/ahakey/view/TopBar.java`
- `src/main/resources/messages_en.properties`
- `src/main/resources/messages_zh.properties`

Governance records such as `AGENTS.md` are outside WD-R001 production allowed paths.

## Forbidden Scope

DIB must not:

- activate or implement WD-002;
- add CP4A Mode Sync / Display Status behavior;
- modify Firmware;
- rebuild old Firmware HEX;
- rewrite old WD-001 Contract, Review, Owner Results, gate receipts, or UAT evidence;
- transfer historical PASS to current source or artifact;
- broaden `0x9F` into capability discovery, release catalog, update gate, or compatibility matrix;
- add a new settings page or broad UI redesign;
- add new dependencies unless DLA/Owner reopens CHANGE;
- build/package/create JAR/EXE in this implement handoff unless separately authorized later;
- run app/device/driver/flash/install tests;
- perform Git writes.

## Lifecycle Ownership

All future implementation, review, candidate, build and Owner UAT for this recovery belong to WD-R001.

WD-001 is not the active implementation identity for this recovery. WD-002 remains PLANNED / CHANGE only and inactive.

## Next Legal Stage

Next legal stage after this identity correction:

- `IMPLEMENT / DIB`
- Change: `WD-R001`

This record does not hand off to DIB by itself and does not authorize build, package, Git write, Firmware modification, or Owner real-device testing.
