# Windows software stabilization review summary

Date: 2026-08-26  
Scope: `desktop/ahakeyconfig-win-java` and directly related Windows release scripts/docs  
Authoritative status: `desktop/docs/windows-stabilization-plan.md`

## Outcome

The P0 Java/build baseline is restored and locally verified. The full test suite and package build pass, PowerShell scripts parse, and the final local JAR contains every required runtime class and `firmware-capabilities.properties`.

The formal release overlay remains blocked because this machine has no installed release baseline at `C:\Program Files\AhaKeyStudio\app`. `build-installer.ps1 -PrepareOnly` likewise reaches the baseline-asset gate and stops because `C:\Program Files\AhaKeyStudio\AhaKeyStudio.ico` is absent. Per the phase gate, remaining P1/P2 work was not continued after that external P0 blocker. No firmware source was modified.

## P0 changes

- Restored Java compilation (`java.util.List`) and aligned WorkMode tests with the frozen offline/edit and online/device transaction semantics.
- Added `ManualApprovalGate` and its tests to source control scope, release-overlay compilation/allowlist, and release-artifact checks.
- Hardened Claude/Cursor/Codex/Kimi Hook responses to a fixed canonical JSON schema. Generated clients fully parse and validate exact fields/types/values; malformed, truncated, extra-field, wrong-event and wrong-platform responses fail closed.
- Kept `fresh && connected && AUTO` as the only automatic approval path.
- Bound ordinary command responses to the transport kind, epoch and receiver generation captured by the send operation; a session change invalidates the response wait.
- Preserved dirty changes made after a save starts by clearing only the captured dirty-revision snapshot.
- Kept offline Mode selection local, established pending Mode only after a successful send, and rolled failed sends back to the last confirmed device Mode.
- Unified the software/firmware contract: capability query `0x9D`, protocol `3.2`, device model id `1` / `AhaKey-X1`, required capability bits `0x7FF`, expected bundled firmware `1.4.7`, minimum stabilized firmware `1.4.7`, and minimum GIF firmware `1.4.3`.
- Configuration writes now require the complete stabilized contract; firmware version alone cannot enable dependent behavior.
- Release input validation now requires an exact HEX name, structurally valid Intel HEX, and provenance fields for firmware version, device model, protocol, capability mask, source commit, build command and UTC build timestamp. The software validates but does not fabricate firmware provenance.
- Formal release generation requires a valid Authenticode signature before declaring a release candidate.

## Automated verification

```text
mvn clean test
Tests run: 148, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS

mvn clean package
Tests run: 148, Failures: 0, Errors: 0, Skipped: 0
RELEASE_ARTIFACT_CONTENTS=OK
BUILD SUCCESS

PowerShell parser (*.ps1)
POWERSHELL_PARSE=OK scripts=9

Test-ReleaseArtifactContents.ps1
RELEASE_ARTIFACT_CONTENTS=OK

git diff --check
exit 0 (line-ending conversion warnings only)
```

The local JAR was explicitly checked for:

- `WorkModeSynchronizer`
- `ManualApprovalGate`
- `ApprovalService`, `ApprovalSnapshot`, `ApprovalState`
- `PhysicalStatusFreshness`
- latest `BleManager`, `UsbHidTransport`, `KimiAhaKeyBridge`
- `GifUploadRules`, `LightOperationCoordinator`
- lifecycle/firmware validation runtime classes
- `firmware-capabilities.properties`

## Blocked validation

```text
preview-part3-release-overlay.ps1
BLOCKED: C:\Program Files\AhaKeyStudio\app does not exist

build-installer.ps1 -AppVersion 1.5.3 -PrepareOnly
BLOCKED: C:\Program Files\AhaKeyStudio\AhaKeyStudio.ico is missing
```

These are external release-baseline prerequisites, not Java test failures. `OVERLAY_VALIDATION=OK` was not produced and is not claimed.

## Still pending

- Formal overlay and installer validation using the actual installed release baseline.
- Formal 1.4.7 HEX plus matching firmware-generated provenance and signed final EXE.
- USB/BLE hardware tests, rapid reconnect/session-switch stress, and approval matrix.
- GIF/OLED upload/readback/timing tests on physical flash.
- Voice hook/recording/ONNX tests on Windows hardware.
- Remaining P1 task-mode/UI, approval-dialog serialization, cross-session integration, GIF/OLED UX, updater/HEX-download work.
- P2 legacy-path cleanup and historical initial-spec archival.

## Git state and commits

No commit was created in this review run. The checkout already contained a large mixed staged/unstaged stabilization set, including paths with both index and working-tree edits. Creating the requested category commits without an authoritative pre-run index snapshot would risk attributing or splitting existing user work incorrectly. No reset, checkout, merge, rebase or push was performed.

Latest history at review time:

```text
6b8426a feat(mac): complete USB wired keyboard integration
5badcb4 feat(windows): integrate AhaKey Studio 1.5.3 device workflows
090f5aa feat(hook): wire 4 hook install/uninstall commands + device-info modal UI
c1114ff Merge remote-tracking branch 'origin/main-anpx' into main-anpx
7134628 提交ubuntu ble
fc7f6c5 Merge remote-tracking branch 'origin/main-anpx' into main-anpx
b8d3992 feat(ui): 2A selectedPart routing + 7-hotspot canvas + 5 InspectorPane groups
045008c fix(ui): two UI bugs - mode switch reset + knob state stale
5351374 refactor(ui): remove BLE device picker, connect directly to v2 bridge
62940e0 refactor(ble): replace btleplug/winrt with TCP client to BLE_tcp_bridge_v2
```

Use `git status --short` for the authoritative live status; it intentionally remains dirty so existing user staging is preserved.
