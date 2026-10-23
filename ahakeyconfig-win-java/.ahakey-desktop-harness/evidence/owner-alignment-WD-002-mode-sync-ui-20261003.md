# WD-002 Owner Alignment - Mode Sync UI / Interaction

Status: OWNER_ALIGNED_FOR_DIB_HANDOFF_WITH_Q7_PATCH
Role: DLA
Harness: AhaKey Windows Harness v1.0.1
Date: 2026-10-03

Updated: 2026-10-03 - Q7 offline edit semantics corrected by Owner during DIB implementation.

## Scope

Change: WD-002 - WS2 CP4A Mode Sync + Display Status

This record captures Owner-confirmed Windows Desktop product/UI/interaction decisions for CP4A after DLA reviewed the existing Windows Mode page, UI flow, selectedMode/status logic, and Firmware CP4A contract.

This record does not modify Java, Firmware, eternal, Git, build artifacts, or test status.

## Confirmed Decisions

### Q1 - Mode picker semantics

Confirmed: connected-state Mode picker is the keyboard current-mode controller.

- When connected, clicking a Mode sends `0x92`.
- Success requires `0x92 OK` plus matching `0x00` readback.
- Keyboard Power-key mode changes make Desktop follow the keyboard-authoritative current mode.
- Offline Mode picker use is local browse only.
- Offline clicks do not send `0x92` and are not replayed after reconnect.
- On reconnect, Desktop first returns to keyboard-authoritative current mode while preserving local drafts.

### Q2 - Keyboard Power key interrupts local editing

Confirmed: if the keyboard Power key changes the real current mode while Desktop has unsaved drafts open, Desktop immediately follows the keyboard current mode.

Required user-visible提示:

`键盘已切到 Mode 2，Mode 1 的未保存草稿已保留`

The exact mode names/numbers should reflect the real previous draft mode and the new keyboard readback mode.

### Q3 - Desktop mode set failure / rollback

Confirmed: if Desktop mode switching fails, Desktop must return to the keyboard-authoritative mode.

Failure cases include:

- `0x92` non-OK response
- `0x92` timeout
- disconnect during set/confirm
- follow-up `0x00` readback mismatch

Required behavior:

- Do not leave UI on the user-clicked target mode if confirmation failed.
- Roll back to the last confirmed/readback keyboard mode.
- Show a recoverable failure message such as:

`未切换到 Mode 2，键盘仍在 Mode 1，请重试`

If disconnected:

`连接中断，键盘模式未确认`

After reconnect, Desktop must read `0x00` first and restore the keyboard-authoritative mode.

### Q4 - Windows-side display status summary

Confirmed: do not add a new compact Mode status summary panel in the Windows Mode area.

Desktop CP4A UI should stay minimal:

- Use the existing Mode picker.
- Use the existing Canvas preview.
- Use existing StatusBar / `syncStatus` style messaging for switching, failure, and draft-preserved messages.
- Do not replicate the keyboard small-screen four-key summary in Windows.

### Q5 - Mode4 behavior

Confirmed: Mode4 is legal and selectable.

- Desktop may use `0x92` to switch the keyboard to Mode4.
- Mode4 remains placeholder / unconfigured in UI.
- Do not auto-fill default image/GIF resources.
- Do not auto-fill new default actions.
- Use the same `0x92 OK` plus `0x00` readback confirmation flow.
- Canvas may show the current placeholder configuration such as `N/A` / `Backspace`.

### Q6 - Mode switching vs configuration save

Confirmed: Desktop Mode switching must not save configuration drafts.

- `0x92` changes only the current mode.
- It must not trigger `saveConfig`.
- It must not write key bindings, descriptions, macros, OLED, or light config.
- It must not upload OLED assets.
- Existing Save/Upload actions remain the only device-write paths for drafts/configuration.

### Q7 - Offline browsing / edit boundary

Confirmed: offline state is browse-only for keyboard configuration. Editing configuration means editing the keyboard configuration, so Desktop must not enter configuration edit state while disconnected.

When disconnected:

- Users may browse local drafts / existing local view.
- Users may not enter configuration edit state.
- Clicking Edit Configuration should first try to connect the keyboard.
- If connection does not succeed, Desktop must remain out of edit state and show a recoverable connection-required message.
- Local draft changes are not started offline by this entry point.
- Device-write actions must be disabled rather than silently behaving as local-only save.
- This includes Save/Apply, `0x92` mode switching, OLED upload, light test, and light config save.
- UI should communicate through disabled state, tooltip, or StatusBar/syncStatus:

`连接键盘后可保存/应用`

Existing local drafts remain preserved as computer-side drafts, but offline mode is not an editing surface for keyboard configuration.

## DIB Implementation Meaning

DIB may proceed only within WD-002 allowed paths and must preserve the Firmware CP4A contract:

- No new Firmware opcode.
- `0x92` remains current-mode selection only.
- `0x00` remains keyboard-authoritative readback.
- Success requires ACK plus readback match.
- Disconnected state permits local draft browsing only; configuration edit entry first attempts connection and must not enter edit state if still offline.
- Existing WD-001 `0x95` and `0x9F` behavior must not regress.

## Non-Goals

- No Firmware changes.
- No eternal workspace changes.
- No Release Batch.
- No installer work.
- No Owner UAT PASS claim.
- No Git write.
- No Java implementation performed by DLA in this alignment step.
