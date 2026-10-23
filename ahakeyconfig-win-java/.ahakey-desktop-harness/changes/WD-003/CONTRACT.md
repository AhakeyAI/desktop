# WD-003 - CP4C input configuration domain readback and side-switch integration

Status: DLA Contract draft. This file is not Owner approval and does not authorize DIB implementation.

## Owner Dispatch And Goal

Owner confirmed a new Windows CHANGE for the CP4C input configuration domain after WD-002 was suspended. The feature scope is four ordinary keys plus the side switch. The goal is to let Windows use firmware readback as the device baseline on CP4C-capable firmware, while preserving legacy behavior on older firmware.

Owner record: `.ahakey-desktop-harness/evidence/20261005T175747_input-domain-change-owner-record.md`.

## Change Classification And Journey

- Journey: `J003` - CP4C input configuration domain integration.
- Classification: `protocol_change`.
- Review policy: `high_impact`.
- Delivery scope: internal integration.
- Device related: yes.
- Real device / Owner UAT required before pass: yes.

This is a protocol-facing Windows change because it introduces ordinary-key readback via `0x87` and changes Windows input-configuration baseline semantics.

## Scope

In scope:

- Four ordinary keys across all four modes.
- Global side-switch configuration.
- Connection/reconnection readback for CP4C firmware.
- Save verification for input configuration.
- Local draft behavior for input configuration.
- User-facing failure feedback and developer-facing logs.
- Legacy firmware fallback.

Out of scope:

- Light configuration.
- OLED/GIF/image configuration.
- Voice configuration.
- Mode switching behavior beyond preserving WD-002 behavior.
- Power configuration.
- Restore Factory.
- CP5.
- Full Host Protocol.
- Firmware upgrade/recovery.
- HID descriptor changes.
- Release batch / EXE packaging.

## Firmware Capability Gate

Windows must use `0x9F` catalog key gating.

CP4C-capable firmware enables this feature only when the catalog key is in the CP4C allowlist. The known CP4C catalog key discussed for this feature is:

- `x1-c582-hw1-p1-1.0.0-r001`

If `0x9F` is missing, fails, or returns a catalog key outside the CP4C allowlist, Windows must keep legacy behavior.

## Protocol Contract

### Side Switch

`0x97` continues to be side-switch configuration only.

Expected side-switch behavior:

- Read current side-switch configuration from firmware.
- Write side-switch configuration when changed.
- Verify saved side-switch configuration by reading `0x97` after write.

`0x97` Custom action payload format:

- Custom shortcut payload must be stored on the wire as `0x73 len keycodes...`.
- Custom macro payload must be stored on the wire as `0x74 len macroBytes...`.
- Windows must not send bare HID keycodes as a `0x97` Custom action payload.
- A single key shortcut is encoded as a shortcut action with `len=1`, for example Backspace is `73 01 2A`.
- A combination shortcut is encoded as a shortcut action with multiple keycodes, for example Ctrl+V is `73 02 E0 19`.
- Current CP4C firmware returns `0x97` side-switch readback in one 64-byte USB report. The current side-switch action budget is 52 bytes total action payload across both positions.
- This stage supports single-key shortcuts, combination shortcuts, and short macros. Oversized macros are not fully solved in this stage; Windows must avoid silent truncation and should fail, disable save, or show a clear limit message before claiming success.

Side-switch binding labels:

- `0` = `自动批准`
- `1` = `手动批准`
- `2` = `无动作`
- `3` = Custom action, represented in UI as `自定义快捷键` or `自定义宏` according to payload type.

Physical side-switch labels:

- `0` = `上拨`
- `1` = `下拨`
- `2` = `中间 / 未知`

### Ordinary Key Readback

Ordinary-key configuration readback uses a new narrow readback-only command candidate: `0x87`.

`0x98` must not be used for ordinary-key readback because firmware already uses it as `AHAKEY_CMD_TASK_LIGHT_MODE`.

Request:

```text
AA BB 87 mode key_index CC DD
```

Success response:

```text
AA BB 87 00 mode key_index action_type action_len action_payload desc_len desc_payload CC DD
```

Error responses:

```text
AA BB 87 01 CC DD   invalid payload
AA BB 87 02 CC DD   mode/key_index out of range or unsupported stored action
AA BB 87 03 CC DD   stored action/description too large for one 64-byte response
```

Status:

- `0` = OK
- `1` = invalid payload
- `2` = mode/key_index out of range
- `3` = stored action/description too large for one single-report readback

Boundaries:

- Read-only.
- One `mode + key_index` per request.
- Does not write ordinary-key configuration.
- Does not open full Host Protocol.
- A successful `0x87` response must fit in one 64-byte USB/BLE configuration frame and include the `CC DD` tail.
- `action_type` may be empty `0x00`, shortcut `0x73`, or macro `0x74`.
- Empty/unconfigured slots return `action_type=0x00`, `action_len=0`, and no action payload.
- Shortcut/macro slots return the real stored `action_len`; firmware must not return fixed 100-byte action padding.
- `desc_len` is deterministic and trimmed; firmware must not return fixed 20-byte description padding.
- With this frame shape, `action_len + desc_len <= 53` for success.
- If the complete action plus description cannot fit, firmware returns an error and must not truncate. Windows must fail closed for that key and must not guess an editable value.

Ordinary-key writes continue to use the existing Windows/firmware path:

- Existing ordinary-key write command: `0x73`.
- Existing save/persist command: `0x04`.

## Readback Strategy

On CP4C-capable firmware, connection and reconnection must start input-configuration readback.

Readback order:

1. Read `0x97` side-switch configuration.
2. Read the current mode's four ordinary keys first using `0x87`, so the current canvas can become accurate quickly.
3. Continue in the background and read the remaining modes' ordinary keys.
4. Full ordinary-key readback is 16 requests: 4 modes x 4 keys.

UI should not block the whole application while background pre-read is running. If the user switches to a mode already read, Windows displays the device baseline immediately. If the user switches to a mode whose background read is not yet complete, Windows may show a lightweight loading/reading state for that mode.

The completed `0x97` and `0x87` readbacks form the CP4C device baseline.

## Save Success Definition

On CP4C-capable firmware, input configuration save success requires write/save/readback verification.

For ordinary keys:

1. Write changed ordinary-key configs through existing `0x73`.
2. Persist through existing `0x04` as applicable.
3. Read back affected keys using `0x87`.
4. Compare readback with the user's saved draft.
5. Only matching readback can be reported as saved.

For side switch:

1. Write changed side-switch config using `0x97`.
2. Read back `0x97`.
3. Compare readback with the user's saved draft.
4. Only matching readback can be reported as saved.

If any affected ordinary key or side-switch position fails write/readback/compare, that part is not saved successfully.

## Local Draft And Baseline Rules

Device baseline:

- On CP4C-capable firmware, device baseline comes from `0x97` and `0x87` readback.
- On legacy firmware, Windows keeps legacy local-state behavior.

Local draft:

- User edits are local drafts until Save.
- Local drafts may be preserved by Windows between app sessions.
- On save, only items written and verified by readback are cleared from local draft.
- Failed or unverified items remain in local draft and must be visible as not confirmed.

Unsaved draft recovery remains an input-domain behavior for this CHANGE. Broader unified draft behavior for light/OLED/GIF/voice/power is out of scope.

## UI Semantics

### CP4C Firmware

Ordinary keys:

- Use existing ordinary-key Shortcut/Macro editing capability.
- Populate visible key config from device baseline once readback is available.
- Show local draft edits separately from confirmed device baseline.

Side switch:

- Entry is on the current keyboard canvas side-switch part.
- Clicking the side-switch part shows side-switch configuration in the right Inspector.
- The Inspector displays up/down position configuration.
- The side-switch Custom Shortcut editor must allow the same single-key and modifier-combination shortcut semantics as ordinary key shortcut editing where practical.
- The side-switch Custom Macro editor may support short macros only. Oversized macros may be blocked or clearly reported instead of being saved.
- First version does not allow mixing Custom with Factory Auto/Manual.
- Allowed AI policy style combinations include Auto/Manual, Auto/Disabled, Manual/Disabled, Disabled/Disabled, and reversed equivalents.
- Allowed custom/action combinations include Custom/Disabled, Disabled/Custom, and Custom/Custom.
- Disallowed combinations include Custom+Auto, Auto+Custom, Custom+Manual, Manual+Custom.
- Switching a Custom side back to Factory Auto/Manual should auto-complement the other side: up Auto => down Manual, up Manual => down Auto, down Auto => up Manual, down Manual => up Auto. Disabled does not force complement.
- Save/Apply is unified with existing app Save/Apply; no separate side-switch Apply.

### Legacy Firmware

If firmware is not CP4C-capable:

- Ordinary keys continue to use local Windows configuration display and existing `0x73`/`0x04` save behavior.
- Windows must not use `0x87`.
- Side-switch Inspector displays physical position and traditional behavior:
  - `上拨=自动批准`
  - `下拨=手动批准`
- Side-switch editable `0x97` form is hidden.
- No error is shown merely because firmware is legacy.

## Failure Handling And Logs

For CP4C-capable firmware, failures in `0x87` or `0x97` readback, write, save, or compare must:

- Show a lightweight user notification.
- Show failure state in the relevant Inspector area.
- Preserve failed/unverified local draft parts.
- Avoid claiming save success for failed parts.
- Log structured developer evidence including:
  - `catalogKey`
  - `cmd`
  - `mode`
  - `keyIndex`
  - `phase`
  - `reason`

If CP4C firmware is detected but `0x97` or `0x87` fails, Windows must not silently fall back to unsafe success semantics for that CP4C feature area.

## Proposed Implementation Boundaries

Likely Windows areas:

- `StudioController.java`: connection/reconnection readback orchestration and save completion handling for readback verification.
- `AhaKeyProtocol.java`: command builders/parsers for `0x87` and `0x97`.
- `AhaKeyResponseParser.java`: parse `0x87`/`0x97` responses.
- `BleManager.java`: readback methods and transaction handling.
- `UsbHidTransport.java`: WD-003 preview defect repair only; configuration commands must select the USB vendor/config interface and must not treat the `mi_00&col02` keyboard/consumer collection as the configuration channel.
- `DeviceSyncService.java`: input save orchestration and readback verification.
- `StudioState.java`: input device baseline, local draft, dirty/confirmed state.
- `InspectorPane.java`: side-switch Inspector and failure state.
- `CanvasController.java`: side-switch canvas selection entry if needed.
- UI text resources if labels need localization.

Allowed paths do not authorize whole-file rewrites or unrelated UI refactors. `StudioController.java` is included only for the existing WD-003 connection/reconnection readback and save/readback confirmation journeys.

## Preservation Requirements

Must preserve:

- WD-002 mode-switch behavior.
- Existing ordinary-key Shortcut/Macro editing capability.
- Existing ordinary-key write behavior on legacy firmware.
- Existing BLE/USB command pathways unless directly needed for readback.
- Existing light, OLED/GIF, voice, mode, and power behavior.

## Acceptance Outline

Machine checks before DLA review:

- Project compiles.
- Focused unit/helper tests if added.
- No use of `0x98` for ordinary-key readback.
- Legacy firmware path does not call `0x87`/editable `0x97`.

Owner Preview / UAT must cover:

- CP4C firmware connects and performs background full input readback.
- Current mode appears quickly; other modes are ready after background read.
- Editing ordinary keys saves only after `0x87` readback matches.
- Editing side switch saves only after `0x97` readback matches.
- A readback mismatch/failure shows lightweight UI notice, Inspector failure state, and logs enough evidence.
- Legacy firmware keeps old ordinary-key and side-switch behavior.

Completion of this task only means WD-003 internal integration has passed its approved scope. It does not imply full product release, EXE release, firmware release, or release batch completion.

## Approval Method

Owner must explicitly approve this Contract before DIB implementation. DLA will then record Harness approval and route to DIB. Without explicit approval, this remains a draft.
