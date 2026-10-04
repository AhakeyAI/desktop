# WD-002 Contract Confirmation Draft

Status: OWNER_CONFIRMED_FOR_IMPLEMENT_HANDOFF
Role: DLA
Harness: AhaKey Windows Harness v1.0.1
Created: 2026-10-03T00:00:00+08:00

## Change

ID: `WD-002`

Title: `WS2 CP4A Mode Sync + Display Status`

Current formal state: Owner confirmed. Intended next stage is IMPLEMENT / DIB, subject to legal Harness routing.

Owner confirmation source:

- `.ahakey-desktop-harness/evidence/owner-confirmation-WD-002-contract-20261003.md`

## Firmware Binding

Read-only Firmware root:

`C:\Users\20825\Desktop\vibe-code`

Formal Firmware gate:

`.ahakey-harness/evidence/checkpoints/X1-INPUT-CONTROL/CP4A/20261002T084039/gate-receipt.json`

Gate SHA256:

`71e61a42b8771a7318467b98bfbb36804ef0b2f3f5c18875c2d9110f7e89b0ab`

Candidate commit:

`bd1ea87e10939fd6f738b599a4c66ba3264acf70`

HEX:

`.ahakey-harness/evidence/builds/ws2-cp4a-mode-sync-display-status/HID_Keyboard_582m_vibe_coding.hex`

HEX SHA256:

`8e11f2b526e9239a67c5199aff88ebbed875bdc9cb3df0eb5592979e5f021867`

Firmware feature:

`Mode sync and display status foundation`

Firmware evidence already indexed by:

- `.ahakey-desktop-harness/v1/planned-changes/WD-002-firmware-evidence.json`
- `.ahakey-desktop-harness/v1/planned-changes/WD-002-intake-20261002.json`

## Journey Binding

Journey: CP4A mode sync and display status.

User behavior:

- User connects keyboard over USB or BLE.
- Windows reads keyboard-authoritative current mode through status readback.
- If the user changes mode from the keyboard Power key, Windows follows the keyboard state after polling/query.
- If the user changes mode from Windows, Windows sends the existing mode-set command and accepts success only after firmware acknowledgement plus matching readback.
- If disconnected, Windows allows browsing/editing local drafts but blocks Save/Apply and protocol writes.
- On reconnect, Windows reads keyboard truth first and preserves unapplied local drafts as drafts.

Firmware modules:

- `MOD-003` Mode Toggle Sync.
- `MOD-004` Configuration Schema / local drafts boundary.
- `MOD-006` Display / status summary ownership.
- `MOD-013` USB Device Transport.
- `MOD-014` BLE Transport.

## Protocol

No new Firmware opcode is introduced.

- Existing `0x00`: status readback for keyboard-authoritative current mode and status fields.
- Existing `0x92`: Desktop-to-keyboard mode set with one valid target mode byte.

Success rule:

- Desktop mode set succeeds only after `0x92 OK` and follow-up `0x00` readback equals requested mode.

Failure rule:

- Non-OK response, timeout, disconnect or readback mismatch returns visible Windows state to keyboard-authoritative mode and shows recoverable failure.

Transport policy:

- USB and BLE must expose equivalent behavior for this journey.
- Active Desktop control channel owns mode-set attempts while connected.

## Windows Scope

Allowed after Owner confirmation:

- Parse existing `0x00` current-mode/status fields.
- Build/send existing `0x92` mode-set request.
- Sequence Desktop mode change as `0x92 OK` plus confirming `0x00` readback.
- Handle connected, disconnected, timeout, readback mismatch, reconnect and stale response cases.
- Keep visible mode aligned with keyboard-originated changes.
- Disable Save/Apply and any `0x92` apply path while disconnected.
- Preserve unapplied local drafts as drafts; do not replay stale drafts on reconnect.
- Add readable status summary for primary key labels, battery percent, charging state and connection/status label.
- Preserve existing Mode1/2/3 visuals.
- Keep Mode4 empty/placeholder unless a later scope authorizes more.
- Add focused offline tests for parser, service sequencing, USB/BLE mock parity, stale response isolation, offline draft boundary and WD-001 regression surfaces.

## Explicitly Out Of Scope

- Continuing WD-001 recovery.
- Implementing WD-R001.
- Rewriting old WD-001 tests, Review, Owner Results, build, candidate or Firmware gate.
- Modifying Firmware or eternal workspaces.
- Creating new Firmware command numbers.
- Voice onboarding.
- Side-switch customization.
- Restore factory settings.
- Flashing/recovery/release catalog behavior.
- Default image/GIF resource changes.
- Release Batch, installer EXE, publication or Git write.
- Claiming Owner real-device PASS before a future WD-002 test packet and Owner feedback.

## Classification

- `scope_expansion`
- `architecture_change`
- `protocol_change`

Primary classification is not a simple bug fix. This is a new Firmware-driven Windows phase while preserving relevant WD-001 regression behavior.

Review policy: `high_impact`

Reason:

- Protocol command sequencing and readback confirmation affect device state.
- USB/BLE parity and active control-channel ownership affect session behavior.
- Offline draft behavior prevents accidental writes or stale replay.
- WD-001 nearby protocol/session surfaces must not regress.

## Confirmation Required

Owner confirmation has been received before DIB implementation.

Copyable confirmation:

`确认 WD-002 Contract：按 CP4A Mode Sync + Display Status 范围进入 IMPLEMENT / DIB；不继续 WD-001 recovery，不执行 WD-R001，不改 Firmware，不创建 Release Batch。`
