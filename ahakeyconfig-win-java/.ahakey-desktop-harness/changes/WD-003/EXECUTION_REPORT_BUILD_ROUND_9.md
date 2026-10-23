# WD-003 DIB Revalidation Report - build_round 9

## Scope

This DIB round revalidates the existing WD-003 Windows implementation after DLA completed Contract/reference reconcile.

No production Java, protocol semantics, Firmware source, Harness rules, Git state, installer, device write, burn, formal Owner UAT, release, or publication action was changed by this round.

## Reason

The previous DIB submission and implementation receipt were bound to build_round 8 and the previous effective approval SHA. After Contract/reference reconcile, WD-003 moved to revision 8 / build_round 9. DLA needs a fresh DIB implementation identity before doing a new build_round 9 actual diff review.

## Checks Run

Evidence log:

- `.ahakey-desktop-harness/evidence/20261007T1732_wd003_build_round9_revalidate_checks.log`

Checks:

- JDK17 Maven compile with `-DskipTests compile`: exit code 0.
- Static check confirmed no `0x98` ordinary-key readback use in Windows Java sources.
- Static check confirmed `UsbHidTransport.java` has no `mi_00` / `col02` configuration-channel fallback.
- Static anchors present for CP4D / CP4C integration:
  - `CMD_ORDINARY_KEY_READBACK`
  - `parseOrdinaryKeyReadback`
  - `readOrdinaryKeyConfig`
  - `readSideSwitchConfig`
  - `writeSideSwitchConfig`
  - `ORDINARY_KEY_READBACK_FRAME_MAX`

## Non-Coverage

- No real device test was run by DIB.
- No BLE or USB device connection was opened by DIB.
- No installer or release package was built.
- Owner Preview PASS remains preview-only and is not formal Owner UAT.
- High-impact independent fresh review, Git candidate, formal artifact identity, Firmware identity, formal Owner UAT, and release are still not completed.

## Result

DIB revalidation passed for the limited build_round 9 implementation identity refresh. This report is ready to be frozen by `submit` and handed to DLA for actual diff review.
