# WD-003 Owner Scope Record - CP4D 0x87 Single-Packet Ordinary-Key Readback

Date: 2026-10-07

Owner request:

- Inspect the current firmware implementation for `0x87` ordinary-key readback.
- Adapt the Windows host according to the previously agreed CP4D direction.
- Start integration-test preparation after Windows adapts.
- Do not break earlier WD-003 stages, especially USB `mi_01` transport selection, `0x95` sleep wait time readback, `0x97` side-switch read/write/readback, and existing Shortcut/Macro semantics.

Owner-approved CP4D direction:

- `0x87` reads one `mode + key_index` at a time.
- Successful firmware response is a complete single 64-byte-or-less frame with `CC DD`.
- No fragmentation protocol is added in CP4D.
- Firmware returns real `action_len` and deterministic trimmed `desc_len`, not fixed action/description padding.
- Empty ordinary-key slots are represented as `action_type=0x00`, `action_len=0`.
- Supported ordinary-key action types are shortcut `0x73` and macro `0x74`.
- Oversized stored action/description returns an explicit fail-closed status, currently `0x87 03`, and Windows must not guess or silently truncate.

Boundary:

- This record does not authorize firmware modification from Windows.
- This record does not authorize changes to `0x97`, `0x95`, `0x9F`, USB HID descriptors, BLE lifecycle, task-light commands, firmware flashing/recovery, installer build, release, or formal Owner UAT.
