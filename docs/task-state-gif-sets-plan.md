# Task-state dual GIF plan

## Objective

Each Mode stores two GIF sets. Every set can provide a separate animation for the nine IDE states. A double click on the power/Mode key changes the active set for the current Mode.

## Compatible Protocol

Existing `0x82` and `0x83` remain the legacy per-Mode animation interface. New firmware adds:

| Command | Request payload | Response payload |
| --- | --- | --- |
| `0x84` | `mode, set, state, start:u16LE, count:u16LE, interval:u16LE` | ACK |
| `0x85` | `mode, set, state` | `mode, set, state, start, count, interval, maxFrames, activeSet` |
| `0x86` | `mode, set` (`0xFF` queries) | `mode, activeSet` |

`0x90` resets the animation index and triggers LCD rendering immediately. The firmware resolves an unset state through that set's SessionEnd animation, then set A, then the old `pic` metadata.

## Storage And Migration

The existing `pic[3][3]` remains intact. `key_bund_s` adds `task_pic[3][2][9][3]`, `active_pic_set[3]`, and a schema marker. A first boot after upgrade copies each legacy Mode animation into both sets' SessionEnd slot without copying external Flash data, then persists the new metadata.

## Upload And Allocation

All 54 task slots share the existing 74 physical 28,672-byte LCD frame slots. The client reads task metadata before upload, reuses an exclusively owned target range when possible, otherwise selects a contiguous free range. It writes frames through the existing `0x80 + 0x7341` sequence, then commits the slot with `0x84`. A zero frame count clears a slot.

## Verification

1. Cover protocol encoding and parsing for `0x84` through `0x86` while keeping `0x82/0x83` behavior.
2. Build the macOS release app and exercise local GIF selection, upload allocation, state configuration, and set selection.
3. Build the CH582 HEX in MounRiver Studio, flash with `wchisp`, and verify `0x90` state switching, power-key double-click set switching, and persistence after restart.

## Boundaries

The two sets share the existing 74-frame physical capacity. A firmware build requires MounRiver Studio plus the CH58x SDK; the repository does not contain a reproducible command-line compiler.
