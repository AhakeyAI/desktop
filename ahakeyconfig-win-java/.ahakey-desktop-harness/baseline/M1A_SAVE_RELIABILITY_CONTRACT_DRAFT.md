# M1a Save Reliability Contract Draft

Status: DLA draft only. Not approved. Not an active change. No production code may be edited from this draft alone.

## Objective

Make Windows save feedback truthful for keyboard configuration:
- do not report device save success from send-only completion;
- keep local draft behavior usable when no device is connected;
- preserve failed device-save drafts for retry, edit, or discard;
- only claim applied/persisted when target firmware evidence supports ACK or readback.

## Sources

Windows receiving repo:
- `DeviceSyncService.writeSequentially()` currently sends commands with short sleeps and no ordinary config response binding.
- Existing UI entry is the current edit/save flow; no new navigation is required.

eternal reference repo:
- `DeviceSyncService.writeSequentially()` uses `executeDeviceTransaction()` and `sendCommandExpecting(frame, frame[2])`.
- `BleManager` adds transaction lock, response token filtering, and timeout handling.
- These are implementation evidence, not an instruction to replace whole classes.

Firmware reference:
- `C:\Users\20825\Desktop\vibe-code\.ahakey-harness\workstreams\X1-INPUT-CONTROL\PRD.md` approves keyboard-authoritative config, write-then-readback, fail-closed advanced editing, and failed draft retention.
- `APP/sub_main/command_solve.c` shows `0x04` and `0x73` do not currently have explicit `command_return(...)` in their branches.
- `APP/sub_main/fram_RC16.c` shows `save_key_bound_data()` erases and writes `key_bund`, but does not return write status to command processing.
- `0x9D` / `0x9F` are present in Firmware contracts/docs but were not found as current `APP/sub_main` implementation branches during this static pass.

## Proposed Migration Boundary

In scope:
- define save result states: local draft saved, device write sent, device ACKed when supported, device readback verified when supported, failed/unknown;
- adjust user-facing save feedback so it does not conflate send completion with persisted device success;
- retain failed device-save draft state for retry/edit/discard;
- use ACK waiting only for commands that the target firmware actually returns;
- add capability/readback gates before any new advanced write semantics.

Out of scope:
- replacing the whole `BleManager`;
- changing KEY1-K4 semantics or adopting eternal's K1 skip behavior;
- adding new firmware commands;
- requiring `0x73` / `0x04` ACK before Firmware explicitly supports it;
- implementing standby, firmware update, app update, OLED layout, or raw F18 routing.

## Existing Entry

The existing save/edit entry is enough. A later DIB may add minimal status text or a small retry/discard prompt, but this draft does not require navigation redesign or component-library changes.

## Target Firmware

Target path: `C:\Users\20825\Desktop\vibe-code`

Target workspace identity at investigation time:
- branch `harness/x1-refactor-main`
- HEAD `e3df33c393db2a9cf5d1a2d7b7c3843125b6864c`
- active Firmware workstream `WS2 / X1-INPUT-CONTROL`
- CP1 not accepted as Windows integration complete; CP3 readback/capability protocol remains locked.

## Old Behavior To Protect

- Existing local draft save behavior must continue when no device is connected.
- Existing KEY1-K4 configuration path must remain intact.
- Basic keyboard input must continue even when advanced save/editing is unknown or disabled.
- Unknown firmware must not receive unsupported advanced write commands.

## Minimum Acceptance

Static/code-level acceptance for first DIB:
- save flow exposes distinct internal outcomes instead of a single send-complete success;
- unsupported or unknown device state does not claim device persistence;
- supported ACK commands use response waiting without forcing ACK expectations on `0x73` / `0x04`;
- failed device result preserves draft and produces retry/edit/discard path;
- no production command IDs are added or changed.

Firmware/device acceptance before calling it real integration:
- target firmware evidence identifies the readback mechanism for saved ordinary config;
- real USB/BLE device test demonstrates write, save, readback match, mismatch failure, and reconnect/persistence behavior;
- old behavior regression confirms KEY1-K4 and existing default table are unchanged.

## Open Items For Owner / Firmware

- Is the first Windows implementation allowed to show "sent, device confirmation unavailable" for current target firmware, or must device save success stay disabled until readback is implemented?
- Which Firmware checkpoint will own the authoritative `0x9D` / `0x9F` implementation or replacement readback contract?
